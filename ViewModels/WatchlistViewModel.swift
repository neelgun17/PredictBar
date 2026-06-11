import SwiftUI
import Combine

/// Owns the watchlist: markets the user is watching for a price target without
/// holding a position. Handles persistence, live price flow (WebSocket + 30s
/// REST refresh), target-crossing alerts with hysteresis, and the add-flow
/// resolution chain (URL/ticker → concrete market).
@MainActor
final class WatchlistViewModel: ObservableObject {
    static let shared = WatchlistViewModel()

    @Published private(set) var items: [WatchlistItem] = [] {
        didSet {
            persist()
            WebSocketManager.shared.setWatchlistTickers(items.map { $0.ticker })
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let userDefaultsKey = "watchlistItems"
    // Last JSON written to UserDefaults. Price ticks mutate only runtime-only
    // fields, so most didSet persists are byte-identical no-ops we can skip.
    private var lastPersistedData: Data?

    private init() {
        if DashboardViewModel.isDemoMode {
            seedDemoItems()
            return
        }

        load()
        WebSocketManager.shared.setWatchlistTickers(items.map { $0.ticker })

        WebSocketManager.shared.priceUpdate
            .receive(on: RunLoop.main)
            .sink { [weak self] quote in
                self?.applyQuote(quote)
            }
            .store(in: &cancellables)

        refreshTimer
            .sink { [weak self] _ in
                self?.refreshQuotes()
            }
            .store(in: &cancellables)

        refreshQuotes()
    }

    // MARK: - Persistence

    private func persist() {
        guard !DashboardViewModel.isDemoMode else { return }
        do {
            let data = try JSONEncoder().encode(items)
            guard data != lastPersistedData else { return }
            lastPersistedData = data
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            Log.alerts.error("Failed to persist watchlist: \(String(describing: error), privacy: .public)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            items = try JSONDecoder().decode([WatchlistItem].self, from: data)
            lastPersistedData = try? JSONEncoder().encode(items)
            Log.alerts.debug("Loaded \(self.items.count) watchlist items.")
        } catch {
            Log.alerts.error("Failed to decode watchlist; resetting: \(String(describing: error), privacy: .public)")
            items = []
        }
    }

    // MARK: - Mutations

    func watch(market: NetworkManager.Market, targetCents: Int, direction: WatchlistItem.Direction) {
        guard !items.contains(where: { $0.ticker == market.ticker }) else { return }

        var item = WatchlistItem(
            ticker: market.ticker,
            title: market.title,
            subtitle: market.subtitle,
            eventTicker: market.eventTicker,
            seriesTicker: market.seriesTicker,
            targetCents: targetCents,
            direction: direction
        )
        item.currentYesCents = WatchlistItem.displayPriceCents(
            lastPrice: market.lastPrice, yesBid: market.yesBid, yesAsk: market.yesAsk
        )
        item.status = market.status
        // Fallback URL until the full series/slug/event link resolves below
        if let seriesTicker = market.seriesTicker {
            item.marketUrl = DashboardViewModel.kalshiMarketURL(path: ["markets", seriesTicker.lowercased()])
        }
        if let price = item.currentYesCents {
            item.armed = Self.initialArmed(direction: direction, targetCents: targetCents, priceCents: price)
        }
        items.append(item)
        Log.alerts.info("Watching \(market.ticker, privacy: .public) \(direction.symbol) \(targetCents)¢")

        resolveMarketUrl(for: item.id, eventTicker: market.eventTicker)
    }

    /// A target the price already satisfies at add/edit time starts disarmed —
    /// no instant notification for a crossing that never happened. The item
    /// re-arms once the price moves past the buffer and alerts on the next
    /// genuine crossing.
    nonisolated static func initialArmed(
        direction: WatchlistItem.Direction,
        targetCents: Int,
        priceCents: Int
    ) -> Bool {
        !evaluateCrossing(direction: direction, targetCents: targetCents, priceCents: priceCents, armed: true).fire
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Edits the target; re-arms the alert and clears the hit badge since the
    /// new target hasn't been hit yet.
    func updateTarget(id: UUID, targetCents: Int, direction: WatchlistItem.Direction) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].targetCents = targetCents
        items[index].direction = direction
        if let price = items[index].currentYesCents {
            items[index].armed = Self.initialArmed(direction: direction, targetCents: targetCents, priceCents: price)
        } else {
            items[index].armed = true
        }
        items[index].lastHitAt = nil
    }

    /// Drops watchlist entries for markets the user now holds a position in
    /// (called on every portfolio refresh).
    func pruneHeldTickers(_ positionTickers: [String]) {
        let held = Set(positionTickers)
        let removed = items.filter { held.contains($0.ticker) }
        guard !removed.isEmpty else { return }
        for item in removed {
            Log.alerts.info("Removing \(item.ticker, privacy: .public) from watchlist: position opened.")
        }
        items.removeAll { held.contains($0.ticker) }
    }

    // MARK: - Price flow

    private func applyQuote(_ quote: WebSocketManager.TickerQuote) {
        guard let index = items.firstIndex(where: { $0.ticker == quote.ticker }) else { return }
        let price = WatchlistItem.displayPriceCents(
            lastPrice: quote.lastPrice, yesBid: quote.yesBid, yesAsk: quote.yesAsk
        )
        guard let price else { return }
        items[index].currentYesCents = price
        checkItem(withId: items[index].id)
    }

    /// REST fallback so quiet markets (no trades, hence no WebSocket ticks) are
    /// still checked every 30 seconds, and market status stays current.
    private func refreshQuotes() {
        guard SettingsViewModel.shared.hasCredentials else { return }
        for item in items {
            NetworkManager.shared.fetchMarket(ticker: item.ticker) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self,
                          case .success(let market) = result,
                          let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                    self.items[index].status = market.status
                    if let price = WatchlistItem.displayPriceCents(
                        lastPrice: market.lastPrice, yesBid: market.yesBid, yesAsk: market.yesAsk
                    ) {
                        self.items[index].currentYesCents = price
                    }
                    self.checkItem(withId: item.id)
                }
            }
        }
    }

    // MARK: - Crossing checks

    /// Pure crossing/hysteresis evaluation. Fires when the price reaches the
    /// target in the watched direction while armed; re-arms once the price moves
    /// `rearmBufferCents` past the target the other way (mirrors the 3¢ stop-loss
    /// buffer), so a price hovering at the target can't flap alerts.
    nonisolated static func evaluateCrossing(
        direction: WatchlistItem.Direction,
        targetCents: Int,
        priceCents: Int,
        armed: Bool,
        rearmBufferCents: Int = 3
    ) -> (fire: Bool, armed: Bool) {
        switch direction {
        case .atOrBelow:
            if armed && priceCents <= targetCents { return (true, false) }
            if !armed && priceCents >= targetCents + rearmBufferCents { return (false, true) }
        case .atOrAbove:
            if armed && priceCents >= targetCents { return (true, false) }
            if !armed && priceCents <= targetCents - rearmBufferCents { return (false, true) }
        }
        return (false, armed)
    }

    private func checkItem(withId id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        guard !item.isClosed, let price = item.currentYesCents else { return }

        let result = Self.evaluateCrossing(
            direction: item.direction,
            targetCents: item.targetCents,
            priceCents: price,
            armed: item.armed
        )
        guard result.fire || result.armed != item.armed else { return }

        item.armed = result.armed
        if result.fire {
            item.lastHitAt = Date()

            // 5-minute dedupe (matches position alerts) so rapid re-arm/re-fire
            // cycles around the target can't spam notifications.
            let minTimeBetweenAlerts: TimeInterval = 300
            let shouldNotify: Bool
            if let last = item.lastNotifiedAt {
                shouldNotify = Date().timeIntervalSince(last) >= minTimeBetweenAlerts
            } else {
                shouldNotify = true
            }

            if shouldNotify, let dashboard = DashboardViewModel.shared {
                let title = dashboard.formatNotificationTitle(
                    marketTitle: item.title,
                    ticker: item.ticker,
                    alertType: DashboardViewModel.AlertType.watchTarget.rawValue,
                    emoji: DashboardViewModel.AlertType.watchTarget.emoji
                )
                let body = "Yes @ \(price)¢ • Target \(item.direction.symbol) \(item.targetCents)¢"
                dashboard.queueAlert(
                    ticker: item.ticker,
                    type: .watchTarget,
                    title: title,
                    body: body,
                    url: item.marketUrl
                )
                item.lastNotifiedAt = Date()
                Log.alerts.info("Watch target hit for \(item.ticker, privacy: .public) at \(price)¢")
            }
        }

        items[index] = item
    }

    // MARK: - Add-flow resolution

    enum ResolutionResult {
        case market(NetworkManager.Market)
        case candidates([NetworkManager.Market])
    }

    enum AddError: LocalizedError, Equatable {
        case invalidInput(String)
        case notFound(String)
        case marketClosed
        case alreadyWatching
        case alreadyHolding
        case network(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let reason): return reason
            case .notFound(let query): return "No market found for “\(query)”."
            case .marketClosed: return "This market is closed."
            case .alreadyWatching: return "Already on your watchlist."
            case .alreadyHolding: return "You hold a position in this market — use position alerts instead."
            case .network(let message): return message
            }
        }
    }

    /// Resolves raw user input (kalshi.com URL or ticker) into a single market
    /// or a list of candidates for the user to pick from.
    func resolve(input raw: String, completion: @escaping (Result<ResolutionResult, AddError>) -> Void) {
        switch WatchlistInputParser.parse(raw) {
        case .invalid(let reason):
            completion(.failure(.invalidInput(reason)))

        case .marketOrEventTicker(let ticker):
            // Try as a market ticker first, then fan out as an event ticker.
            NetworkManager.shared.fetchMarket(ticker: ticker) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let market):
                        completion(self.validated(market).map { ResolutionResult.market($0) })
                    case .failure:
                        self.resolveMarkets(eventTicker: ticker, seriesTicker: nil, query: ticker, completion: completion)
                    }
                }
            }

        case .url(let seriesTicker, let eventTicker):
            if let eventTicker {
                resolveMarkets(eventTicker: eventTicker, seriesTicker: nil, query: eventTicker, completion: completion)
            } else if let seriesTicker {
                resolveMarkets(eventTicker: nil, seriesTicker: seriesTicker, query: seriesTicker, completion: completion)
            } else {
                completion(.failure(.invalidInput("Couldn't find a market in that URL.")))
            }
        }
    }

    private func resolveMarkets(
        eventTicker: String?,
        seriesTicker: String?,
        query: String,
        completion: @escaping (Result<ResolutionResult, AddError>) -> Void
    ) {
        NetworkManager.shared.fetchMarkets(eventTicker: eventTicker, seriesTicker: seriesTicker) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let markets):
                    let open = markets.filter { !Self.isClosedStatus($0.status) }
                    switch open.count {
                    case 0:
                        completion(.failure(.notFound(query)))
                    case 1:
                        completion(self.validated(open[0]).map { ResolutionResult.market($0) })
                    default:
                        completion(.success(.candidates(open)))
                    }
                case .failure(let error):
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .unauthorized, .forbidden:
                            // Credential problems must surface as such, not as a missing market
                            completion(.failure(.network(apiError.errorDescription ?? "Kalshi API error.")))
                        case .server, .unexpectedResponse:
                            completion(.failure(.notFound(query)))
                        }
                    } else {
                        completion(.failure(.network(DashboardViewModel.userFacingMessage(for: error))))
                    }
                }
            }
        }
    }

    /// Final gate before a market can be watched; also used when the user picks
    /// from the candidates list.
    func validated(_ market: NetworkManager.Market) -> Result<NetworkManager.Market, AddError> {
        if Self.isClosedStatus(market.status) {
            return .failure(.marketClosed)
        }
        if items.contains(where: { $0.ticker == market.ticker }) {
            return .failure(.alreadyWatching)
        }
        if DashboardViewModel.shared?.positions.contains(where: { $0.ticker == market.ticker }) == true {
            return .failure(.alreadyHolding)
        }
        return .success(market)
    }

    nonisolated private static func isClosedStatus(_ status: String?) -> Bool {
        guard let status else { return false }
        return ["finalized", "settled", "closed", "determined"].contains(status)
    }

    /// Resolves the full kalshi.com market URL (series/slug/event) the same way
    /// `DashboardViewModel.fetchData` does for positions.
    private func resolveMarketUrl(for id: UUID, eventTicker: String) {
        NetworkManager.shared.fetchEvent(eventTicker: eventTicker) { [weak self] result in
            DispatchQueue.main.async {
                guard case .success(let event) = result else { return }
                if let index = self?.items.firstIndex(where: { $0.id == id }) {
                    self?.items[index].seriesTicker = event.seriesTicker
                }
                NetworkManager.shared.fetchSeries(seriesTicker: event.seriesTicker) { [weak self] result in
                    DispatchQueue.main.async {
                        guard case .success(let series) = result,
                              let index = self?.items.firstIndex(where: { $0.id == id }) else { return }
                        let slug = series.title
                            .lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                            .folding(options: .diacriticInsensitive, locale: .current)
                            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(.init(charactersIn: "-")))
                            .joined()
                        if let url = DashboardViewModel.kalshiMarketURL(path: [
                            "markets",
                            series.ticker.lowercased(),
                            slug,
                            event.eventTicker.lowercased()
                        ]) {
                            self?.items[index].marketUrl = url
                        }
                    }
                }
            }
        }
    }

    // MARK: - Demo mode

    // Curated watchlist for marketing screenshots. Activated via PREDICTBAR_DEMO=1.
    private func seedDemoItems() {
        var fed = WatchlistItem(
            ticker: "KXFEDCUT-26JUL",
            title: "Will the Fed cut rates in July 2026?",
            subtitle: "Rate cut",
            targetCents: 25,
            direction: .atOrBelow
        )
        fed.currentYesCents = 34
        fed.status = "active"

        var eth = WatchlistItem(
            ticker: "KXETH-26SEP-5K",
            title: "Will Ethereum hit $5k by September 2026?",
            subtitle: "Above $5,000",
            targetCents: 50,
            direction: .atOrBelow
        )
        eth.currentYesCents = 48
        eth.status = "active"
        eth.armed = false
        eth.lastHitAt = Date()

        items = [fed, eth]
    }
}

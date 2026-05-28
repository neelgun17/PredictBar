import SwiftUI
import Combine
import UserNotifications
@MainActor
class DashboardViewModel: ObservableObject {
    nonisolated(unsafe) static var shared: DashboardViewModel?

    /// Builds a kalshi.com URL by appending path components through `URLComponents`,
    /// which percent-encodes each segment. Prevents API-controlled tickers/slugs
    /// from injecting `?`, `#`, or `/..` into the final URL.
    nonisolated static func kalshiMarketURL(path components: [String]) -> URL? {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "kalshi.com"
        url.path = "/" + components.joined(separator: "/")
        return url.url
    }

    @Published var totalCashOutValue: Double = 0.0
    @Published var overallROI: Double = 0.0
    @Published var overallPnL: Double = 0.0
    @Published var portfolioValue: Double = 0.0
    @Published var accountBalance: Double = 0.0
    @Published var menuBarText: String = ""
    @Published var positions: [Position] = []
    @Published var isConnected: Bool = false
    @Published var fills: [Fill] = []
    @Published var tradeMetrics: TradeMetrics?
    @Published var isLoadingFills: Bool = false
    @Published var lastFetchError: String?

    private var cancellables = Set<AnyCancellable>()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    static var isDemoMode: Bool {
        ProcessInfo.processInfo.environment["PREDICTBAR_DEMO"] == "1"
    }

    init() {
        loadAlertStatesFromUserDefaults()
        loadCachedFills()
        setupBindings()
        if Self.isDemoMode {
            loadDemoData()
            return
        }
        fetchData()
        fetchTradeHistoryIfNeeded()
        WebSocketManager.shared.connect()
    }

    deinit {
        groupingTimer?.invalidate()
    }

    private func setupBindings() {
        WebSocketManager.shared.$isConnected
            .receive(on: RunLoop.main)
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)
            
        WebSocketManager.shared.priceUpdate
            .receive(on: RunLoop.main)
            .sink { [weak self] quote in
                self?.updatePrice(with: quote)
            }
            .store(in: &cancellables)
//            .store(in: &cancellables)
            
        // Auto-refresh data every 30 seconds
        timer
            .sink { [weak self] _ in
                self?.fetchData()
            }
            .store(in: &cancellables)
            
        // Listen to Settings changes
        SettingsViewModel.shared.$menuBarMetric
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarText() }
            .store(in: &cancellables)
            
        SettingsViewModel.shared.$notificationsEnabled
            .sink { [weak self] _ in self?.checkThresholds() }
            .store(in: &cancellables)
            
        SettingsViewModel.shared.$highROIThreshold
            .sink { [weak self] _ in self?.checkThresholds() }
            .store(in: &cancellables)
            
        SettingsViewModel.shared.$lowROIThreshold
            .sink { [weak self] _ in self?.checkThresholds() }
            .store(in: &cancellables)
            
        // Listen for credential updates to auto-refresh data
        SettingsViewModel.shared.$hasCredentials
            .receive(on: RunLoop.main)
            .sink { [weak self] hasCreds in
                if hasCreds {
                    print("🔑 Credentials updated, refreshing data...")
                    self?.fetchData()
                    WebSocketManager.shared.connect()
                } else {
                    print("🔒 Credentials deleted, clearing data...")
                    self?.positions = []
                    self?.portfolioValue = 0.0
                    self?.accountBalance = 0.0
                    self?.menuBarText = "PredictBar"
                    self?.lastFetchError = nil
                    WebSocketManager.shared.disconnect()
                }
            }
            .store(in: &cancellables)
    }
    
    func fetchData() {
        if Self.isDemoMode { return }
        // Skip fetches when credentials are missing; the UI shows a connect CTA instead.
        guard SettingsViewModel.shared.hasCredentials else { return }

        // Fetch Balance
        NetworkManager.shared.fetchBalance { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.accountBalance = Double(response.balance) / 100.0
                    self?.updateMenuBarText()
                    self?.portfolioValue = Double(response.portfolioValue) / 100.0
                case .failure(let error):
                    self?.lastFetchError = Self.userFacingMessage(for: error)
                }
            }
        }

        NetworkManager.shared.fetchPortfolio { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let positions):
                    self?.lastFetchError = nil
                    // Filter out positions with 0 quantity (sold out)
                    let activePositions = positions.filter { $0.position != 0 }
                    
                    // Merge with existing positions to preserve price, history, and metadata
                    // This prevents ROI from dropping to -100% (0 price) during the refresh cycle
                    let mergedPositions = activePositions.map { newPos -> Position in
                        if let existing = self?.positions.first(where: { $0.ticker == newPos.ticker }) {
                            var merged = newPos
                            merged.currentPrice = existing.currentPrice
                            merged.history = existing.history
                            merged.title = existing.title
                            merged.subtitle = existing.subtitle
                            merged.eventTicker = existing.eventTicker
                            merged.marketUrl = existing.marketUrl
                            merged.seriesTicker = existing.seriesTicker
                            merged.seriesTitle = existing.seriesTitle
                            merged.status = existing.status
                            merged.lastROI = existing.lastROI
                            return merged
                        }
                        return newPos
                    }
                    
                    self?.positions = mergedPositions
                    self?.calculateTotals()
                    
                    // Subscribe to WebSocket updates for these tickers
                    let tickers = positions.map { $0.ticker }
                    WebSocketManager.shared.subscribeToTickers(tickers)
                    
                    // Fetch market details for each position
                    for (_, position) in positions.enumerated() {
                        NetworkManager.shared.fetchMarket(ticker: position.ticker) { [weak self] result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let market):
                                    // Find the current index of this position safely
                                    if let currentIdx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                        var updatedPosition = self?.positions[currentIdx]
                                        
                                        updatedPosition?.title = market.title
                                        updatedPosition?.status = market.status
                                        
                                        // Filter out closed/settled/finalized/determined/pending positions (User wants only live events)
                                        if let status = market.status, (status == "finalized" || status == "settled" || status == "closed" || status == "determined" || status == "pending") {
                                            self?.positions.remove(at: currentIdx)
                                            self?.calculateTotals()
                                            return
                                        }
                                        
                                        // Use API subtitle, or fallback to ticker suffix (e.g., "PHI" from "...-PHI")
                                        if let sub = market.subtitle, !sub.isEmpty {
                                            updatedPosition?.subtitle = sub
                                        } else {
                                            updatedPosition?.subtitle = position.ticker.components(separatedBy: "-").last
                                        }
                                        
                                        updatedPosition?.eventTicker = market.eventTicker
                                        
                                        // Update price logic
                                        // If market is active, use the best available bid (executable sell price)
                                        // If market is closed/determined, use lastPrice because bids are likely pulled (0.0)
                                        let isActive = (market.status == "active")
                                        
                                        let yesBid = market.yesBid.map { Double($0) / 100.0 }
                                        let noBid = market.noBid.map { Double($0) / 100.0 }
                                        let yesAsk = market.yesAsk.map { Double($0) / 100.0 }
                                        let lastPrice = market.lastPrice.map { Double($0) / 100.0 }

                                        // Store all bid/ask prices for arbitrage detection
                                        updatedPosition?.yesBid = yesBid
                                        updatedPosition?.yesAsk = yesAsk
                                        updatedPosition?.noBid = noBid
                                        updatedPosition?.noAsk = market.noAsk.map { Double($0) / 100.0 }

                                        if !isActive, let last = lastPrice, last > 0 {
                                            // Market is closed/settling, trust the last trade price
                                            updatedPosition?.currentPrice = last
                                        } else {
                                            // Market is active (or lastPrice is missing), use executable bid
                                            if let executable = updatedPosition?.executableSellPrice(
                                                yesBid: yesBid,
                                                noBid: noBid,
                                                yesAsk: yesAsk,
                                                lastPrice: lastPrice
                                            ) {
                                                updatedPosition?.currentPrice = executable
                                            }
                                        }
                                        
                                        // Set fallback URL immediately using series ticker (if available)
                                        if let seriesTicker = market.seriesTicker {
                                            updatedPosition?.seriesTicker = seriesTicker
                                            if let url = Self.kalshiMarketURL(path: ["markets", seriesTicker.lowercased()]) {
                                                updatedPosition?.marketUrl = url
                                            }
                                        }
                                        
                                        // Save back to the array
                                        if let finalPosition = updatedPosition {
                                            self?.positions[currentIdx] = finalPosition
                                            self?.calculateTotals()
                                            
                                            // Fetch Event details to get the correct URL slug
                                            let eventTicker = market.eventTicker
                                            NetworkManager.shared.fetchEvent(eventTicker: eventTicker) { [weak self] result in
                                                    DispatchQueue.main.async {
                                                        switch result {
                                                        case .success(let event):
                                                            // Store series ticker for later use
                                                            if let idx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                                                self?.positions[idx].seriesTicker = event.seriesTicker
                                                            }
                                                            
                                                            // Fetch candlestick history once we have the series ticker
                                                            NetworkManager.shared.fetchMarketHistory(
                                                                seriesTicker: event.seriesTicker,
                                                                marketTicker: position.marketTicker
                                                            ) { [weak self] result in
                                                                DispatchQueue.main.async {
                                                                    if case .success(let history) = result {
                                                                        if let idx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                                                            self?.positions[idx].history = history
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                            
                                                            // Fetch Series to get the slug
                                                            NetworkManager.shared.fetchSeries(seriesTicker: event.seriesTicker) { [weak self] result in
                                                                DispatchQueue.main.async {
                                                                    switch result {
                                                                    case .success(let series):
                                                                        // Construct URL: https://kalshi.com/markets/{series}/{slug}/{event}
                                                                        let slug = series.title
                                                                            .lowercased()
                                                                            .replacingOccurrences(of: " ", with: "-")
                                                                            .folding(options: .diacriticInsensitive, locale: .current)
                                                                            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(.init(charactersIn: "-")))
                                                                            .joined()
                                                                        
                                                                        if let url = Self.kalshiMarketURL(path: [
                                                                            "markets",
                                                                            series.ticker.lowercased(),
                                                                            slug,
                                                                            event.eventTicker.lowercased()
                                                                        ]) {
                                                                            // Update position safely
                                                                            if let idx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                                                                self?.positions[idx].marketUrl = url
                                                                                self?.positions[idx].seriesTitle = series.title
                                                                            }
                                                                        }
                                                                        
                                                                    case .failure:
                                                                        break
                                                                    }
                                                                }
                                                            }
                                                        case .failure:
                                                            break
                                                        }
                                                    }
                                                }
                                        }
                                    }
                                case .failure:
                                    break
                                }
                            }
                        }
                    }
                case .failure(let error):
                    self?.lastFetchError = Self.userFacingMessage(for: error)
                }
            }
        }
    }

    nonisolated static func userFacingMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Kalshi API error."
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "No internet connection."
            case NSURLErrorTimedOut:
                return "Request timed out. Try again."
            case NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication:
                return "Authentication failed. Check your API credentials in Settings."
            default:
                return "Network error: \(ns.localizedDescription)"
            }
        }
        if error is DecodingError {
            return "Unexpected response from Kalshi. The API format may have changed."
        }
        return ns.localizedDescription
    }

    // Curated portfolio for marketing screenshots. Activated via PREDICTBAR_DEMO=1.
    private func loadDemoData() {
        struct DemoSpec {
            let ticker: String
            let title: String
            let subtitle: String
            let qty: Int
            let avg: Double
            let current: Double
        }
        let specs: [DemoSpec] = [
            .init(ticker: "KXNBAMVP-26-JOKIC", title: "Will Nikola Jokić win 2026 NBA MVP?", subtitle: "Nikola Jokić", qty: 50, avg: 0.22, current: 0.41),
            .init(ticker: "KXWORLDCUP-26-FRA", title: "Will France win the 2026 Men's World Cup?", subtitle: "France", qty: 30, avg: 0.18, current: 0.27),
            .init(ticker: "KXBTC-EOY26-150K", title: "Will Bitcoin close above $150k by EOY 2026?", subtitle: "Above $150,000", qty: 25, avg: 0.30, current: 0.44),
            .init(ticker: "KXFED-DEC26-CUT", title: "Will the Fed cut rates at the Dec 2026 meeting?", subtitle: "Rate cut", qty: 40, avg: 0.55, current: 0.48),
        ]

        positions = specs.map { s in
            let exposureCents = Int((s.avg * Double(s.qty) * 100).rounded())
            var p = Position(
                ticker: s.ticker,
                position: s.qty,
                feesPaid: 0,
                realizedPnl: 0,
                totalTraded: exposureCents,
                marketExposure: exposureCents
            )
            p.title = s.title
            p.subtitle = s.subtitle
            p.status = "active"
            p.currentPrice = s.current
            p.yesBid = s.current
            p.yesAsk = min(0.99, s.current + 0.01)
            p.noBid = max(0.01, 1 - s.current - 0.01)
            p.noAsk = 1 - s.current
            let steps = 24
            p.history = (0..<steps).map { i in
                let t = Double(i) / Double(steps - 1)
                return s.avg + (s.current - s.avg) * t
            }
            return p
        }

        accountBalance = 500.00
        calculateTotals()
        portfolioValue = accountBalance + totalCashOutValue
        updateMenuBarText()
    }

    private func calculateTotals() {
        // Portfolio-level realized ROI after fees, based on actual cost basis and current net proceeds
        let totalCost = positions.reduce(0.0) { $0 + $1.totalCostBasis }
        let totalNetProceeds = positions.reduce(0.0) { $0 + $1.netProceedsAfterFees }
        
        totalCashOutValue = totalNetProceeds
        overallPnL = totalNetProceeds - totalCost
        
        if totalCost > 0 {
            overallROI = overallPnL / totalCost
        } else {
            overallROI = 0.0
        }
        
        updateMenuBarText()
        checkThresholds()
    }
    
    func updateMenuBarText() {
        let metric = SettingsViewModel.shared.menuBarMetric
        
        switch metric {
        case "Cash Out":
            menuBarText = totalCashOutValue.formatted(.currency(code: "USD"))
        case "ROI":
            menuBarText = overallROI.formatted(.percent.precision(.fractionLength(1)))
        case "PnL":
            menuBarText = overallPnL.formatted(.currency(code: "USD"))
        case "Portfolio":
            menuBarText = portfolioValue.formatted(.currency(code: "USD"))
        case "Balance":
            menuBarText = accountBalance.formatted(.currency(code: "USD"))
        default:
            menuBarText = totalCashOutValue.formatted(.currency(code: "USD"))
        }
    }
    
    private var lastNotificationTime: Date?
    
    // ROI State for transitioning alerts (Low, Neutral, High)
    enum ROIState: String, Codable {
        case low
        case neutral
        case high
    }

    // Alert types for notification grouping
    enum AlertType: String {
        case highROI = "High ROI"
        case lowROI = "Low ROI"
        case targetProfit = "Profit Target"
        case targetPrice = "Price Target"
        case arbitrage = "Arbitrage"
        case stopLoss = "Stop-Loss"

        var emoji: String {
            switch self {
            case .highROI: return "🚀"
            case .lowROI: return "📉"
            case .targetProfit: return "💰"
            case .targetPrice: return "🎯"
            case .arbitrage: return "⚖️"
            case .stopLoss: return "🛑"
            }
        }
    }

    // Pending alert for grouping
    struct PendingAlert {
        let ticker: String
        let type: AlertType
        let title: String
        let body: String
        let url: URL?
        let timestamp: Date
    }

    // Notification grouping state
    private var pendingAlerts: [PendingAlert] = []
    private var groupingTimer: Timer? = nil
    private let alertGroupingWindow: TimeInterval = 2.0 // Group alerts within 2 seconds

    // Track the last state of each position to prevent spamming notifications
    // Key: Ticker, Value: State
    private var positionAlertStates: [String: PositionAlertState] = [:] {
        didSet {
            persistAlertStatesToUserDefaults()
        }
    }

    struct PositionAlertState: Codable {
        var roiState: ROIState = .neutral
        var lastHighROIAlertTime: Date? = nil
        var lastLowROIAlertTime: Date? = nil
        var isAboveTargetProfit: Bool = false
        var isAboveTargetPrice: Bool = false
        var lastArbitrageAlertTime: Date? = nil
        var lastArbitrageProfit: Double? = nil

        // Stop-loss state tracking
        var stopLossTriggered: Bool = false       // True when threshold breached
        var lastStopLossAlertTime: Date? = nil    // For 5-minute deduplication
    }

    // MARK: - Alert State Persistence

    private func persistAlertStatesToUserDefaults() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(positionAlertStates)
            UserDefaults.standard.set(data, forKey: "positionAlertStates")
        } catch {
            print("⚠️ Failed to persist alert states: \(error)")
        }
    }

    private func loadAlertStatesFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: "positionAlertStates") else {
            print("📊 No persisted alert states found, starting fresh")
            return
        }

        do {
            let decoder = JSONDecoder()
            positionAlertStates = try decoder.decode([String: PositionAlertState].self, from: data)
            print("✅ Loaded alert states for \(positionAlertStates.count) positions")
        } catch {
            print("⚠️ Failed to decode alert states, resetting: \(error)")
            positionAlertStates = [:]
        }
    }

    private func checkThresholds() {
        let settingsVM = SettingsViewModel.shared
        
        // 1. Check Global Portfolio ROI (if notifications enabled globally)
        if settingsVM.notificationsEnabled {
            checkPortfolioThresholds()
        }
        
        // 2. Check Individual Positions
        for index in positions.indices {
            var position = positions[index]
            let ticker = position.ticker
            let settings = settingsVM.getAlertSettings(for: ticker)
            
            // Skip if alerts are disabled for this position
            if !settings.isEnabled { continue }
            
            // Determine effective thresholds
            let highThreshold = settings.useGlobal ? settingsVM.highROIThreshold : (settings.highROI ?? settingsVM.highROIThreshold)
            let lowThreshold = settings.useGlobal ? settingsVM.lowROIThreshold : (settings.lowROI ?? settingsVM.lowROIThreshold)
            let targetProfit = settings.targetProfit
            let targetPrice = settings.targetPrice
            
            // Skip if price hasn't loaded yet (default is 0.0)
            if position.currentPrice == 0 { continue }
            
            let newROI = position.realizedROI * 100.0
            
            handleAlerts(for: &position, newROI: newROI, highThreshold: highThreshold, lowThreshold: lowThreshold, targetProfit: targetProfit, targetPrice: targetPrice)

            // Check for arbitrage opportunities
            checkArbitrageOpportunity(for: &position)

            // Check for stop-loss threshold breaches
            checkStopLoss(for: &position)

            // Update lastROI (still useful for debugging or other logic, but state drives alerts now)
            position.lastROI = newROI
            positions[index] = position
        }
    }
    
    private func handleAlerts(for position: inout Position, newROI: Double, highThreshold: Double, lowThreshold: Double, targetProfit: Double?, targetPrice: Double?) {
        let ticker = position.ticker
        var state = positionAlertStates[ticker] ?? PositionAlertState()
        let currentState = state.roiState

        // Determine new state based on thresholds
        // Note: We use a hysteresis or simple transition.
        // Requirement: "fire a notification when transitioning neutral→high or neutral→low, and reset when back in neutral"

        var newState: ROIState = currentState

        // Hysteresis Buffer: 3%
        // Prevents "flapping" alerts when ROI hovers near the threshold.
        // You must drop 3% below the High threshold (or rise 3% above Low) to reset to Neutral.
        let buffer = 3.0

        if newROI >= highThreshold {
            newState = .high
        } else if newROI <= lowThreshold {
            newState = .low
        } else {
            // We are in the "middle" zone (between Low and High thresholds)

            if currentState == .high {
                // Only reset to Neutral if we drop significantly below the threshold
                if newROI < (highThreshold - buffer) {
                    newState = .neutral
                } else {
                    newState = .high // Maintain High state (hysteresis)
                }
            } else if currentState == .low {
                // Only reset to Neutral if we rise significantly above the threshold
                if newROI > (lowThreshold + buffer) {
                    newState = .neutral
                } else {
                    newState = .low // Maintain Low state (hysteresis)
                }
            } else {
                newState = .neutral
            }
        }

        // Time-based deduplication: 5 minutes minimum between alerts
        let minTimeBetweenAlerts: TimeInterval = 300 // 5 minutes

        // Check transitions with time-based deduplication
        if currentState == .neutral && newState == .high {
            let shouldSend: Bool
            if let lastAlert = state.lastHighROIAlertTime {
                shouldSend = Date().timeIntervalSince(lastAlert) >= minTimeBetweenAlerts
            } else {
                shouldSend = true
            }

            if shouldSend {
                let title = formatNotificationTitle(
                    marketTitle: position.title,
                    ticker: position.ticker,
                    alertType: AlertType.highROI.rawValue,
                    emoji: AlertType.highROI.emoji
                )
                let body = formatNotificationBody(
                    roi: position.realizedROI,
                    pnl: position.realizedPnL,
                    currentPrice: position.currentPrice
                )
                queueAlert(
                    ticker: position.ticker,
                    type: .highROI,
                    title: title,
                    body: body,
                    url: position.marketUrl
                )
                state.lastHighROIAlertTime = Date()
            }
        } else if currentState == .neutral && newState == .low {
            let shouldSend: Bool
            if let lastAlert = state.lastLowROIAlertTime {
                shouldSend = Date().timeIntervalSince(lastAlert) >= minTimeBetweenAlerts
            } else {
                shouldSend = true
            }

            if shouldSend {
                let title = formatNotificationTitle(
                    marketTitle: position.title,
                    ticker: position.ticker,
                    alertType: AlertType.lowROI.rawValue,
                    emoji: AlertType.lowROI.emoji
                )
                let body = formatNotificationBody(
                    roi: position.realizedROI,
                    pnl: position.realizedPnL,
                    currentPrice: position.currentPrice
                )
                queueAlert(
                    ticker: position.ticker,
                    type: .lowROI,
                    title: title,
                    body: body,
                    url: position.marketUrl
                )
                state.lastLowROIAlertTime = Date()
            }
        }

        // Check Target Profit (One-off)
        if let target = targetProfit {
            if position.realizedPnL >= target {
                if !state.isAboveTargetProfit {
                    let title = formatNotificationTitle(
                        marketTitle: position.title,
                        ticker: position.ticker,
                        alertType: AlertType.targetProfit.rawValue,
                        emoji: AlertType.targetProfit.emoji
                    )
                    let body = formatNotificationBody(
                        roi: position.realizedROI,
                        pnl: position.realizedPnL,
                        currentPrice: position.currentPrice,
                        targetValue: target
                    )
                    queueAlert(
                        ticker: position.ticker,
                        type: .targetProfit,
                        title: title,
                        body: body,
                        url: position.marketUrl
                    )
                    state.isAboveTargetProfit = true
                }
            } else {
                if state.isAboveTargetProfit {
                    state.isAboveTargetProfit = false
                }
            }
        }

        // Check Target Price (One-off)
        if let target = targetPrice {
            let currentPrice = position.currentPrice
            // Target Price is in cents (e.g. 50 for 50c). Current price is dollars (0.50).
            if (currentPrice * 100) >= target {
                if !state.isAboveTargetPrice {
                    let title = formatNotificationTitle(
                        marketTitle: position.title,
                        ticker: position.ticker,
                        alertType: AlertType.targetPrice.rawValue,
                        emoji: AlertType.targetPrice.emoji
                    )
                    let body = formatNotificationBody(
                        roi: position.realizedROI,
                        pnl: position.realizedPnL,
                        currentPrice: position.currentPrice,
                        targetValue: target / 100.0 // Convert cents to dollars
                    )
                    queueAlert(
                        ticker: position.ticker,
                        type: .targetPrice,
                        title: title,
                        body: body,
                        url: position.marketUrl
                    )
                    state.isAboveTargetPrice = true
                }
            } else {
                if state.isAboveTargetPrice {
                    state.isAboveTargetPrice = false
                }
            }
        }

        // Update state in dictionary (after all checks)
        state.roiState = newState
        positionAlertStates[ticker] = state
    }

    private func checkArbitrageOpportunity(for position: inout Position) {
        let ticker = position.ticker
        var state = positionAlertStates[ticker] ?? PositionAlertState()

        // Get settings
        let minProfit = SettingsViewModel.shared.minimumArbitrageProfit
        let settings = SettingsViewModel.shared.getAlertSettings(for: ticker)

        // Skip if disabled or market not active
        guard settings.isEnabled, settings.arbitrageEnabled, position.status == "active" else {
            position.lastArbitrageOpportunity = nil
            return
        }

        // Detect arbitrage
        if let opportunity = position.detectArbitrage(minimumProfit: minProfit) {
            position.lastArbitrageOpportunity = opportunity

            // Determine if we should notify
            var shouldNotify = false
            let minTimeBetweenAlerts: TimeInterval = 300 // 5 minutes

            if let lastAlert = state.lastArbitrageAlertTime,
               let lastProfit = state.lastArbitrageProfit {
                let timeSinceLastAlert = Date().timeIntervalSince(lastAlert)
                let profitIncrease = opportunity.guaranteedProfit - lastProfit

                shouldNotify = timeSinceLastAlert >= minTimeBetweenAlerts && profitIncrease >= 1.0
            } else {
                shouldNotify = true  // First detection
            }

            if shouldNotify {
                let title = formatNotificationTitle(
                    marketTitle: position.title,
                    ticker: position.ticker,
                    alertType: AlertType.arbitrage.rawValue,
                    emoji: AlertType.arbitrage.emoji
                )

                let body = "Guaranteed: +\(opportunity.guaranteedProfit.formatted(.currency(code: "USD"))) " +
                           "(\(opportunity.profitPerContract.formatted(.currency(code: "USD")))/contract) • " +
                           "Buy opposite @ \(opportunity.oppositeSidePrice.formatted(.currency(code: "USD")))"

                queueAlert(
                    ticker: position.ticker,
                    type: .arbitrage,
                    title: title,
                    body: body,
                    url: position.marketUrl
                )

                state.lastArbitrageAlertTime = Date()
                state.lastArbitrageProfit = opportunity.guaranteedProfit
            }
        } else {
            position.lastArbitrageOpportunity = nil
        }

        positionAlertStates[ticker] = state
    }

    private func checkStopLoss(for position: inout Position) {
        let ticker = position.ticker
        var state = positionAlertStates[ticker] ?? PositionAlertState()

        // Get stop-loss settings
        let settings = SettingsViewModel.shared.getAlertSettings(for: ticker)
        let minPrice = settings.stopLossMinPrice
        let minProfit = settings.stopLossMinProfit

        // Skip if no thresholds configured
        guard minPrice != nil || minProfit != nil else { return }

        // Skip if price hasn't loaded yet
        guard position.currentPrice > 0 else { return }

        // Current values
        let currentPriceCents = position.currentPrice * 100.0
        let currentProfit = position.realizedPnL

        // 3% hysteresis buffer (consistent with ROI alerts)
        let priceBuffer = 3.0  // 3 cents
        let profitBufferPercent = 0.03  // 3% of threshold

        // Check if EITHER threshold is breached (OR logic)
        var isBelowThreshold = false
        var breachedType = ""
        var breachedValue: Double = 0.0

        if let minPriceCents = minPrice, currentPriceCents <= minPriceCents {
            isBelowThreshold = true
            breachedType = "price"
            breachedValue = minPriceCents / 100.0
        } else if let minProfitDollars = minProfit, currentProfit <= minProfitDollars {
            isBelowThreshold = true
            breachedType = "profit"
            breachedValue = minProfitDollars
        }

        // State transition logic
        if isBelowThreshold {
            // Breach detected - send alert if not already triggered
            if !state.stopLossTriggered {
                // Time-based deduplication: 5 minutes minimum
                let shouldSend: Bool
                if let lastAlert = state.lastStopLossAlertTime {
                    shouldSend = Date().timeIntervalSince(lastAlert) >= 300  // 5 minutes
                } else {
                    shouldSend = true
                }

                if shouldSend {
                    let title = formatNotificationTitle(
                        marketTitle: position.title,
                        ticker: position.ticker,
                        alertType: AlertType.stopLoss.rawValue,
                        emoji: AlertType.stopLoss.emoji
                    )

                    let body: String
                    if breachedType == "price" {
                        body = "Price dropped to \(position.currentPrice.formatted(.currency(code: "USD"))) " +
                               "(Min: \(breachedValue.formatted(.currency(code: "USD")))) • " +
                               formatNotificationBody(
                                   roi: position.realizedROI,
                                   pnl: position.realizedPnL,
                                   currentPrice: position.currentPrice
                               )
                    } else {
                        body = "P&L dropped to \(currentProfit.formatted(.currency(code: "USD"))) " +
                               "(Min: \(breachedValue.formatted(.currency(code: "USD")))) • " +
                               formatNotificationBody(
                                   roi: position.realizedROI,
                                   pnl: position.realizedPnL,
                                   currentPrice: position.currentPrice
                               )
                    }

                    queueAlert(
                        ticker: position.ticker,
                        type: .stopLoss,
                        title: title,
                        body: body,
                        url: position.marketUrl
                    )

                    state.stopLossTriggered = true
                    state.lastStopLossAlertTime = Date()
                }
            }
        } else {
            // Check if price has recovered above threshold + buffer (reset condition)
            var hasRecovered = false

            if let minPriceCents = minPrice {
                let recoveryThreshold = minPriceCents + priceBuffer
                if currentPriceCents > recoveryThreshold {
                    hasRecovered = true
                }
            }

            if let minProfitDollars = minProfit {
                let recoveryThreshold = minProfitDollars + (abs(minProfitDollars) * profitBufferPercent)
                if currentProfit > recoveryThreshold {
                    hasRecovered = true
                }
            }

            if hasRecovered && state.stopLossTriggered {
                // Price recovered - reset state to allow future alerts
                state.stopLossTriggered = false
            }
        }

        positionAlertStates[ticker] = state
    }

    private func checkPortfolioThresholds() {
        let highThreshold = SettingsViewModel.shared.highROIThreshold / 100.0
        let lowThreshold = SettingsViewModel.shared.lowROIThreshold / 100.0

        var shouldNotify = false
        var title = ""
        var body = ""

        let defaults = UserDefaults.standard
        let alertCooldown: TimeInterval = 24 * 60 * 60 // 24 hours in seconds

        // Skip alerts if we have positions but they haven't loaded prices yet (avoid false -100% ROI)
        if !positions.isEmpty && positions.contains(where: { $0.currentPrice == 0 }) {
            return
        }

        // Check High Threshold
        if overallROI >= highThreshold {
            let lastHighDate = defaults.object(forKey: "lastPortfolioHighAlertDate") as? Date

            // Alert if never alerted, or if 24+ hours have passed
            let shouldAlert: Bool
            if let lastDate = lastHighDate {
                shouldAlert = Date().timeIntervalSince(lastDate) >= alertCooldown
            } else {
                shouldAlert = true
            }

            if shouldAlert {
                shouldNotify = true
                title = "High Portfolio ROI"
                body = "Your portfolio ROI is up to \(overallROI.formatted(.percent.precision(.fractionLength(1))))!"
                defaults.set(Date(), forKey: "lastPortfolioHighAlertDate")
            }
        }
        // Check Low Threshold
        else if overallROI <= lowThreshold {
            let lastLowDate = defaults.object(forKey: "lastPortfolioLowAlertDate") as? Date

            // Alert if never alerted, or if 24+ hours have passed
            let shouldAlert: Bool
            if let lastDate = lastLowDate {
                shouldAlert = Date().timeIntervalSince(lastDate) >= alertCooldown
            } else {
                shouldAlert = true
            }

            if shouldAlert {
                shouldNotify = true
                title = "Low Portfolio ROI"
                body = "Your portfolio ROI has dropped to \(overallROI.formatted(.percent.precision(.fractionLength(1))))."
                defaults.set(Date(), forKey: "lastPortfolioLowAlertDate")
            }
        }

        if shouldNotify {
            sendNotification(title: title, body: body)
        }
    }
    
    // MARK: - Notification Grouping

    private func queueAlert(ticker: String, type: AlertType, title: String, body: String, url: URL?) {
        let alert = PendingAlert(
            ticker: ticker,
            type: type,
            title: title,
            body: body,
            url: url,
            timestamp: Date()
        )
        pendingAlerts.append(alert)
        scheduleGroupedNotification()
    }

    private func scheduleGroupedNotification() {
        // Cancel existing timer if pending
        groupingTimer?.invalidate()

        // Schedule new timer to fire after grouping window
        groupingTimer = Timer.scheduledTimer(
            withTimeInterval: alertGroupingWindow,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sendGroupedNotifications()
            }
        }
    }

    private func sendGroupedNotifications() {
        guard !pendingAlerts.isEmpty else { return }

        if pendingAlerts.count == 1 {
            // Send single notification
            let alert = pendingAlerts[0]
            sendNotification(title: alert.title, body: alert.body, url: alert.url)
        } else {
            // Send grouped notification
            let title = "\(pendingAlerts.count) Position Alerts 📊"

            var bodyLines: [String] = []
            for (index, alert) in pendingAlerts.prefix(5).enumerated() {
                // Find the position for this ticker to get the market title
                if let position = positions.first(where: { $0.ticker == alert.ticker }) {
                    let name = position.title.map { String($0.prefix(25)) } ?? alert.ticker
                    // Extract ROI and PnL from the body (simplified for grouped view)
                    let roi = position.realizedROI.formatted(.percent.precision(.fractionLength(0)))
                    let pnl = position.realizedPnL.formatted(.currency(code: "USD"))
                    bodyLines.append("\(index + 1). \(name): \(roi) (\(pnl))")
                }
            }

            if pendingAlerts.count > 5 {
                bodyLines.append("...and \(pendingAlerts.count - 5) more")
            }

            let body = bodyLines.joined(separator: "\n")

            // Send with fallback URL
            sendNotification(
                title: title,
                body: body,
                url: URL(string: "https://kalshi.com")
            )
        }

        pendingAlerts.removeAll()
    }

    // MARK: - Notification Formatting

    private func formatNotificationTitle(marketTitle: String?, ticker: String, alertType: String, emoji: String, maxLength: Int = 50) -> String {
        // Reserve space for alert type, emoji, and spacing
        let prefix = "\(alertType): "
        let suffix = " \(emoji)"
        let reserved = prefix.count + suffix.count
        let availableLength = maxLength - reserved

        let displayName = marketTitle ?? ticker

        if displayName.count <= availableLength {
            return "\(prefix)\(displayName)\(suffix)"
        }

        // Smart truncation strategy 1: Remove question marks and common filler words
        let cleaned = displayName
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: " the ", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: " in ", with: " ", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)

        if cleaned.count <= availableLength {
            return "\(prefix)\(cleaned)\(suffix)"
        }

        // Strategy 2: Use first N words that fit
        let words = displayName.split(separator: " ")
        var truncated = ""
        for word in words {
            if truncated.isEmpty {
                truncated = String(word)
            } else if (truncated + " " + word).count <= availableLength - 3 { // Reserve "..."
                truncated += " " + word
            } else {
                break
            }
        }

        return "\(prefix)\(truncated)...\(suffix)"
    }

    private func formatNotificationBody(roi: Double, pnl: Double, currentPrice: Double, targetValue: Double? = nil) -> String {
        var parts: [String] = []

        // Always show ROI prominently
        parts.append("ROI: \(roi.formatted(.percent.precision(.fractionLength(1))))")

        // Show P&L with sign
        let pnlSign = pnl >= 0 ? "+" : ""
        parts.append("P&L: \(pnlSign)\(pnl.formatted(.currency(code: "USD")))")

        // Show current sell price
        parts.append("Sell @ \(currentPrice.formatted(.currency(code: "USD")))")

        // Optional target reference
        if let target = targetValue {
            parts.append("(Target: \(target.formatted(.currency(code: "USD"))))")
        }

        return parts.joined(separator: " • ")
    }

    private func sendNotification(title: String, body: String, url: URL? = nil) {
        // Ensure notifications are enabled globally before attempting to send
        guard SettingsViewModel.shared.notificationsEnabled else { return }
        
        // Ensure the app is running in a proper .app bundle for notifications to work
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            print("Cannot send notification: App is not in a .app bundle")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        if let url = url {
            content.userInfo = ["url": url.absoluteString]
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Trade History & Metrics

    private func loadCachedFills() {
        guard let data = UserDefaults.standard.data(forKey: "cachedFills") else { return }
        do {
            let decoder = JSONDecoder()
            let cached = try decoder.decode([Fill].self, from: data)
            fills = cached
            tradeMetrics = TradeMetrics.compute(from: cached)
        } catch {
            print("⚠️ Failed to decode cached fills: \(error)")
        }
    }

    private func cacheFills(_ fills: [Fill]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(fills)
            UserDefaults.standard.set(data, forKey: "cachedFills")
            UserDefaults.standard.set(Date(), forKey: "fillsCacheTimestamp")
        } catch {
            print("⚠️ Failed to cache fills: \(error)")
        }
    }

    private func fetchTradeHistoryIfNeeded() {
        if let timestamp = UserDefaults.standard.object(forKey: "fillsCacheTimestamp") as? Date,
           Date().timeIntervalSince(timestamp) < 3600,
           !fills.isEmpty {
            return
        }
        refreshTradeHistory()
    }

    func refreshTradeHistory() {
        guard !isLoadingFills else { return }
        isLoadingFills = true

        NetworkManager.shared.fetchAllFills { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingFills = false
                switch result {
                case .success(let fetchedFills):
                    self?.fills = fetchedFills
                    self?.tradeMetrics = TradeMetrics.compute(from: fetchedFills)
                    self?.cacheFills(fetchedFills)
                case .failure(let error):
                    print("⚠️ Failed to fetch fills: \(error)")
                }
            }
        }
    }

    // Called when a WebSocket ticker update is received
    func updatePrice(with quote: WebSocketManager.TickerQuote) {
        guard let index = positions.firstIndex(where: { $0.marketTicker == quote.ticker }) else { return }

        var position = positions[index]

        let yesBid = quote.yesBid.map { Double($0) / 100.0 }
        let yesAsk = quote.yesAsk.map { Double($0) / 100.0 }
        let lastPrice = quote.lastPrice.map { Double($0) / 100.0 }

        // Store YES prices from WebSocket
        position.yesBid = yesBid
        position.yesAsk = yesAsk

        // WebSocket stream does not carry noBid; derive from yesAsk if available
        if let yesAsk = yesAsk, position.noBid == nil {
            position.noBid = 1.0 - yesAsk
        }

        // WebSocket stream does not carry noBid; fall back to derived price for "No"
        let executable = position.executableSellPrice(yesBid: yesBid, noBid: nil, yesAsk: yesAsk, lastPrice: lastPrice)

        if let executable = executable {
            position.currentPrice = executable
            position.history.append(executable)
            if position.history.count > 50 { // Keep last 50 points
                position.history.removeFirst()
            }

            // Check for arbitrage after price update
            checkArbitrageOpportunity(for: &position)

            positions[index] = position
            calculateTotals()
        }
    }
    
}

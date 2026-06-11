import Foundation

/// A market the user is watching for a price target, without holding a position.
/// Alert state (`armed`, `lastHitAt`, `lastNotifiedAt`) is persisted so hysteresis
/// survives app restarts; live quote data (`currentYesCents`, `status`) is
/// runtime-only and re-fetched on launch.
struct WatchlistItem: Identifiable, Codable, Equatable {
    enum Direction: String, Codable, CaseIterable {
        case atOrBelow
        case atOrAbove

        var symbol: String {
            switch self {
            case .atOrBelow: return "≤"
            case .atOrAbove: return "≥"
            }
        }

        var label: String {
            switch self {
            case .atOrBelow: return "At or below"
            case .atOrAbove: return "At or above"
            }
        }
    }

    let id: UUID
    let ticker: String            // market ticker (matches WebSocket market_ticker)
    var title: String
    var subtitle: String?
    var eventTicker: String?
    var seriesTicker: String?
    var marketUrl: URL?
    var targetCents: Int          // 1...99, on the Yes price
    var direction: Direction
    var createdAt: Date

    // Alert state
    var armed: Bool = true        // true = will notify on next crossing
    var lastHitAt: Date? = nil    // non-nil => target was hit at least once
    var lastNotifiedAt: Date? = nil

    // Runtime-only
    var currentYesCents: Int? = nil
    var status: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, ticker, title, subtitle, eventTicker, seriesTicker, marketUrl
        case targetCents, direction, createdAt, armed, lastHitAt, lastNotifiedAt
    }

    init(
        id: UUID = UUID(),
        ticker: String,
        title: String,
        subtitle: String? = nil,
        eventTicker: String? = nil,
        seriesTicker: String? = nil,
        marketUrl: URL? = nil,
        targetCents: Int,
        direction: Direction,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ticker = ticker
        self.title = title
        self.subtitle = subtitle
        self.eventTicker = eventTicker
        self.seriesTicker = seriesTicker
        self.marketUrl = marketUrl
        self.targetCents = targetCents
        self.direction = direction
        self.createdAt = createdAt
    }

    /// Whether the market can still trade; closed/settled markets show "Closed"
    /// and never alert.
    var isClosed: Bool {
        guard let status else { return false }
        return ["finalized", "settled", "closed", "determined"].contains(status)
    }

    /// The Yes price shown to the user and compared against the target, matching
    /// what kalshi.com displays: last trade, then bid/ask midpoint, then either
    /// side alone. Pure so the REST and WebSocket paths use identical logic.
    static func displayPriceCents(lastPrice: Int?, yesBid: Int?, yesAsk: Int?) -> Int? {
        if let lastPrice { return lastPrice }
        if let yesBid, let yesAsk { return (yesBid + yesAsk) / 2 }
        return yesBid ?? yesAsk
    }
}

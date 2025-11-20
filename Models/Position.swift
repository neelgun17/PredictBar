import Foundation

struct Position: Identifiable, Codable {
    let ticker: String
    let position: Int
    let feesPaid: Int?
    let realizedPnl: Int?
    let totalTraded: Int?
    
    // Enriched data from Market API
    var title: String?
    var subtitle: String?
    var eventTicker: String?
    
    // Computed properties for app compatibility
    var id: String { ticker }
    var marketTicker: String { ticker }
    var quantity: Int { position }
    
    // Determine side based on position sign
    var side: String {
        return position > 0 ? "Yes" : "No"
    }
    
    // Cost basis calculation
    // totalTraded is in cents. We use it as a proxy for cost basis.
    // Note: This is an approximation if the user has traded in and out.
    var entryPrice: Double {
        guard let cost = totalTraded, position != 0 else { return 0.0 }
        // cost is in cents, convert to dollars and average
        return (Double(cost) / 100.0) / Double(abs(position))
    }
    
    // This needs to be updated via WebSocket
    var currentPrice: Double = 0.0
    
    var roi: Double {
        guard entryPrice > 0 else { return 0.0 }
        return ((currentPrice - entryPrice) / entryPrice) * 100.0
    }
    
    var pnl: Double {
        return (currentPrice - entryPrice) * Double(quantity)
    }
    
    enum CodingKeys: String, CodingKey {
        case ticker
        case position
        case feesPaid = "fees_paid"
        case realizedPnl = "realized_pnl"
        case totalTraded = "total_traded"
        case title
        case subtitle
        case eventTicker = "event_ticker"
    }
}

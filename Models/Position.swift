import Foundation

struct Position: Identifiable, Codable {
    let ticker: String
    let position: Int
    let feesPaid: Int?
    let realizedPnl: Int?
    
    // Computed properties for app compatibility
    var id: String { ticker }
    var marketTicker: String { ticker }
    var quantity: Int { position }
    
    // These would ideally come from a separate market data fetch or WebSocket update
    // For now, we'll default them or calculate what we can
    var entryPrice: Double {
        guard let fees = feesPaid, position != 0 else { return 0.0 }
        // feesPaid is in cents, convert to dollars and average
        return (Double(fees) / 100.0) / Double(abs(position))
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
    }
}

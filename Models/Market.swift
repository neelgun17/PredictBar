import Foundation

struct Market: Codable, Identifiable {
    let ticker: String
    let title: String
    let subtitle: String?
    let yesBid: Int
    let yesAsk: Int
    let expirationDate: Date
    let status: String?
    
    var id: String { ticker }
    
    // Helper to convert cents to dollars
    var currentPrice: Double {
        // Assuming price is roughly mid-market or last trade. 
        // For simplicity, using mid-point of bid/ask or just bid if ask is missing.
        let mid = Double(yesBid + yesAsk) / 2.0
        return mid / 100.0
    }
}

struct MarketResponse: Codable {
    let markets: [Market]
}

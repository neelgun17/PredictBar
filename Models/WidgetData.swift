import Foundation

// MARK: - Shared Widget Data Models

/// Lightweight position data for widget display
struct WidgetPosition: Codable, Identifiable {
    let id: String // ticker
    let ticker: String
    let title: String
    let subtitle: String // e.g., "MSTA · 20 @ $0.24"
    let currentPrice: Double
    let roi: Double // fraction, e.g., 0.515 for 51.5%
    let history: [Double] // price history for sparkline
    let isPositive: Bool // for color coding
    
    init(from position: Position) {
        self.id = position.ticker
        self.ticker = position.ticker
        self.title = position.title ?? position.ticker
        
        // Build subtitle: "TICKER · qty @ $price"
        let tickerPart = position.ticker.components(separatedBy: "-").last ?? position.ticker
        let subtitle = "\(tickerPart) · \(abs(position.quantity)) @ $\(String(format: "%.2f", position.entryPrice))"
        self.subtitle = subtitle
        
        self.currentPrice = position.currentPrice
        self.roi = position.realizedROI
        self.history = position.history
        self.isPositive = position.realizedROI >= 0
    }
}

/// Portfolio snapshot for widget
struct WidgetPortfolioSnapshot: Codable {
    let positions: [WidgetPosition]
    let lastUpdate: Date
    
    init(positions: [WidgetPosition]) {
        self.positions = positions
        self.lastUpdate = Date()
    }
}

/// Helper for reading/writing widget data
class WidgetDataStore {
    static let shared = WidgetDataStore()
    
    // App Group identifier - must match in both app and widget targets
    private let appGroupIdentifier = "group.com.kalshi.menubar.dashboard"
    private let snapshotKey = "portfolioSnapshot"
    
    private init() {}
    
    func saveSnapshot(_ snapshot: WidgetPortfolioSnapshot) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("Failed to create UserDefaults for app group")
            return
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(snapshot) {
            userDefaults.set(data, forKey: snapshotKey)
            // print("Widget snapshot saved: \(snapshot.positions.count) positions")
        }
    }
    
    func loadSnapshot() -> WidgetPortfolioSnapshot? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("Failed to create UserDefaults for app group")
            return nil
        }
        
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            print("No widget snapshot data found")
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(WidgetPortfolioSnapshot.self, from: data)
    }
}

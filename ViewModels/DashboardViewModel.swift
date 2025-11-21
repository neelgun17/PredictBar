import SwiftUI
import Combine
import UserNotifications

class DashboardViewModel: ObservableObject {
    @Published var overallROI: Double = 0.0
    @Published var positions: [Position] = []
    @Published var isConnected: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    init() {
        setupBindings()
        fetchData()
        WebSocketManager.shared.connect()
    }
    
    private func setupBindings() {
        WebSocketManager.shared.$isConnected
            .receive(on: RunLoop.main)
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)
            
        WebSocketManager.shared.priceUpdate
            .receive(on: RunLoop.main)
            .sink { [weak self] (ticker, price) in
                // Convert price from cents to dollars
                let priceInDollars = Double(price) / 100.0
                self?.updatePrice(for: ticker, price: priceInDollars)
                
                // Friendly logging
                if let position = self?.positions.first(where: { $0.marketTicker == ticker }) {
                    let title = position.title ?? ticker
                    print("Price Update: \(title) (\(ticker)) - \(priceInDollars.formatted(.currency(code: "USD")))")
                }
            }
            .store(in: &cancellables)
//            .store(in: &cancellables)
            
        // Auto-refresh data every 30 seconds
        timer
            .sink { [weak self] _ in
                print("Auto-refreshing data...")
                self?.fetchData()
            }
            .store(in: &cancellables)
    }
    
    func fetchData() {
        NetworkManager.shared.fetchPortfolio { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let positions):
                    // Filter out positions with 0 quantity (sold out)
                    let activePositions = positions.filter { $0.position != 0 }
                    print("Fetched \(positions.count) positions, \(activePositions.count) active")
                    
                    // Debug cost basis
                    for p in activePositions {
                        print("Position \(p.ticker): Qty=\(p.position), TotalTraded=\(p.totalTraded ?? -1)")
                    }
                    
                    self?.positions = activePositions
                    self?.calculateTotals()
                    
                    // Subscribe to WebSocket updates for these tickers
                    let tickers = positions.map { $0.ticker }
                    print("DashboardVM: Calling subscribe for tickers: \(tickers)")
                    WebSocketManager.shared.subscribeToTickers(tickers)
                    
                    // Fetch market details for each position
                    for (index, position) in positions.enumerated() {
                        NetworkManager.shared.fetchMarket(ticker: position.ticker) { [weak self] result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let market):
                                    print("Fetched market for \(position.ticker): Title='\(market.title)', Subtitle='\(market.subtitle ?? "nil")'")
                                    print("Fetched market for \(position.ticker): Title='\(market.title)', Subtitle='\(market.subtitle ?? "nil")'")
                                    
                                    // Find the current index of this position safely
                                    if let currentIdx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                        var updatedPosition = self?.positions[currentIdx]
                                        
                                        updatedPosition?.title = market.title
                                        
                                        // Use API subtitle, or fallback to ticker suffix (e.g., "PHI" from "...-PHI")
                                        if let sub = market.subtitle, !sub.isEmpty {
                                            updatedPosition?.subtitle = sub
                                        } else {
                                            updatedPosition?.subtitle = position.ticker.components(separatedBy: "-").last
                                        }
                                        
                                        updatedPosition?.eventTicker = market.eventTicker
                                        
                                        // Update price if available (priority: lastPrice > yesBid)
                                        if let price = market.lastPrice {
                                            updatedPosition?.currentPrice = Double(price) / 100.0
                                        } else if let bid = market.yesBid {
                                            updatedPosition?.currentPrice = Double(bid) / 100.0
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
                                                            // We need to find where to store the slug/URL.
                                                            // For now, let's just print the event response to find the slug.
                                                            // print("Fetched event: \(event.eventTicker)")
                                                            
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
                                                                        
                                                                        let urlString = "https://kalshi.com/markets/\(series.ticker.lowercased())/\(slug)/\(event.eventTicker.lowercased())"
                                                                        
                                                                        if let url = URL(string: urlString) {
                                                                            print("Generated URL for \(position.ticker): \(url)")
                                                                            // Update position safely
                                                                            if let idx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                                                                self?.positions[idx].marketUrl = url
                                                                            }
                                                                        }
                                                                        
                                                                    case .failure(let error):
                                                                        print("Error fetching series: \(error)")
                                                                    }
                                                                }
                                                            }
                                                        case .failure(let error):
                                                            print("Error fetching event: \(error)")
                                                        }
                                                    }
                                                }
                                        }
                                    }
                                case .failure(let error):
                                    print("Error fetching market \(position.ticker): \(error)")
                                }
                            }
                        }
                    }
                case .failure(let error):
                    print("Error fetching portfolio: \(error)")
                }
            }
        }
    }
    
    private func calculateTotals() {
        let totalCost = positions.reduce(0.0) { $0 + ($1.entryPrice * Double($1.quantity)) }
        let currentValue = positions.reduce(0.0) { $0 + ($1.currentPrice * Double($1.quantity)) }
        
        if totalCost > 0 {
            overallROI = ((currentValue - totalCost) / totalCost) * 100.0
        } else {
            overallROI = 0.0
        }
        
        checkThresholds()
    }
    
    private func checkThresholds() {
        // Simple check: if ROI > 20%
        if overallROI > 20.0 {
            sendNotification(title: "High ROI Alert", body: "Your portfolio ROI has exceeded 20%!")
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
//         UNUserNotificationCenter.current().add(request)
    }
    
    // Called when a WebSocket ticker update is received
    func updatePrice(for ticker: String, price: Double) {
        if let index = positions.firstIndex(where: { $0.marketTicker == ticker }) {
            // Create a mutable copy of the position
            var position = positions[index]
            
            // Update the price
            position.currentPrice = price
            
            // Save back to the array (triggers UI update)
            positions[index] = position
            calculateTotals()
        }
    }
}


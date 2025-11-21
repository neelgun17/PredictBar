import SwiftUI
import Combine
import UserNotifications

class DashboardViewModel: ObservableObject {
    @Published var overallROI: Double = 0.0
    @Published var overallPnL: Double = 0.0
    @Published var portfolioValue: Double = 0.0
    @Published var accountBalance: Double = 0.0
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
    }
    
    func fetchData() {
        // Fetch Balance
        NetworkManager.shared.fetchBalance { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let response) = result {
                    self?.accountBalance = Double(response.balance) / 100.0
                    self?.portfolioValue = Double(response.portfolioValue) / 100.0
                }
            }
        }
        
        NetworkManager.shared.fetchPortfolio { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let positions):
                    // Filter out positions with 0 quantity (sold out)
                    let activePositions = positions.filter { $0.position != 0 }
                    
                    self?.positions = activePositions
                    self?.calculateTotals()
                    
                    // Subscribe to WebSocket updates for these tickers
                    let tickers = positions.map { $0.ticker }
                    WebSocketManager.shared.subscribeToTickers(tickers)
                    
                    // Fetch market details for each position
                    for (index, position) in positions.enumerated() {
                        NetworkManager.shared.fetchMarket(ticker: position.ticker) { [weak self] result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let market):
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
                                        
                                        // Update price to the executable sell price (best current bid for this side)
                                        let yesBid = market.yesBid.map { Double($0) / 100.0 }
                                        let noBid = market.noBid.map { Double($0) / 100.0 }
                                        let yesAsk = market.yesAsk.map { Double($0) / 100.0 }
                                        let lastPrice = market.lastPrice.map { Double($0) / 100.0 }
                                        
                                        if let executable = updatedPosition?.executableSellPrice(
                                            yesBid: yesBid,
                                            noBid: noBid,
                                            yesAsk: yesAsk,
                                            lastPrice: lastPrice
                                        ) {
                                            updatedPosition?.currentPrice = executable
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
                                                                            // Update position safely
                                                                            if let idx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                                                                self?.positions[idx].marketUrl = url
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
                case .failure:
                    break
                }
            }
        }
    }
    
    private func calculateTotals() {
        // Portfolio-level realized ROI after fees, based on actual cost basis and current net proceeds
        let totalCost = positions.reduce(0.0) { $0 + $1.totalCostBasis }
        let totalNetProceeds = positions.reduce(0.0) { $0 + $1.netProceedsAfterFees }
        
        overallPnL = totalNetProceeds - totalCost
        
        if totalCost > 0 {
            overallROI = overallPnL / totalCost
        } else {
            overallROI = 0.0
        }
        
        checkThresholds()
    }
    
    private func checkThresholds() {
        // Simple check: if ROI > 20%
        if overallROI > 0.20 {
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
    func updatePrice(with quote: WebSocketManager.TickerQuote) {
        guard let index = positions.firstIndex(where: { $0.marketTicker == quote.ticker }) else { return }

        var position = positions[index]

        let yesBid = quote.yesBid.map { Double($0) / 100.0 }
        let yesAsk = quote.yesAsk.map { Double($0) / 100.0 }
        let lastPrice = quote.lastPrice.map { Double($0) / 100.0 }

        // WebSocket stream does not carry noBid; fall back to derived price for "No"
        let executable = position.executableSellPrice(yesBid: yesBid, noBid: nil, yesAsk: yesAsk, lastPrice: lastPrice)

        if let executable = executable {
            position.currentPrice = executable
            positions[index] = position
            calculateTotals()
        }
    }
}

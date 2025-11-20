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
            
        // Listen for WebSocket messages (Need to expose a publisher in WebSocketManager)
        // For now, we'll simulate it or add a callback
    }
    
    func fetchData() {
        NetworkManager.shared.fetchPortfolio { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let positions):
                    self?.positions = positions
                    self?.calculateTotals()
                    
                    // Fetch market details for each position
                    for (index, position) in positions.enumerated() {
                        NetworkManager.shared.fetchMarket(ticker: position.ticker) { [weak self] result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let market):
                                    if var updatedPosition = self?.positions[index] {
                                        updatedPosition.title = market.title
                                        updatedPosition.subtitle = market.subtitle
                                        updatedPosition.eventTicker = market.eventTicker
                                        
                                        // Update price if available (priority: lastPrice > yesBid)
                                        if let price = market.lastPrice {
                                            updatedPosition.currentPrice = Double(price) / 100.0
                                        } else if let bid = market.yesBid {
                                            updatedPosition.currentPrice = Double(bid) / 100.0
                                        }
                                        
                                        // Update the position in the array
                                        // Note: Index might shift if list changes, ideally use ID
                                        if let currentIdx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                            self?.positions[currentIdx] = updatedPosition
                                            self?.calculateTotals()
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
            let oldPosition = positions[index]
            
            // Create a new position with updated price
            var newPosition = Position(
                ticker: oldPosition.ticker,
                position: oldPosition.position,
                feesPaid: oldPosition.feesPaid,
                realizedPnl: oldPosition.realizedPnl,
                totalTraded: oldPosition.totalTraded
            )
            newPosition.currentPrice = price
            
            positions[index] = newPosition
            calculateTotals()
        }
    }
}

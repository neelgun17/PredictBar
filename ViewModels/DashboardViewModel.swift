import SwiftUI
import Combine
import UserNotifications

class DashboardViewModel: ObservableObject {
    @Published var overallROI: Double = 0.0
    @Published var overallPnL: Double = 0.0
    @Published var portfolioValue: Double = 0.0
    @Published var accountBalance: Double = 0.0
    @Published var menuBarText: String = ""
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
                    self?.updateMenuBarText()
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
        
        updateMenuBarText()
        checkThresholds()
    }
    
    func updateMenuBarText() {
        let metric = UserDefaults.standard.string(forKey: "menuBarMetric") ?? "ROI"
        
        switch metric {
        case "ROI":
            menuBarText = overallROI.formatted(.percent.precision(.fractionLength(1)))
        case "PnL":
            menuBarText = overallPnL.formatted(.currency(code: "USD"))
        case "Portfolio":
            menuBarText = portfolioValue.formatted(.currency(code: "USD"))
        case "Balance":
            menuBarText = accountBalance.formatted(.currency(code: "USD"))
        default:
            menuBarText = ""
        }
    }
    
    private var lastNotificationTime: Date?
    
    private func checkThresholds() {
        let defaults = UserDefaults.standard
        let notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        
        guard notificationsEnabled else { return }
        
        // Defaults: High +20%, Low -20%
        // Note: UserDefaults returns 0 if key doesn't exist, so we need to handle defaults carefully if we want non-zero defaults when not set.
        // However, @AppStorage in SettingsView initializes them. If the user hasn't opened settings, they might be 0.
        // Better to use a helper or safe defaults.
        let highThreshold = (defaults.object(forKey: "highROIThreshold") as? Double ?? 20.0) / 100.0
        let lowThreshold = (defaults.object(forKey: "lowROIThreshold") as? Double ?? -20.0) / 100.0
        
        // Debounce: Don't notify more than once every 5 minutes
        if let lastTime = lastNotificationTime, Date().timeIntervalSince(lastTime) < 300 {
            return
        }
        
        var shouldNotify = false
        var title = ""
        var body = ""
        
        if overallROI >= highThreshold {
            shouldNotify = true
            title = "High ROI Alert 🚀"
            body = "Your portfolio ROI is up to \(overallROI.formatted(.percent.precision(.fractionLength(1))))!"
        } else if overallROI <= lowThreshold {
            shouldNotify = true
            title = "Low ROI Alert 📉"
            body = "Your portfolio ROI has dropped to \(overallROI.formatted(.percent.precision(.fractionLength(1))))."
        }
        
        if shouldNotify {
            sendNotification(title: title, body: body)
            lastNotificationTime = Date()
        }
    }
    
    private func sendNotification(title: String, body: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            print("Cannot send notification: App is not in a .app bundle")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
            position.history.append(executable)
            if position.history.count > 50 { // Keep last 50 points
                position.history.removeFirst()
            }
            positions[index] = position
            calculateTotals()
        }
    }
}

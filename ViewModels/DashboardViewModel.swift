import SwiftUI
import Combine
import UserNotifications

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var totalCashOutValue: Double = 0.0
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
                    self?.menuBarText = "Kalshi"
                    WebSocketManager.shared.disconnect()
                }
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
                            merged.previousROIState = existing.previousROIState
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
                                            if let url = URL(string: "https://kalshi.com/markets/\(seriesTicker.lowercased())") {
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
                                                                        
                                                                        let urlString = "https://kalshi.com/markets/\(series.ticker.lowercased())/\(slug)/\(event.eventTicker.lowercased())"
                                                                        
                                                                        if let url = URL(string: urlString) {
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
        
        totalCashOutValue = totalNetProceeds
        overallPnL = totalNetProceeds - totalCost
        
        if totalCost > 0 {
            overallROI = overallPnL / totalCost
        } else {
            overallROI = 0.0
        }
        
        updateMenuBarText()
        checkThresholds()
        updateWidgetData()
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
    
    // Track the last state of each position to prevent spamming notifications
    // Key: Ticker, Value: State
    private var positionAlertStates: [String: PositionAlertState] = [:]
    
    struct PositionAlertState {
        var isAboveHighROI: Bool = false
        var isBelowLowROI: Bool = false
        var isAboveTargetProfit: Bool = false
        var isAboveTargetPrice: Bool = false
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
            
            // Update lastROI (still useful for debugging or other logic, but state drives alerts now)
            position.lastROI = newROI
            positions[index] = position
        }
    }
    
    private func handleAlerts(for position: inout Position, newROI: Double, highThreshold: Double, lowThreshold: Double, targetProfit: Double?, targetPrice: Double?) {
        let currentState = position.previousROIState
        
        // Determine new state based on thresholds
        // Note: We use a hysteresis or simple transition. 
        // Requirement: "fire a notification when transitioning neutral→high or neutral→low, and reset when back in neutral"
        
        var newState: Position.ROIState = currentState
        
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
        
        // Check transitions
        if currentState == .neutral && newState == .high {
            sendNotification(
                title: "High ROI Alert: \(position.title ?? position.ticker) 🚀",
                body: "High ROI hit: \(position.realizedROI.formatted(.percent.precision(.fractionLength(1)))) — Profit: \(position.realizedPnL.formatted(.currency(code: "USD"))) (Sell @ \(position.currentPrice.formatted(.currency(code: "USD"))))",
                url: position.marketUrl
            )
        } else if currentState == .neutral && newState == .low {
            sendNotification(
                title: "Low ROI Alert: \(position.title ?? position.ticker) 📉",
                body: "Low ROI hit: \(position.realizedROI.formatted(.percent.precision(.fractionLength(1)))) — Profit: \(position.realizedPnL.formatted(.currency(code: "USD"))) (Sell @ \(position.currentPrice.formatted(.currency(code: "USD"))))",
                url: position.marketUrl
            )
        }
        
        // Update state on position
        position.previousROIState = newState
        
        // Check Target Profit (One-off)
        if let target = targetProfit {
             var state = positionAlertStates[position.ticker] ?? PositionAlertState()
             
             if position.realizedPnL >= target {
                 if !state.isAboveTargetProfit {
                     sendNotification(
                         title: "Profit Target Hit: \(position.title ?? position.ticker) 💰",
                         body: "Profit reached \(position.realizedPnL.formatted(.currency(code: "USD")))! (Target: \(target.formatted(.currency(code: "USD"))))",
                         url: position.marketUrl
                     )
                     state.isAboveTargetProfit = true
                     positionAlertStates[position.ticker] = state
                 }
             } else {
                 if state.isAboveTargetProfit {
                     state.isAboveTargetProfit = false
                     positionAlertStates[position.ticker] = state
                 }
             }
         }
         
         // Check Target Price (One-off)
         if let target = targetPrice {
             let currentPrice = position.currentPrice
             // Target Price is in cents (e.g. 50 for 50c). Current price is dollars (0.50).
             if (currentPrice * 100) >= target {
                 var state = positionAlertStates[position.ticker] ?? PositionAlertState()
                 
                 if !state.isAboveTargetPrice {
                     sendNotification(
                         title: "Price Target Hit: \(position.title ?? position.ticker) 🎯",
                         body: "Price reached \(currentPrice.formatted(.currency(code: "USD")))! (Target: \(target.formatted())¢)",
                         url: position.marketUrl
                     )
                     state.isAboveTargetPrice = true
                     positionAlertStates[position.ticker] = state
                 }
             } else {
                  var state = positionAlertStates[position.ticker] ?? PositionAlertState()
                  if state.isAboveTargetPrice {
                      state.isAboveTargetPrice = false
                      positionAlertStates[position.ticker] = state
                  }
             }
         }
    }
    
    private func checkPortfolioThresholds() {
        let highThreshold = SettingsViewModel.shared.highROIThreshold / 100.0
        let lowThreshold = SettingsViewModel.shared.lowROIThreshold / 100.0
        
        var shouldNotify = false
        var title = ""
        var body = ""
        
        let defaults = UserDefaults.standard
        let calendar = Calendar.current
        
        // Skip alerts if we have positions but they haven't loaded prices yet (avoid false -100% ROI)
        if !positions.isEmpty && positions.contains(where: { $0.currentPrice == 0 }) {
            return
        }
        
        // Check High Threshold
        if overallROI >= highThreshold {
            let lastHighDate = defaults.object(forKey: "lastPortfolioHighAlertDate") as? Date
            
            // Alert if never alerted, or if last alert was not today
            if lastHighDate == nil || !calendar.isDateInToday(lastHighDate!) {
                shouldNotify = true
                title = "High Portfolio ROI 🚀"
                body = "Your portfolio ROI is up to \(overallROI.formatted(.percent.precision(.fractionLength(1))))!"
                defaults.set(Date(), forKey: "lastPortfolioHighAlertDate")
            }
        } 
        // Check Low Threshold
        else if overallROI <= lowThreshold {
            let lastLowDate = defaults.object(forKey: "lastPortfolioLowAlertDate") as? Date
            
            // Alert if never alerted, or if last alert was not today
            if lastLowDate == nil || !calendar.isDateInToday(lastLowDate!) {
                shouldNotify = true
                title = "Low Portfolio ROI 📉"
                body = "Your portfolio ROI has dropped to \(overallROI.formatted(.percent.precision(.fractionLength(1))))."
                defaults.set(Date(), forKey: "lastPortfolioLowAlertDate")
            }
        }
        
        if shouldNotify {
            sendNotification(title: title, body: body)
        }
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
    
    // MARK: - Widget Data Update
    
    /// Updates the widget's shared data store with current portfolio snapshot
    private func updateWidgetData() {
        // Take top 5 positions for the widget
        let topPositions = positions.prefix(5).map { WidgetPosition(from: $0) }
        let snapshot = WidgetPortfolioSnapshot(positions: Array(topPositions))
        WidgetDataStore.shared.saveSnapshot(snapshot)
    }
}

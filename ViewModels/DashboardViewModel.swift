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
                    for (index, position) in positions.enumerated() {
                        NetworkManager.shared.fetchMarket(ticker: position.ticker) { [weak self] result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let market):
                                    // Find the current index of this position safely
                                    if let currentIdx = self?.positions.firstIndex(where: { $0.ticker == position.ticker }) {
                                        var updatedPosition = self?.positions[currentIdx]
                                        
                                        updatedPosition?.title = market.title
                                        updatedPosition?.status = market.status
                                        
                                        // Filter out settled/finalized positions
                                        if let status = market.status, (status == "finalized" || status == "settled") {
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
            
            let newROI = position.realizedROI * 100.0
            let oldROI = position.lastROI ?? newROI // First run: assume no change
            
            handleAlerts(for: &position, oldROI: oldROI, newROI: newROI, highThreshold: highThreshold, lowThreshold: lowThreshold, targetProfit: targetProfit, targetPrice: targetPrice)
            
            // Update lastROI
            position.lastROI = newROI
            positions[index] = position
        }
    }
    
    private func handleAlerts(for position: inout Position, oldROI: Double, newROI: Double, highThreshold: Double, lowThreshold: Double, targetProfit: Double?, targetPrice: Double?) {
        var shouldUpdateState = false
        
        // Check High ROI
        // Trigger if we crossed ABOVE the threshold (old < high && new >= high)
        if oldROI < highThreshold && newROI >= highThreshold {
            sendNotification(
                title: "High ROI Alert: \(position.ticker) 🚀",
                body: "ROI hit \(newROI.formatted(.percent.precision(.fractionLength(1))))! Profit: \(position.realizedPnL.formatted(.currency(code: "USD"))) (Sell @ \(position.currentPrice.formatted(.currency(code: "USD"))))",
                url: position.marketUrl
            )
        }
        
        // Check Low ROI
        // Trigger if we crossed BELOW the threshold (old > low && new <= low)
        if oldROI > lowThreshold && newROI <= lowThreshold {
            sendNotification(
                title: "Low ROI Alert: \(position.ticker) 📉",
                body: "ROI dropped to \(newROI.formatted(.percent.precision(.fractionLength(1)))). Profit: \(position.realizedPnL.formatted(.currency(code: "USD"))) (Sell @ \(position.currentPrice.formatted(.currency(code: "USD"))))",
                url: position.marketUrl
            )
        }
        
        // Check Target Profit
        if let target = targetProfit {
            // We need to track if we already alerted for profit. 
            // Since Position struct is re-created often, we might need persistent state for "one-off" targets like Profit/Price.
            // However, for ROI, the crossing logic (old vs new) handles "fire once" naturally.
            // For Profit/Price, we can use the same crossing logic if we tracked lastProfit/lastPrice, 
            // OR we can keep using positionAlertStates for these specific one-off targets.
            
            // For now, let's use the existing state map for Profit/Price to avoid adding more fields to Position if not needed.
            var state = positionAlertStates[position.ticker] ?? PositionAlertState()
            
            if position.realizedPnL >= target {
                if !state.isAboveTargetProfit {
                    sendNotification(
                        title: "Profit Target Hit: \(position.ticker) 💰",
                        body: "Profit reached \(position.realizedPnL.formatted(.currency(code: "USD")))! (Target: \(target.formatted(.currency(code: "USD"))))",
                        url: position.marketUrl
                    )
                    state.isAboveTargetProfit = true
                    shouldUpdateState = true
                }
            } else {
                if state.isAboveTargetProfit {
                    state.isAboveTargetProfit = false
                    shouldUpdateState = true
                }
            }
            
            if shouldUpdateState {
                positionAlertStates[position.ticker] = state
            }
        }
        
        // Check Target Price
        if let target = targetPrice {
            let currentPrice = position.currentPrice
            // Target Price is in cents (e.g. 50 for 50c). Current price is dollars (0.50).
            // Compare cents to cents.
            if (currentPrice * 100) >= target {
                var state = positionAlertStates[position.ticker] ?? PositionAlertState()
                
                if !state.isAboveTargetPrice {
                    sendNotification(
                        title: "Price Target Hit: \(position.ticker) 🎯",
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
        
        // Debounce portfolio alerts
        if let lastTime = lastNotificationTime, Date().timeIntervalSince(lastTime) < 300 {
            return
        }
        
        var shouldNotify = false
        var title = ""
        var body = ""
        
        if overallROI >= highThreshold {
            shouldNotify = true
            title = "High Portfolio ROI 🚀"
            body = "Your portfolio ROI is up to \(overallROI.formatted(.percent.precision(.fractionLength(1))))!"
        } else if overallROI <= lowThreshold {
            shouldNotify = true
            title = "Low Portfolio ROI 📉"
            body = "Your portfolio ROI has dropped to \(overallROI.formatted(.percent.precision(.fractionLength(1))))."
        }
        
        if shouldNotify {
            sendNotification(title: title, body: body)
            lastNotificationTime = Date()
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

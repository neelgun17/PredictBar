import SwiftUI
import Combine

class BacktestingViewModel: ObservableObject {
    @Published var selectedPeriod: Int = 30 // Days
    @Published var selectedStrategy: StrategyType = .balanced
    
    @Published var episodes: [TradeEpisode] = []
    @Published var results: [SimulationResult] = []
    
    @Published var isRunning: Bool = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String? = nil
    @Published var hasRun: Bool = false
    
    // Cache
    private var allFills: [Fill] = []
    private var cachedEpisodes: [TradeEpisode] = []
    
    // KPI
    @Published var strategyPnL: Double = 0.0
    @Published var winRate: Double = 0.0
    @Published var tradeCount: Int = 0
    
    func runBacktest() {
        guard !isRunning else { return }
        isRunning = true
        hasRun = false
        progress = 0.0
        statusMessage = "Fetching fills..."
        errorMessage = nil
        results = []
        
        // 1. Fetch Fills (if needed)
        
        if !allFills.isEmpty {
            self.processFills()
        } else {
            fetchAllFills { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    // Failure
                    self.statusMessage = "Failed_Fetch"
                    self.errorMessage = error.localizedDescription
                    self.isRunning = false
                    self.hasRun = true
                } else {
                    // Success
                    if self.allFills.isEmpty {
                        // Only overwrite if we don't have a specific debug message already
                        if !self.statusMessage.contains("Empty Response") {
                            self.statusMessage = "No fills found."
                        }
                        self.isRunning = false
                        self.hasRun = true
                    } else {
                        self.processFills()
                    }
                }
            }
        }
    }
    
    // Dev Mode Flag
    static let isDevMode = false
    
    private func fetchAllFills(completion: @escaping (Error?) -> Void) {
        if Self.isDevMode {
            // Mock Data
            let mock = Fill(tradeId: "mock-1", marketTicker: "KX-TEST", isTaker: true, side: "yes", count: 100, action: "buy", price: 50, createdTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400 * 5)))
            self.allFills = [mock]
            completion(nil)
            return
        }
        
        // Calculate cutoff date
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -selectedPeriod, to: Date()) ?? Date.distantPast
        
        // Recursive fetch
        var accumulated: [Fill] = []
        var fetchedIds = Set<String>()
        var shouldContinue = true
        
        func fetch(cursor: String?) {
            guard shouldContinue else {
                DispatchQueue.main.async {
                    self.allFills = accumulated
                    completion(nil)
                }
                return
            }
            
            NetworkManager.shared.fetchFills(cursor: cursor, limit: 100) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let (response, jsonStr)):
                    let newFills = response.fills ?? []
                    
                    // Filter duplicates to prevent infinite loops (API returning same page)
                    let uniqueFills = newFills.filter { !fetchedIds.contains($0.tradeId) }
                    
                    if uniqueFills.isEmpty && !newFills.isEmpty {
                        // We received fills but we have seen them all before.
                        // Loop detected. Stop.
                        print("Optimization: Duplicate fills detected (Loop). Stopping fetch.")
                        shouldContinue = false
                    }
                    
                    if uniqueFills.isEmpty && accumulated.isEmpty {
                        // Truly empty start
                         // Debug: Capture JSON if completely empty
                         print("Debug - Empty Fills JSON: \(jsonStr)")
                         let snippet = String(jsonStr.prefix(200))
                         DispatchQueue.main.async {
                             self.statusMessage = "Empty Response: \(snippet)"
                         }
                    }
                    
                    // Add to accumulated
                    accumulated.append(contentsOf: uniqueFills)
                    for fill in uniqueFills {
                        fetchedIds.insert(fill.tradeId)
                    }
                    
                    DispatchQueue.main.async {
                        self.statusMessage = "Fetching fills... (\(accumulated.count) fetched)"
                    }
                    
                    // Optimization: Check if we've reached past the cutoff date
                    if let lastFill = uniqueFills.last, let lastDate = lastFill.date {
                        if lastDate < cutoffDate {
                            print("Optimization: Reached cutoff date \(cutoffDate). Stopping fetch.")
                            shouldContinue = false
                        }
                    }
                    
                    if shouldContinue, let next = response.cursor, !uniqueFills.isEmpty {
                        fetch(cursor: next)
                    } else {
                        DispatchQueue.main.async {
                            self.allFills = accumulated
                            completion(nil)
                        }
                    }
                case .failure(let error):
                    print("Error fetching fills: \(error)")
                    DispatchQueue.main.async {
                        completion(error)
                    }
                }
            }
        }
        
        fetch(cursor: nil)
    }
    
    private func processFills() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async { self.statusMessage = "Reconstructing episodes..." }
            
            // Reconstruct
            var reconstructed = PositionReconstructor.reconstruct(fills: self.allFills)
            
            // Validation: Check for settlements on open positions
            DispatchQueue.main.async { self.statusMessage = "Checking market settlements..." }
            
            self.checkSettlements(episodes: reconstructed) { updatedEpisodes in
                self.cachedEpisodes = updatedEpisodes
                
                // Filter by date range
                let cutoff = Calendar.current.date(byAdding: .day, value: -self.selectedPeriod, to: Date()) ?? Date.distantPast
                
                let filteredEpisodes = self.cachedEpisodes.filter { $0.entryTime >= cutoff }
                
                let summary = "Fills: \(self.allFills.count), Ep: \(self.cachedEpisodes.count), Filt: \(filteredEpisodes.count)"
                print(summary)
                
                DispatchQueue.main.async {
                    self.episodes = filteredEpisodes
                    if filteredEpisodes.isEmpty {
                         self.statusMessage = "No trades in period. (Debug: \(summary))"
                         self.results = []
                         self.isRunning = false
                         self.hasRun = true
                    } else {
                        self.statusMessage = "Simulating \(filteredEpisodes.count) episodes..."
                        self.progress = 0.1
                        self.runSimulation(episodes: filteredEpisodes)
                    }
                }
            }
        }
    }
    
    private func checkSettlements(episodes: [TradeEpisode], completion: @escaping ([TradeEpisode]) -> Void) {
        let group = DispatchGroup()
        var updated = episodes
        // Use a lock for concurrent writes
        let lock = NSLock()
        
        for (index, ep) in episodes.enumerated() {
            if ep.exitTime == nil {
                // Open position, check if market is settled
                group.enter()
                NetworkManager.shared.fetchMarket(ticker: ep.ticker) { result in
                    defer { group.leave() }
                    
                    switch result {
                    case .success(let market):
                        // Check if settled
                        // Status values: "active", "closed", "finalized"
                        if let status = market.status, (status == "finalized" || status == "settled") {
                            // Determine settlement price
                            // If finalized, price is 100 (Yes won) or 0 (No won).
                            // Helper: lastPrice is usually reliable for settlement?
                            // Or check bids?
                            // If settled, no bids/asks usually.
                            
                            var finalPrice = 0.0
                            if let lp = market.lastPrice {
                                finalPrice = Double(lp) / 100.0
                            }
                            // Sanity check: Should be 0 or 1 usually.
                            
                            lock.lock()
                            let newEp = TradeEpisode(
                                id: ep.id,
                                ticker: ep.ticker,
                                side: ep.side,
                                avgEntryPrice: ep.avgEntryPrice,
                                quantity: ep.quantity,
                                entryTime: ep.entryTime,
                                exitTime: Date(), // Settled now (or createdTime of market close? don't have it)
                                marketResult: finalPrice >= 0.99 ? "yes" : "no",
                                marketSettled: true,
                                realizedPnL: (finalPrice - ep.avgEntryPrice) * Double(ep.quantity), // Estimated realized
                                avgExitPrice: finalPrice,
                                simulatedExitPrice: nil,
                                simulatedExitTime: nil,
                                simulatedPnL: nil,
                                exitReason: nil
                            )
                            updated[index] = newEp
                            lock.unlock()
                            
                            print("Settlement Found: \(ep.ticker) settled at \(finalPrice)")
                        }
                    case .failure:
                        break // Keep as is
                    }
                }
            }
        }
        
        group.notify(queue: .global()) {
            completion(updated)
        }
    }
    
    private func runSimulation(episodes: [TradeEpisode]) {
        // Create a serial queue for results
        var tempResults: [SimulationResult] = []
        var completed = 0
        let total = episodes.count
        
        let strat = BacktestStrategy(
            type: selectedStrategy,
            targetProfit: selectedStrategy.defaultTP,
            stopLoss: selectedStrategy.defaultSL,
            maxHoldSeconds: nil,
            slippageCents: 1
        )
        
        let operationQueue = OperationQueue() 
        operationQueue.maxConcurrentOperationCount = 2 // Match the BacktestDataService semaphore
        
        for episode in episodes {
            let operation = BlockOperation {
                let semaphore = DispatchSemaphore(value: 0)
                
                BacktestDataService.shared.getTrades(for: episode.ticker) { result in
                    var pnl: Double = 0
                    var resultType = "Skip"
                    
                    switch result {
                    case .success(let history):
                        if let res = BacktestEngine.run(episode: episode, history: history, strategy: strat) {
                            pnl = res.pnl
                            resultType = res.pnl >= 0 ? "Win" : "Loss"
                            DispatchQueue.main.async {
                                tempResults.append(res)
                            }
                        }
                    case .failure:
                        break
                    }
                    
                    DispatchQueue.main.async {
                         completed += 1
                         if total > 0 { self.progress = 0.1 + (0.9 * Double(completed) / Double(total)) }
                         self.statusMessage = "Simulating \(completed)/\(total): \(episode.ticker) (\(resultType))"
                         print("Processed \(episode.ticker): \(resultType) $\(String(format: "%.2f", pnl))")
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            }
            operationQueue.addOperation(operation)
        }
        
        // Completion observer
        DispatchQueue.global().async {
            operationQueue.waitUntilAllOperationsAreFinished()
            DispatchQueue.main.async {
                self.results = tempResults.sorted { $0.exitTime > $1.exitTime }
                self.computeKPIs()
                self.isRunning = false
                self.statusMessage = "Done"
                self.progress = 1.0
                self.hasRun = true
            }
        }
    }
    
    private func computeKPIs() {
        let totalPnl = results.reduce(0) { $0 + $1.pnl }
        let wins = results.filter { $0.pnl > 0 }.count
        let count = results.count
        
        self.strategyPnL = totalPnl
        self.tradeCount = count
        self.winRate = count > 0 ? Double(wins) / Double(count) : 0.0
    }
}

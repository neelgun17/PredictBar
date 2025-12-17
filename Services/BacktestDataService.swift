import Foundation

class BacktestDataService {
    static let shared = BacktestDataService()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let semaphore = DispatchSemaphore(value: 2) // Max 2 concurrent downloads
    
    // Cache structure: [[ts, price, qty], [ts, price, qty], ...]
    // price in cents, qty as int
    typealias TradeEntry = [Int]
    
    private init() {
        // Setup cache directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let kalshiDir = appSupport.appendingPathComponent("KalshiMenuBar", isDirectory: true)
        cacheDirectory = kalshiDir.appendingPathComponent("Backtesting", isDirectory: true)
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    func getTrades(for ticker: String, forceRefresh: Bool = false, progress: ((Double) -> Void)? = nil, completion: @escaping (Result<[TradeEntry], Error>) -> Void) {
        let fileURL = cacheDirectory.appendingPathComponent("trades_\(ticker).json")
        
        // 1. Load existing cache
        var cachedTrades: [TradeEntry] = []
        var lastTs = 0
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                cachedTrades = try JSONDecoder().decode([TradeEntry].self, from: data)
                if let last = cachedTrades.last {
                    lastTs = last[0]
                }
            } catch {
                print("Error reading cache for \(ticker): \(error)")
                // If corrupted, start over
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        // If we have data and don't need refresh (or data is very fresh), return immediately?
        // Actually, we always want to try and fetch latest unless covered.
        // But for backtest, maybe "fresh enough" is okay? 
        // Let's implement incremental fetch.
        
        let now = Int(Date().timeIntervalSince1970)
        // If lastTs is within 1 hour, maybe skip unless forced?
        // For MVP, always try to catch up.
        
        let minTs = lastTs > 0 ? lastTs + 1 : nil
        
        // Calculate progress steps if possible? difficult with pagination. w/e.
        print("Debug - getTrades for \(ticker): Start. LastTS: \(lastTs)")
        
        fetchTradesPaginated(ticker: ticker, minTs: minTs, maxTs: now) { [weak self] result in
            guard let self = self else { return }
            print("Debug - getTrades for \(ticker): Fetch Complete. Result: \(result.map { $0.count }) items")
            
            switch result {
            case .success(let newTrades):
                if newTrades.isEmpty {
                    completion(.success(cachedTrades))
                    return
                }
                
                // Merge and Save
                var merged = cachedTrades
                // Convert NetworkManager.PublicTrade to TradeEntry [ts, price, qty]
                let newEntries = newTrades.map { t -> TradeEntry in
                    // ISO8601 to Int timestamp
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let date = formatter.date(from: t.createdTime) ?? Date()
                    let ts = Int(date.timeIntervalSince1970)
                    return [ts, t.price, t.count]
                }
                
                // Sorting should be handled by API return order, but ensuring sort is safe
                // API returns oldest first usually if not specified, let's verify.
                // Kalshi /trades defaults to latest first? Need to check docs or behavior.
                // Docs: "Order direction is by created_time desc by default"
                // So we need to reverse them if we want chronological append.
                
                // Wait, if API returns DESC (latest first), and we asked for min_ts > last_known,
                // we get [newest ... oldest_but_newer_than_last].
                // So we should reverse `newEntries` before appending.
                
                let sortedNew = newEntries.sorted { $0[0] < $1[0] }
                merged.append(contentsOf: sortedNew)
                
                // Write to disk
                self.saveCache(trades: merged, url: fileURL)
                
                completion(.success(merged))
                
            case .failure(let error):
                if !cachedTrades.isEmpty {
                    print("Network error fetching trades for \(ticker), returning cached: \(error)")
                    completion(.success(cachedTrades)) // Fallback to cache
                } else {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    // Fetches candles (as trades) using the series/market endpoint (since /trades is broken/404)
    private func fetchTradesPaginated(ticker: String, minTs: Int?, maxTs: Int?, accumulated: [NetworkManager.PublicTrade] = [], cursor: String? = nil, completion: @escaping (Result<[NetworkManager.PublicTrade], Error>) -> Void) {
        
        // 1. We need the Series Ticker first.
        print("Debug - fetchCandles (via market) for \(ticker): Fetching market details...")
        semaphore.wait()
        
        // We really need to release the semaphore before completion in all paths
        
        NetworkManager.shared.fetchMarket(ticker: ticker) { [weak self] marketResult in
            guard let self = self else { 
                self?.semaphore.signal()
                return 
            }
            
            switch marketResult {
            case .failure(let error):
                print("Debug - fetchCandles: Failed to get market details: \(error)")
                self.semaphore.signal()
                completion(.failure(error))
                
            case .success(let market):
                // 2. Resolve Series Ticker (Market -> Event -> Series fallback)
                func proceedWithSeries(_ series: String) {
                    let start = minTs ?? (Int(Date().timeIntervalSince1970) - 30 * 24 * 3600) // Default 30 days
                    let end = maxTs ?? Int(Date().timeIntervalSince1970)
                    
                    print("Debug - fetchCandles: Got series \(series). Fetching candles...")
                    
                    // Chunking logic: API limit is 5000 candles. 
                    // 30 days = 43,200 minutes. We need to split this.
                    // Let's safe chunk at 4000 minutes (approx 2.7 days).
                    let chunkSize = 4000 * 60 // in seconds
                    
                    var allCandles: [NetworkManager.Candlestick] = []
                    
                    func fetchChunk(currentStart: Int) {
                        if currentStart >= end {
                            // Done fetching all chunks
                            print("Debug - fetchCandles: Finished fetching chunks. Total \(allCandles.count) candles.")
                            
                             // Convert Candles to fake "PublicTrade" objects
                            let fakeTrades = allCandles.compactMap { candle -> NetworkManager.PublicTrade? in
                                guard let ts = candle.endPeriodTs else { return nil }
                                
                                var priceVal: Double?
                                if let p = candle.midPrice?.close ?? candle.price?.close ?? candle.yesBid?.close {
                                    priceVal = Double(p)
                                }
                                guard let price = priceVal else { return nil }
                                
                                let date = Date(timeIntervalSince1970: TimeInterval(ts))
                                let iso = ISO8601DateFormatter()
                                iso.formatOptions = [.withInternetDateTime]
                                let dateStr = iso.string(from: date)
                                
                                return NetworkManager.PublicTrade(
                                    price: Int(price),
                                    count: 100,
                                    createdTime: dateStr,
                                    takerSide: "yes"
                                )
                            }
                            
                            self.semaphore.signal()
                            completion(.success(fakeTrades))
                            return
                        }
                        
                        let currentEnd = min(currentStart + chunkSize, end)
                        print("Debug - fetchCandles: Fetching chunk \(currentStart) to \(currentEnd)...")
                        
                        NetworkManager.shared.fetchCandles(seriesTicker: series, marketTicker: ticker, startTs: currentStart, endTs: currentEnd) { candleResult in
                            switch candleResult {
                            case .failure(let error):
                                print("Debug - fetchCandles: Chunk failed: \(error)")
                                // If one chunk fails, maybe we still return what we have? 
                                // Or fail? Let's fail for now to be safe.
                                self.semaphore.signal()
                                completion(.failure(error))
                                
                            case .success(let candles):
                                allCandles.append(contentsOf: candles)
                                // Next chunk
                                fetchChunk(currentStart: currentEnd)
                            }
                        }
                    }
                    
                    // Start fetching
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                         fetchChunk(currentStart: start)
                    }
                }
                
                if let series = market.seriesTicker {
                    proceedWithSeries(series)
                } else {
                    // Fallback: Fetch Event to get Series
                    print("Debug - fetchCandles: Missing series for \(ticker), fetching Event \(market.eventTicker)...")
                    NetworkManager.shared.fetchEvent(eventTicker: market.eventTicker) { eventResult in
                        switch eventResult {
                        case .success(let event):
                            proceedWithSeries(event.seriesTicker)
                        case .failure(let error):
                             print("Debug - fetchCandles: Failed to get event: \(error)")
                             self.semaphore.signal()
                             completion(.failure(error))
                        }
                    }
                }
            }
        }
    }
    
    private func saveCache(trades: [TradeEntry], url: URL) {
        do {
            let data = try JSONEncoder().encode(trades)
            try data.write(to: url)
        } catch {
            print("Failed to save cache: \(error)")
        }
    }
}

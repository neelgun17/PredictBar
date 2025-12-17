import Foundation

enum StrategyType: String, CaseIterable, Identifiable {
    case balanced = "Balanced"
    case momentum = "Momentum"
    case conservative = "Conservative"
    case swing = "Swing"
    case hodl = "Hodl"
    case history = "History"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var defaultTP: Double {
        switch self {
        case .balanced: return 0.10
        case .momentum: return 0.20
        case .conservative: return 0.05
        case .swing: return 0.30
        case .custom: return 0.10
        case .hodl, .history: return 100.0 // Never take profit
        }
    }
    
    var defaultSL: Double {
        switch self {
        case .balanced: return 0.10
        case .momentum: return 0.05
        case .conservative: return 0.05
        case .swing: return 0.15
        case .custom: return 0.10
        case .hodl, .history: return 2.0 // Never stop loss
        }
    }
}

struct BacktestStrategy {
    let type: StrategyType
    let targetProfit: Double // 0.10 for 10%
    let stopLoss: Double // 0.10 for 10%
    let maxHoldSeconds: Int?
    let slippageCents: Int // Conservative slippage, default 1 cent
}

struct TradeEpisode: Identifiable, Codable {
    let id: String
    let ticker: String
    let side: String // "yes" or "no"
    let avgEntryPrice: Double // 0.01 - 0.99
    let quantity: Int
    let entryTime: Date
    let exitTime: Date? // If user actually closed
    let marketResult: String? // "yes", "no", or nil if active
    let marketSettled: Bool
    
    // Actual History
    let realizedPnL: Double?
    let avgExitPrice: Double?
    
    // For backtest
    var simulatedExitPrice: Double?
    var simulatedExitTime: Date?
    var simulatedPnL: Double?
    var exitReason: String? // "TP", "SL", "Time", "End"
}

struct SimulationResult: Identifiable {
    var id: String { episodeId }
    let episodeId: String
    let exitPrice: Double
    let exitTime: Date
    let pnl: Double
    let roi: Double
    let reason: String
}

class BacktestEngine {
    
    static func run(episode: TradeEpisode, history: [BacktestDataService.TradeEntry], strategy: BacktestStrategy) -> SimulationResult? {
        
        // Handle "History" Strategy (Actual PnL)
        if strategy.type == .history {
            if let pnl = episode.realizedPnL, let exitTime = episode.exitTime, let exitPrice = episode.avgExitPrice {
                // Return actual realized result
                let roi = (exitPrice - episode.avgEntryPrice) / episode.avgEntryPrice
                return SimulationResult(
                    episodeId: episode.id,
                    exitPrice: exitPrice,
                    exitTime: exitTime,
                    pnl: pnl,
                    roi: roi,
                    reason: "Actual"
                )
            }
            // If active/unrealized, fall through to HODL logic (Mark-to-Market)
        }
        
        guard history.isEmpty == false else { return nil }
        
        let entryTs = Int(episode.entryTime.timeIntervalSince1970)
        
        // Filter history for relevant period: entry -> end
        // Optimization: Binary search start index
        
        // Calculate targets
        // Is YES position?
        let isYes = episode.side.lowercased() == "yes"
        let entry = episode.avgEntryPrice
        
        // YES: Profit if Price > Entry. Loss if Price < Entry.
        // NO: Profit if Price < Entry. Loss if Price > Entry. (Inverted price logic?)
        // Wait, Kalshi trades are always priced in "Yes".
        // If I bought NO at 0.40, I paid 0.40. It roughly equals YES at 0.60.
        // If "Yes" price goes to 0.50, my NO is worth 0.50 (profit).
        // If "Yes" price goes to 0.70, my NO is worth 0.30 (loss).
        
        // Wait, `entryPrice` in `TradeEpisode` should be normalized to the price paid (0-0.99).
        // If side is NO, and price paid is 0.40.
        // Current Market Price (YES price) being 0.60 means NO is 0.40.
        // Current Market Price (YES price) being 0.50 means NO is 0.50.
        
        // Let's normalize everything to "Value of my position".
        // If YES: Value = MarketPrice
        // If NO: Value = 1.00 - MarketPrice
        
        // TP (+10%): TargetValue = Entry * 1.10
        // SL (-10%): StopValue = Entry * 0.90
        
        let targetValue = entry * (1.0 + strategy.targetProfit)
        let stopValue = entry * (1.0 - strategy.stopLoss)
        
        // Iterate through history
        for row in history {
            let ts = row[0]
            let priceCents = row[1]
            // let qty = row[2] // unused for price simulation
            
            if ts < entryTs { continue }
            
            let marketPrice = Double(priceCents) / 100.0
            
            let currentPositionValue: Double
            if isYes {
                currentPositionValue = marketPrice
            } else {
                currentPositionValue = 1.0 - marketPrice
            }
            
            // Check signals
            // Check SL first? Or TP? Usually check both.
            // Assuming 1m bars, high/low not available in this simple history, just close.
            
            var hitTP = false
            var hitSL = false
            
            if currentPositionValue >= targetValue {
                hitTP = true
            } else if currentPositionValue <= stopValue {
                hitSL = true
            }
            
            if hitTP {
                // Execute TP
                // Slip? If I sell, I might get worse price.
                // Conservative: Deduct slippage from EXIT VALUE.
                let rawExit = currentPositionValue
                let slippageParam = Double(strategy.slippageCents) / 100.0
                let exitPrice = max(0, rawExit - slippageParam)
                
                let pnl = (exitPrice - entry) * Double(episode.quantity)
                let roi = (exitPrice - entry) / entry
                
                return SimulationResult(
                    episodeId: episode.id,
                    exitPrice: exitPrice,
                    exitTime: Date(timeIntervalSince1970: TimeInterval(ts)),
                    pnl: pnl,
                    roi: roi,
                    reason: "TP"
                )
            }
            
            if hitSL {
                // Execute SL
                // Assumption: Stop order triggers AT the stop price.
                // In reality, it fills at the best available price after triggering.
                // With 1m candles, if we cross the line, we likely filled near the line.
                // If it's a massive gap (e.g. 0.99 -> 0.01), this is optimistic.
                // But generally better than exiting at the bottom of the candle.
                
                // Let's use the stop price itself as the base exit.
                let baseExit = stopValue
                let slippageParam = Double(strategy.slippageCents) / 100.0
                
                // Ensure we don't exit below 0 or above 1 (sanity)
                // And ensure we don't "improve" our exit if the market price is actually WAY worse?
                // For safety in this MVP: Exit at Stop Price - Slippage.
                // If marketPrice is significantly lower (e.g. > 5 cent gap), maybe split difference?
                // Let's stick to Stop Price for standardized testing.
                
                let exitPrice = max(0, baseExit - slippageParam)
                
                 let pnl = (exitPrice - entry) * Double(episode.quantity)
                let roi = (exitPrice - entry) / entry
                
                return SimulationResult(
                    episodeId: episode.id,
                    exitPrice: exitPrice,
                    exitTime: Date(timeIntervalSince1970: TimeInterval(ts)),
                    pnl: pnl,
                    roi: roi,
                    reason: "SL"
                )
            }
            
            // Check Time Limit
            if let maxSeconds = strategy.maxHoldSeconds {
                if ts - entryTs >= maxSeconds {
                    // Time exit
                   let rawExit = currentPositionValue
                   // Maybe less slippage on time exit?
                   let exitPrice = rawExit 
                   
                   let pnl = (exitPrice - entry) * Double(episode.quantity)
                   let roi = (exitPrice - entry) / entry
                   
                   return SimulationResult(
                       episodeId: episode.id,
                       exitPrice: exitPrice,
                       exitTime: Date(timeIntervalSince1970: TimeInterval(ts)),
                       pnl: pnl,
                       roi: roi,
                       reason: "Time"
                   )
                }
            }
        }
        
        // If loop finishes, hold to end
        // Last price
        guard let last = history.last else { return nil }
        let lastTs = last[0]
        let lastPriceCents = last[1]
        let marketPrice = Double(lastPriceCents) / 100.0
        
        let finalValue = isYes ? marketPrice : (1.0 - marketPrice)
        let pnl = (finalValue - entry) * Double(episode.quantity)
        let roi = (finalValue - entry) / entry
        
        return SimulationResult(
            episodeId: episode.id,
            exitPrice: finalValue,
            exitTime: Date(timeIntervalSince1970: TimeInterval(lastTs)),
            pnl: pnl,
            roi: roi,
            reason: "Hold"
        )
    }
}

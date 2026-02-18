import Foundation

struct TradeResult {
    let ticker: String
    let pnl: Double
    let date: Date?
}

enum StreakType {
    case win
    case loss
}

struct Streak {
    let type: StreakType
    let count: Int

    var display: String {
        switch type {
        case .win: return "\(count)W"
        case .loss: return "\(count)L"
        }
    }
}

struct MarketStats: Identifiable {
    let ticker: String
    let trades: Int
    let pnl: Double
    let winRate: Double

    var id: String { ticker }
}

struct TradeMetrics {
    let totalTrades: Int
    let totalBuys: Int
    let totalSells: Int
    let totalRealizedPnL: Double
    let totalFeesPaid: Double
    let winRate: Double
    let avgProfitPerTrade: Double
    let bestTrade: TradeResult?
    let worstTrade: TradeResult?

    let currentStreak: Streak
    let longestWinStreak: Int
    let longestLossStreak: Int

    let pnlByMonth: [(month: String, pnl: Double)]
    let marketBreakdown: [MarketStats]

    /// Extract league/category from a Kalshi ticker.
    /// e.g. "KXNBAGAME-25NOV19NYKDAL-NYK" → "NBA"
    ///      "KXNFLMVP-26-MSTA" → "NFL"
    ///      "KXFIFAGAME-25NOV18BRATUN-TIE" → "FIFA"
    ///      "KXATPMATCH-25DEC17LANBUD-BUD" → "ATP"
    ///      "KXNCAAFGAME-..." → "NCAAF"
    ///      "INX..." or other → ticker prefix
    static func extractCategory(from ticker: String) -> String {
        // Most Kalshi sports tickers start with "KX" followed by the league
        let upper = ticker.uppercased()
        guard upper.hasPrefix("KX") else {
            // Non-KX tickers: take everything before the first dash or hyphen
            if let dashIdx = ticker.firstIndex(of: "-") {
                return String(ticker[ticker.startIndex..<dashIdx])
            }
            return ticker
        }

        // Strip "KX" prefix, then extract the league before the type suffix
        let afterKX = String(upper.dropFirst(2))

        // Known type suffixes to strip (order matters — check longer ones first)
        let typeSuffixes = ["GAME", "MATCH", "MVP", "SERIES", "PROP", "FUTURES", "WINNER", "TOTAL", "SPREAD"]
        for suffix in typeSuffixes {
            if afterKX.hasPrefix(suffix) {
                // The category IS the suffix (unlikely, but handle)
                return suffix
            }
            // Check if the category precedes the suffix, e.g. "NBAGAME" → "NBA"
            if let range = afterKX.range(of: suffix) {
                let category = String(afterKX[afterKX.startIndex..<range.lowerBound])
                if !category.isEmpty {
                    return category
                }
            }
        }

        // Fallback: take everything before the first dash in afterKX
        if let dashIdx = afterKX.firstIndex(of: "-") {
            return String(afterKX[afterKX.startIndex..<dashIdx])
        }
        return afterKX
    }

    static func compute(from fills: [Fill]) -> TradeMetrics {
        let buys = fills.filter { $0.action.lowercased() == "buy" }
        let sells = fills.filter { $0.action.lowercased() == "sell" }
        let totalFees = fills.reduce(0.0) { $0 + Double($1.totalFeeVal) / 100.0 }

        // Group fills by marketTicker — match buys with sells chronologically (FIFO)
        let grouped = Dictionary(grouping: fills) { $0.marketTicker }

        var roundTrips: [TradeResult] = []
        var perCategoryResults: [String: [TradeResult]] = [:]

        for (ticker, tickerFills) in grouped {
            let sorted = tickerFills.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            var buyQueue: [(price: Double, count: Int, date: Date?)] = []

            for fill in sorted {
                let pricePerContract = Double(fill.price) / 100.0
                let action = fill.action.lowercased()
                if action == "buy" {
                    buyQueue.append((price: pricePerContract, count: fill.count, date: fill.date))
                } else if action == "sell" {
                    var remaining = fill.count
                    let sellPrice = pricePerContract

                    while remaining > 0 && !buyQueue.isEmpty {
                        var buy = buyQueue[0]
                        let matched = min(remaining, buy.count)

                        // Simple P&L: sell price - buy price per contract
                        let pnl = (sellPrice - buy.price) * Double(matched)
                        let result = TradeResult(ticker: ticker, pnl: pnl, date: fill.date)
                        roundTrips.append(result)

                        let category = extractCategory(from: ticker)
                        perCategoryResults[category, default: []].append(result)

                        remaining -= matched
                        buy.count -= matched
                        if buy.count == 0 {
                            buyQueue.removeFirst()
                        } else {
                            buyQueue[0] = buy
                        }
                    }
                }
            }
        }


        // Sort round trips by date
        let sortedTrips = roundTrips.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        // Win rate
        let wins = sortedTrips.filter { $0.pnl > 0 }
        let winRate = sortedTrips.isEmpty ? 0.0 : Double(wins.count) / Double(sortedTrips.count)

        // Total realized P&L
        let totalPnL = sortedTrips.reduce(0.0) { $0 + $1.pnl }
        let avgProfit = sortedTrips.isEmpty ? 0.0 : totalPnL / Double(sortedTrips.count)

        // Best/worst
        let best = sortedTrips.max(by: { $0.pnl < $1.pnl })
        let worst = sortedTrips.min(by: { $0.pnl < $1.pnl })

        // Streaks
        var currentStreakType: StreakType = .win
        var currentStreakCount = 0
        var longestWin = 0
        var longestLoss = 0
        var tempWin = 0
        var tempLoss = 0

        for trip in sortedTrips {
            if trip.pnl > 0 {
                tempWin += 1
                tempLoss = 0
                longestWin = max(longestWin, tempWin)
            } else {
                tempLoss += 1
                tempWin = 0
                longestLoss = max(longestLoss, tempLoss)
            }
        }

        // Current streak from end
        if let last = sortedTrips.last {
            currentStreakType = last.pnl > 0 ? .win : .loss
            currentStreakCount = 1
            for trip in sortedTrips.dropLast().reversed() {
                let isWin = trip.pnl > 0
                if (isWin && currentStreakType == .win) || (!isWin && currentStreakType == .loss) {
                    currentStreakCount += 1
                } else {
                    break
                }
            }
        }

        // P&L by month
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"

        var monthPnL: [String: Double] = [:]
        var monthOrder: [String] = []

        for trip in sortedTrips {
            let key: String
            if let date = trip.date {
                key = monthFormatter.string(from: date)
            } else {
                key = "Unknown"
            }
            if monthPnL[key] == nil {
                monthOrder.append(key)
            }
            monthPnL[key, default: 0.0] += trip.pnl
        }

        let pnlByMonth = monthOrder.map { (month: $0, pnl: monthPnL[$0] ?? 0.0) }

        // Per-category breakdown (grouped by league/sport)
        var marketStats: [MarketStats] = []
        for (category, results) in perCategoryResults {
            let mPnL = results.reduce(0.0) { $0 + $1.pnl }
            let mWins = results.filter { $0.pnl > 0 }.count
            let mWinRate = results.isEmpty ? 0.0 : Double(mWins) / Double(results.count)
            marketStats.append(MarketStats(ticker: category, trades: results.count, pnl: mPnL, winRate: mWinRate))
        }
        marketStats.sort { $0.pnl > $1.pnl }

        return TradeMetrics(
            totalTrades: sortedTrips.count,
            totalBuys: buys.count,
            totalSells: sells.count,
            totalRealizedPnL: totalPnL,
            totalFeesPaid: totalFees,
            winRate: winRate,
            avgProfitPerTrade: avgProfit,
            bestTrade: best,
            worstTrade: worst,
            currentStreak: Streak(type: currentStreakType, count: currentStreakCount),
            longestWinStreak: longestWin,
            longestLossStreak: longestLoss,
            pnlByMonth: pnlByMonth,
            marketBreakdown: marketStats
        )
    }
}

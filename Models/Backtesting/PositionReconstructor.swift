import Foundation

class PositionReconstructor {
    
    static func reconstruct(fills: [Fill]) -> [TradeEpisode] {
        let grouped = Dictionary(grouping: fills, by: { $0.marketTicker })
        var episodes: [TradeEpisode] = []
        
        for (ticker, tickerFills) in grouped {
            let sorted = tickerFills.sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }
            
            // State tracking for both sides
            struct OpenState {
                var currentQty: Int = 0
                var buys: [Fill] = []
                var sells: [Fill] = []
            }
            
            var positions: [String: OpenState] = [
                "yes": OpenState(),
                "no": OpenState()
            ]

            for fill in sorted {
                let isBuy = fill.action == "buy"
                let side = fill.side
                let otherSide = side == "yes" ? "no" : "yes"
                
                if isBuy {
                    // Add to position
                    positions[side]?.currentQty += fill.count
                    positions[side]?.buys.append(fill)
                } else {
                    // Sell
                    // Check if we have a position on this side
                    if (positions[side]?.currentQty ?? 0) > 0 {
                        positions[side]?.currentQty -= fill.count
                        positions[side]?.sells.append(fill)
                    } else if (positions[otherSide]?.currentQty ?? 0) > 0 {
                        // Mismatched Sell (Orphan Sell Strategy)
                        positions[otherSide]?.currentQty -= fill.count
                        positions[otherSide]?.sells.append(fill)
                    } else {
                        // Truly orphan sell (missing buy history?)
                        // Ignore
                    }
                }
                
                // Check for episode completion
                for checkSide in ["yes", "no"] {
                    if let p = positions[checkSide], !p.buys.isEmpty, p.currentQty == 0 {
                        // Episode closed
                        let (pnl, avgExit, realizedFees) = calculatePnL(buys: p.buys, sells: p.sells)
                        let ep = createEpisode(ticker: ticker, side: checkSide, buys: p.buys, exitTime: p.sells.last?.date, settled: false, realizedPnL: pnl, avgExitPrice: avgExit)
                        episodes.append(ep)
                        
                        // Reset
                        positions[checkSide] = OpenState()
                    }
                }
            }
            
            // Handle remaining open positions
            for checkSide in ["yes", "no"] {
                if let p = positions[checkSide], !p.buys.isEmpty, p.currentQty > 0 {
                    // Active Episode
                    let ep = createEpisode(ticker: ticker, side: checkSide, buys: p.buys, exitTime: nil, settled: false, realizedPnL: nil, avgExitPrice: nil)
                    episodes.append(ep)
                }
            }
        }
        
        return episodes.sorted { $0.entryTime > $1.entryTime }
    }
    
    private static func calculatePnL(buys: [Fill], sells: [Fill]) -> (Double, Double, Double) {
        var totalBuyCost = 0.0
        var totalBuyQty = 0
        var totalPropFees = 0.0
        
        for b in buys {
            let cost = Double(b.count * b.price)
            let fee = Double(b.totalFeeVal)
            totalBuyCost += cost
            totalPropFees += fee
            totalBuyQty += b.count
        }
        
        var totalSellProceeds = 0.0
        var totalSellQty = 0
        var totalSellFees = 0.0
        
        for s in sells {
            let proceeds = Double(s.count * s.price)
            let fee = Double(s.totalFeeVal)
            totalSellProceeds += proceeds
            totalSellFees += fee
            totalSellQty += s.count
        }
        
        // PnL = Proceeds - Cost - Fees
        // But need to prorate cost if partial? (Here we only call on closure so totalBuyQty should match totalSellQty roughly, or at least we sold 'totalSellQty')
        
        let avgEntryCents = totalBuyQty > 0 ? (totalBuyCost / Double(totalBuyQty)) : 0
        let costOfSold = avgEntryCents * Double(totalSellQty)
        
        // Pro-rate buy fees?
        let buyFeesOfSold = totalBuyQty > 0 ? (totalPropFees / Double(totalBuyQty)) * Double(totalSellQty) : 0
        
        let pnlCents = totalSellProceeds - costOfSold - buyFeesOfSold - totalSellFees
        
        let pnl = pnlCents / 100.0
        let avgExit = totalSellQty > 0 ? (totalSellProceeds / Double(totalSellQty)) / 100.0 : 0.0
        let totalFees = (buyFeesOfSold + totalSellFees) / 100.0
        
        return (pnl, avgExit, totalFees)
    }
    
    private static func createEpisode(ticker: String, side: String, buys: [Fill], exitTime: Date?, settled: Bool, realizedPnL: Double?, avgExitPrice: Double?) -> TradeEpisode {
        var totalQty = 0
        var totalCost = 0.0
        var minTime = Date.distantFuture
        var totalFees = 0.0
        
        for buy in buys {
            totalQty += buy.count
            totalCost += Double(buy.count * buy.price)
            totalFees += Double(buy.totalFeeVal)
            
            if let d = buy.date, d < minTime {
                minTime = d
            }
        }
        
        // Avg Entry SHOULD include fees according to user
        // "Total Cost" = (Price * Qty) + Fees
        // Avg Entry = Total Cost / Qty
        let totalCostWithFees = totalCost + totalFees
        let avgPriceCents = totalQty > 0 ? totalCostWithFees / Double(totalQty) : 0.0
        let avgPrice = avgPriceCents / 100.0
        
        let id = "\(ticker)-\(side)-\(minTime.timeIntervalSince1970)"
        
        return TradeEpisode(
            id: id,
            ticker: ticker,
            side: side,
            avgEntryPrice: avgPrice,
            quantity: totalQty,
            entryTime: minTime,
            exitTime: exitTime,
            marketResult: nil,
            marketSettled: settled,
            realizedPnL: realizedPnL,
            avgExitPrice: avgExitPrice
        )
    }
}

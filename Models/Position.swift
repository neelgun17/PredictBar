import Foundation

struct Position: Identifiable, Codable {
    let ticker: String
    let position: Int
    let feesPaid: Int?
    let realizedPnl: Int?
    let totalTraded: Int?
    let marketExposure: Int?
    
    // Enriched data from Market API
    var title: String?
    var subtitle: String?
    var eventTicker: String?
    var marketUrl: URL?
    var seriesTicker: String? = nil
    
    // History for sparklines
    var history: [Double] = []
    
    // Computed properties for app compatibility
    var id: String { ticker }
    var marketTicker: String { ticker }
    var quantity: Int { position }
    
    // Determine side based on position sign
    var side: String {
        return position > 0 ? "Yes" : "No"
    }
    
    // Cost basis calculation
    // Use marketExposure (cents) from API if available, otherwise fallback to totalTraded
    var entryPrice: Double {
        if let exposure = marketExposure, position != 0 {
            return (Double(exposure) / 100.0) / Double(abs(position))
        }
        
        guard let cost = totalTraded, position != 0 else { return 0.0 }
        // cost is in cents, convert to dollars and average
        return (Double(cost) / 100.0) / Double(abs(position))
    }

    /// Total dollars spent to open the position (cost basis)
    var totalCostBasis: Double {
        if let exposure = marketExposure {
            return Double(exposure) / 100.0
        }
        let contracts = Double(abs(quantity))
        return contracts * entryPrice
    }
    
    // This gets updated via WebSocket
    var currentPrice: Double = 0.0
    
    // MARK: - Realistic stats (if we sold everything right now)
    //
    // commission = 0.07 * contracts * sellPrice * (1 - sellPrice)
    // rounded to nearest cent
    private func calculateRealisticStats() -> (roi: Double, pnl: Double, netProceeds: Double) {
        let totalCost = totalCostBasis
        // If no meaningful cost basis, bail out
        guard totalCost > 0, quantity != 0 else { return (0.0, 0.0, 0.0) }

        let contracts = Double(abs(quantity))
        let sellPrice = currentPrice

        // Gross proceeds if we hit "Sell" on all contracts at currentPrice
        let gross = contracts * sellPrice
        
        // Raw commission for the whole position
        let rawCommission = 0.07 * contracts * sellPrice * (1.0 - sellPrice)
        
        // Round commission to nearest cent
        let roundedCommission = (rawCommission * 100.0).rounded(.toNearestOrAwayFromZero) / 100.0
        
        // Net cash we actually get after commission
        let netProceeds = gross - roundedCommission
        
        // PnL and ROI based on net proceeds
        let calculatedPnl = netProceeds - totalCost
        let calculatedRoi = totalCost > 0 ? (calculatedPnl / totalCost) : 0.0
        
        return (calculatedRoi, calculatedPnl, netProceeds)
    }
    
    // Exposed computed properties
    
    /// Realized ROI for this position (if we sold everything now, after fees)
    var realizedROI: Double {
        return calculateRealisticStats().roi
    }
    
    /// Dollar PnL (profit/loss) for this position, after fees
    var realizedPnL: Double {
        return calculateRealisticStats().pnl
    }
    
    /// Net proceeds (cash you’d receive) if you sold the whole position now
    var netProceedsAfterFees: Double {
        return calculateRealisticStats().netProceeds
    }

    /// Executable sell price based on best-known bid/ask for this side
    /// yesBid/noBid/yesAsk/lastPrice are in dollars (0.00 - 1.00)
    func executableSellPrice(yesBid: Double?, noBid: Double?, yesAsk: Double?, lastPrice: Double?) -> Double? {
        let isYes = quantity >= 0

        if isYes {
            if let bid = yesBid { return bid } // best executable for long yes is yes bid
        } else {
            if let bid = noBid { return bid } // best executable for long no is no bid
            if let ask = yesAsk { return 1.0 - ask } // derive no bid from yes ask if needed
        }

        // Fallbacks if no firm bid available
        if let last = lastPrice { return last }
        if let bid = yesBid { return isYes ? bid : (1.0 - bid) }
        return nil
    }
    
    enum CodingKeys: String, CodingKey {
        case ticker
        case position
        case feesPaid
        case realizedPnl
        case totalTraded
        case marketExposure
        case title
        case subtitle
        case eventTicker
    }
}

import Foundation

struct Position: Identifiable, Decodable {
    // MARK: - Nested Types

    struct ArbitrageOpportunity: Codable, Equatable {
        let guaranteedProfit: Double      // Net profit after all fees
        let oppositeSidePrice: Double     // Price to buy opposite side
        let totalCostToHedge: Double      // Total cost including commission
        let profitPerContract: Double     // Profit per contract
        let timestamp: Date
    }

    // MARK: - Properties

    let ticker: String
    let position: Int
    let feesPaid: Int?
    let realizedPnl: Int?
    let totalTraded: Int?
    let marketExposure: Int?

    // Memberwise init — used by tests and any code that constructs a Position by hand.
    init(
        ticker: String,
        position: Int,
        feesPaid: Int? = nil,
        realizedPnl: Int? = nil,
        totalTraded: Int? = nil,
        marketExposure: Int? = nil
    ) {
        self.ticker = ticker
        self.position = position
        self.feesPaid = feesPaid
        self.realizedPnl = realizedPnl
        self.totalTraded = totalTraded
        self.marketExposure = marketExposure
    }

    // Kalshi's /portfolio/positions response. Around early 2026 they migrated from
    // integer cents + signed integer position to decimal-string dollars + fractional
    // shares. We decode the new shape and normalize back to the cents/contracts
    // representation the rest of the app already expects.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try c.decode(String.self, forKey: .ticker)

        let positionString = try c.decode(String.self, forKey: .positionFp)
        let positionDouble = Double(positionString) ?? 0
        position = Int(positionDouble.rounded())

        feesPaid = Self.decodeDollars(c, key: .feesPaidDollars)
        realizedPnl = Self.decodeDollars(c, key: .realizedPnlDollars)
        totalTraded = Self.decodeDollars(c, key: .totalTradedDollars)
        marketExposure = Self.decodeDollars(c, key: .marketExposureDollars)
    }

    private static func decodeDollars(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        guard let s = try? c.decodeIfPresent(String.self, forKey: key), let d = Double(s) else { return nil }
        return Int((d * 100).rounded())
    }

    
    // Enriched data from Market API
    var title: String?
    var subtitle: String?
    var eventTicker: String?
    var marketUrl: URL?
    var seriesTicker: String? = nil
    var seriesTitle: String? = nil
    var status: String? = nil
    
    // Alert state tracking
    var lastROI: Double? = nil

    // Price tracking for arbitrage detection
    var yesBid: Double? = nil
    var yesAsk: Double? = nil
    var noBid: Double? = nil
    var noAsk: Double? = nil
    var lastArbitrageOpportunity: ArbitrageOpportunity? = nil

    // History for sparklines
    var history: [Double] = []

    // MARK: - Computed Properties

    var id: String { ticker }
    var marketTicker: String { ticker }
    var quantity: Int { abs(position) }
    
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

    /// Kalshi taker trading fee, rounded UP to the next cent per the official
    /// fee schedule: ceil(0.07 * contracts * price * (1 - price)).
    static func tradingFee(contracts: Double, price: Double) -> Double {
        let raw = 0.07 * contracts * price * (1.0 - price)
        return (raw * 100.0).rounded(.up) / 100.0
    }

    private func calculateRealisticStats() -> (roi: Double, pnl: Double, netProceeds: Double) {
        let totalCost = totalCostBasis
        // If no meaningful cost basis, bail out
        guard totalCost > 0, quantity != 0 else { return (0.0, 0.0, 0.0) }

        let contracts = Double(abs(quantity))
        let sellPrice = currentPrice

        // Gross proceeds if we hit "Sell" on all contracts at currentPrice
        let gross = contracts * sellPrice

        // Net cash we actually get after commission
        let netProceeds = gross - Self.tradingFee(contracts: contracts, price: sellPrice)
        
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
    
    /// Helper for "Cash Out" value (same as netProceedsAfterFees)
    var cashOutValue: Double {
        return netProceedsAfterFees
    }

    /// Executable sell price based on best-known bid/ask for this side
    /// yesBid/noBid/yesAsk/lastPrice are in dollars (0.00 - 1.00)
    func executableSellPrice(yesBid: Double?, noBid: Double?, yesAsk: Double?, lastPrice: Double?) -> Double? {
        let isYes = position > 0  // Use original signed position value

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

    /// Detects if an arbitrage opportunity exists for this position
    /// Returns ArbitrageOpportunity if profitable, nil otherwise
    func detectArbitrage(minimumProfit: Double = 0.01) -> ArbitrageOpportunity? {
        guard position != 0 else { return nil }

        let contracts = Double(abs(position))
        let isYesPosition = position > 0

        // Determine price to buy opposite side
        let oppositeSideAsk: Double?
        if isYesPosition {
            // For YES position, need to buy NO at noAsk. By orderbook parity
            // noAsk = 1 - yesBid (Kalshi publishes only bids).
            oppositeSideAsk = noAsk ?? yesBid.map { 1.0 - $0 }
        } else {
            // For NO position, need to buy YES at yesAsk (= 1 - noBid).
            oppositeSideAsk = yesAsk ?? noBid.map { 1.0 - $0 }
        }

        guard let oppositePrice = oppositeSideAsk, oppositePrice > 0 else {
            return nil
        }

        // Calculate costs
        let originalCost = totalCostBasis
        let oppositeSideGross = contracts * oppositePrice

        let commission = Self.tradingFee(contracts: contracts, price: oppositePrice)
        let totalCostToHedge = oppositeSideGross + commission
        let totalInvested = originalCost + totalCostToHedge
        let guaranteedPayout = contracts * 1.0
        let netProfit = guaranteedPayout - totalInvested
        let profitPerContract = netProfit / contracts

        guard netProfit >= minimumProfit else { return nil }

        return ArbitrageOpportunity(
            guaranteedProfit: netProfit,
            oppositeSidePrice: oppositePrice,
            totalCostToHedge: totalCostToHedge,
            profitPerContract: profitPerContract,
            timestamp: Date()
        )
    }

    enum CodingKeys: String, CodingKey {
        case ticker
        case positionFp
        case feesPaidDollars
        case realizedPnlDollars
        case totalTradedDollars
        case marketExposureDollars
    }
}

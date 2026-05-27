import XCTest
@testable import PredictBar

final class PositionTests: XCTestCase {

    // Build a long-Yes position from raw values matching what Kalshi's API returns.
    // marketExposure and totalTraded are in cents.
    private func makePosition(
        ticker: String = "TEST-MKT",
        position: Int,
        marketExposure: Int? = nil,
        totalTraded: Int? = nil,
        currentPrice: Double = 0.0
    ) -> Position {
        var p = Position(
            ticker: ticker,
            position: position,
            feesPaid: 0,
            realizedPnl: 0,
            totalTraded: totalTraded,
            marketExposure: marketExposure
        )
        p.currentPrice = currentPrice
        return p
    }

    // MARK: - Cost basis

    func testEntryPriceFromMarketExposure() {
        // 100 contracts bought at 30¢ average → exposure 3000¢
        let p = makePosition(position: 100, marketExposure: 3000)
        XCTAssertEqual(p.entryPrice, 0.30, accuracy: 1e-9)
        XCTAssertEqual(p.totalCostBasis, 30.00, accuracy: 1e-9)
    }

    func testEntryPriceFallsBackToTotalTraded() {
        let p = makePosition(position: 50, marketExposure: nil, totalTraded: 1250)
        XCTAssertEqual(p.entryPrice, 0.25, accuracy: 1e-9)
    }

    func testEntryPriceForShortPositionUsesAbsoluteQuantity() {
        // No-side position (negative), 200 contracts at 40¢
        let p = makePosition(position: -200, marketExposure: 8000)
        XCTAssertEqual(p.entryPrice, 0.40, accuracy: 1e-9)
        XCTAssertEqual(p.quantity, 200)
        XCTAssertEqual(p.side, "No")
    }

    // MARK: - P&L and ROI (after 7% commission, rounded to nearest cent)

    func testRealizedPnLWithProfit() {
        // 100 contracts bought at 30¢, now worth 60¢
        // Gross: 100 * 0.60 = $60
        // Raw commission: 0.07 * 100 * 0.60 * 0.40 = 1.68 → rounds to $1.68
        // Net proceeds: 60 - 1.68 = 58.32
        // PnL: 58.32 - 30 = 28.32
        let p = makePosition(position: 100, marketExposure: 3000, currentPrice: 0.60)
        XCTAssertEqual(p.realizedPnL, 28.32, accuracy: 0.001)
        XCTAssertEqual(p.netProceedsAfterFees, 58.32, accuracy: 0.001)
        XCTAssertEqual(p.realizedROI, 28.32 / 30.00, accuracy: 1e-6)
    }

    func testRealizedPnLWithLoss() {
        // 100 contracts at 60¢, now worth 20¢
        // Gross: 100 * 0.20 = $20
        // Raw commission: 0.07 * 100 * 0.20 * 0.80 = 1.12 → $1.12
        // Net proceeds: 20 - 1.12 = 18.88
        // PnL: 18.88 - 60 = -41.12
        let p = makePosition(position: 100, marketExposure: 6000, currentPrice: 0.20)
        XCTAssertEqual(p.realizedPnL, -41.12, accuracy: 0.001)
        XCTAssertEqual(p.realizedROI, -41.12 / 60.00, accuracy: 1e-6)
    }

    func testCommissionRoundsToNearestCent() {
        // 33 contracts at 37¢ → raw 0.07*33*0.37*0.63 = 0.5384... → rounds to $0.54
        // Gross: 33 * 0.37 = 12.21
        // Net proceeds: 12.21 - 0.54 = 11.67
        let p = makePosition(position: 33, marketExposure: 660, currentPrice: 0.37)
        XCTAssertEqual(p.netProceedsAfterFees, 11.67, accuracy: 0.001)
    }

    func testZeroQuantityReturnsZeroStats() {
        let p = makePosition(position: 0, marketExposure: 0, currentPrice: 0.50)
        XCTAssertEqual(p.realizedPnL, 0.0)
        XCTAssertEqual(p.realizedROI, 0.0)
        XCTAssertEqual(p.netProceedsAfterFees, 0.0)
    }

    func testZeroCostBasisReturnsZeroStats() {
        let p = makePosition(position: 100, marketExposure: 0, currentPrice: 0.50)
        XCTAssertEqual(p.realizedPnL, 0.0)
    }

    // MARK: - executableSellPrice

    func testExecutableSellPriceYesUsesYesBid() {
        let p = makePosition(position: 100, marketExposure: 3000)
        let price = p.executableSellPrice(yesBid: 0.55, noBid: 0.43, yesAsk: 0.58, lastPrice: 0.56)
        XCTAssertEqual(price, 0.55)
    }

    func testExecutableSellPriceNoUsesNoBid() {
        let p = makePosition(position: -100, marketExposure: 4000)
        let price = p.executableSellPrice(yesBid: 0.55, noBid: 0.43, yesAsk: 0.58, lastPrice: 0.56)
        XCTAssertEqual(price, 0.43)
    }

    func testExecutableSellPriceNoFallsBackToOneMinusYesAsk() {
        // No noBid → derive from yesAsk: 1 - 0.58 = 0.42
        let p = makePosition(position: -100, marketExposure: 4000)
        let price = p.executableSellPrice(yesBid: 0.55, noBid: nil, yesAsk: 0.58, lastPrice: 0.56)
        XCTAssertEqual(price, 0.42, accuracy: 1e-9)
    }

    func testExecutableSellPriceReturnsNilWhenNoQuotes() {
        let p = makePosition(position: 100, marketExposure: 3000)
        let price = p.executableSellPrice(yesBid: nil, noBid: nil, yesAsk: nil, lastPrice: nil)
        XCTAssertNil(price)
    }

    // MARK: - detectArbitrage

    func testDetectArbitrageProfitableHedge() {
        // YES position of 100 contracts bought at 30¢ (cost $30).
        // NO is offered at 10¢. Buy 100 NO for $10 + commission.
        // Commission: 0.07 * 100 * 0.10 * 0.90 = 0.63 → $0.63
        // Total hedge cost: 10 + 0.63 = $10.63
        // Total invested: 30 + 10.63 = $40.63
        // Guaranteed payout (one side resolves to $1): 100 * 1 = $100
        // Net profit: $100 - $40.63 = $59.37
        var p = makePosition(position: 100, marketExposure: 3000)
        p.noAsk = 0.10

        let arb = p.detectArbitrage(minimumProfit: 1.0)
        XCTAssertNotNil(arb)
        XCTAssertEqual(arb?.guaranteedProfit ?? 0, 59.37, accuracy: 0.01)
        XCTAssertEqual(arb?.oppositeSidePrice ?? 0, 0.10)
        XCTAssertEqual(arb?.totalCostToHedge ?? 0, 10.63, accuracy: 0.01)
    }

    func testDetectArbitrageReturnsNilWhenBelowMinimum() {
        // YES bought at 99¢ — hedge cost dominates, no real edge.
        var p = makePosition(position: 100, marketExposure: 9900)
        p.noAsk = 0.99

        let arb = p.detectArbitrage(minimumProfit: 1.0)
        XCTAssertNil(arb)
    }

    func testDetectArbitrageReturnsNilWhenNoOppositeQuote() {
        let p = makePosition(position: 100, marketExposure: 3000)
        // no yesAsk, no noAsk
        XCTAssertNil(p.detectArbitrage())
    }

    func testDetectArbitrageForNoPositionUsesYesAsk() {
        // NO position of 100 at 40¢ (cost $40). YES offered at 30¢.
        // Hedge: 100 YES at 0.30 = $30, commission 0.07*100*0.30*0.70 = 1.47
        // Total hedge: 31.47; Total invested: 71.47; Payout: $100; Profit: $28.53
        var p = makePosition(position: -100, marketExposure: 4000)
        p.yesAsk = 0.30

        let arb = p.detectArbitrage(minimumProfit: 1.0)
        XCTAssertNotNil(arb)
        XCTAssertEqual(arb?.guaranteedProfit ?? 0, 28.53, accuracy: 0.01)
    }
}

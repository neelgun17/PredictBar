import XCTest
@testable import PredictBar

/// Exhaustive coverage of the money math — fees, net proceeds, P&L, ROI, and
/// arbitrage. Fees are the heart of the product: every figure the user sees
/// (cash-out value, P&L, ROI, arb profit) is downstream of `tradingFee`, and
/// Kalshi rounds fees UP to the next cent. These tests pin that behavior so a
/// regression in the rounding or formula fails loudly.
final class FeeCalculationTests: XCTestCase {

    private func position(
        contracts: Int,
        avgCents: Int,
        sellPrice: Double = 0.0
    ) -> Position {
        // marketExposure is the cost basis in cents and is always positive,
        // even for short (NO) positions: |contracts| * avg price.
        let exposureCents = abs(contracts) * avgCents
        var p = Position(
            ticker: "FEE-TEST",
            position: contracts,
            feesPaid: 0,
            realizedPnl: 0,
            totalTraded: exposureCents,
            marketExposure: exposureCents
        )
        p.currentPrice = sellPrice
        return p
    }

    // MARK: - tradingFee: formula = ceil(0.07 * C * P * (1 - P))

    func testFeeExactCentNotRoundedUp() {
        // 0.07 * 100 * 0.60 * 0.40 = 1.68 exactly. Must stay 1.68 despite the
        // intermediate Double computing as 1.6800000000000002.
        XCTAssertEqual(Position.tradingFee(contracts: 100, price: 0.60), 1.68, accuracy: 1e-9)
    }

    func testFeeExactCentAtLowPrice() {
        // 0.07 * 100 * 0.20 * 0.80 = 1.12 exactly.
        XCTAssertEqual(Position.tradingFee(contracts: 100, price: 0.20), 1.12, accuracy: 1e-9)
    }

    func testFeeRoundsUpWhenFractional() {
        // 0.07 * 10 * 0.45 * 0.55 = 0.17325 -> $0.18 (nearest would give 0.17).
        XCTAssertEqual(Position.tradingFee(contracts: 10, price: 0.45), 0.18, accuracy: 1e-9)
    }

    func testFeeRoundsUpJustAboveCent() {
        // 0.07 * 7 * 0.30 * 0.70 = 0.1029 -> 10.29¢ -> $0.11 (nearest -> 0.10).
        XCTAssertEqual(Position.tradingFee(contracts: 7, price: 0.30), 0.11, accuracy: 1e-9)
    }

    func testTinyNonZeroFeeRoundsUpToOneCent() {
        // 0.07 * 1 * 0.01 * 0.99 = 0.0006930 -> 0.0693¢, still rounds up to $0.01.
        XCTAssertEqual(Position.tradingFee(contracts: 1, price: 0.01), 0.01, accuracy: 1e-9)
    }

    func testFeeIsZeroAtPriceZero() {
        XCTAssertEqual(Position.tradingFee(contracts: 100, price: 0.0), 0.0, accuracy: 1e-9)
    }

    func testFeeIsZeroAtPriceOne() {
        XCTAssertEqual(Position.tradingFee(contracts: 100, price: 1.0), 0.0, accuracy: 1e-9)
    }

    func testFeeIsSymmetricAroundFiftyCents() {
        // P*(1-P) is symmetric, so the fee for P equals the fee for (1 - P).
        XCTAssertEqual(
            Position.tradingFee(contracts: 80, price: 0.30),
            Position.tradingFee(contracts: 80, price: 0.70),
            accuracy: 1e-9
        )
    }

    func testFeePeaksAtFiftyCents() {
        // P*(1-P) is maximized at 0.50, so the fee there is the largest.
        let atPeak = Position.tradingFee(contracts: 100, price: 0.50)
        XCTAssertGreaterThan(atPeak, Position.tradingFee(contracts: 100, price: 0.30))
        XCTAssertGreaterThan(atPeak, Position.tradingFee(contracts: 100, price: 0.70))
        XCTAssertEqual(atPeak, 1.75, accuracy: 1e-9) // 0.07 * 100 * 0.25 = 1.75
    }

    func testFeeScalesLinearlyWithContracts() {
        let single = Position.tradingFee(contracts: 100, price: 0.60)
        let double = Position.tradingFee(contracts: 200, price: 0.60)
        XCTAssertEqual(double, single * 2, accuracy: 1e-9)
    }

    func testFeeForFractionalContracts() {
        // 0.07 * 2.5 * 0.50 * 0.50 = 0.04375 -> $0.05.
        XCTAssertEqual(Position.tradingFee(contracts: 2.5, price: 0.50), 0.05, accuracy: 1e-9)
    }

    /// Strongest fee guarantee: across every integer price 1..99¢ and a range of
    /// contract counts, the production fee must equal the exact rational fee
    /// rounded UP to the next cent. The reference is computed in pure integer
    /// arithmetic — fee_cents = ceil(7 * C * p * (100 - p) / 10000) — so it can't
    /// drift with the same floating-point quirks the implementation guards
    /// against. This pins both the formula AND the round-up behavior at once.
    func testFeeMatchesIntegerCeilReferenceAcrossAllPrices() {
        for contracts in [1, 7, 10, 33, 100, 200, 1000] {
            for priceCents in 1...99 {
                let numerator = 7 * contracts * priceCents * (100 - priceCents)
                let expectedCents = (numerator + 9_999) / 10_000  // integer ceil
                let actualCents = Int(
                    (Position.tradingFee(contracts: Double(contracts),
                                         price: Double(priceCents) / 100.0) * 100).rounded()
                )
                XCTAssertEqual(
                    actualCents, expectedCents,
                    "fee mismatch for \(contracts) contracts @ \(priceCents)¢"
                )
            }
        }
    }

    // MARK: - Net proceeds, P&L, ROI (fee applied to the sell)

    func testProfitNetsTheFee() {
        // 100 @ 30¢ ($30 cost), sell @ 60¢. Gross 60, fee 1.68, net 58.32.
        let p = position(contracts: 100, avgCents: 30, sellPrice: 0.60)
        XCTAssertEqual(p.netProceedsAfterFees, 58.32, accuracy: 1e-6)
        XCTAssertEqual(p.realizedPnL, 28.32, accuracy: 1e-6)
        XCTAssertEqual(p.realizedROI, 28.32 / 30.0, accuracy: 1e-9)
    }

    func testLossNetsTheFee() {
        // 100 @ 60¢ ($60 cost), sell @ 20¢. Gross 20, fee 1.12, net 18.88.
        let p = position(contracts: 100, avgCents: 60, sellPrice: 0.20)
        XCTAssertEqual(p.netProceedsAfterFees, 18.88, accuracy: 1e-6)
        XCTAssertEqual(p.realizedPnL, -41.12, accuracy: 1e-6)
    }

    func testSellingAtEntryPriceLosesExactlyTheFee() {
        // 100 @ 50¢ ($50 cost), sell @ 50¢. Gross 50, fee 1.75, net 48.25.
        // The only loss is the commission.
        let p = position(contracts: 100, avgCents: 50, sellPrice: 0.50)
        XCTAssertEqual(p.netProceedsAfterFees, 48.25, accuracy: 1e-6)
        XCTAssertEqual(p.realizedPnL, -1.75, accuracy: 1e-6)
    }

    func testNearTotalLossStillNetsFee() {
        // 100 @ 50¢ ($50 cost), sell @ 1¢. Gross 1, fee ceil(0.0693)=0.07, net 0.93.
        let p = position(contracts: 100, avgCents: 50, sellPrice: 0.01)
        XCTAssertEqual(p.netProceedsAfterFees, 0.93, accuracy: 1e-6)
        XCTAssertEqual(p.realizedPnL, -49.07, accuracy: 1e-6)
    }

    func testNetProceedsFloorWhenFeeEqualsGross() {
        // 1 contract @ 50¢ ($0.50 cost), sell @ 1¢. Gross 0.01, fee
        // ceil(0.0693)=0.01 — the fee exactly consumes the gross, so net is $0.00
        // (never negative) and the whole cost basis is the loss.
        let p = position(contracts: 1, avgCents: 50, sellPrice: 0.01)
        XCTAssertEqual(p.netProceedsAfterFees, 0.0, accuracy: 1e-9)
        XCTAssertEqual(p.realizedPnL, -0.50, accuracy: 1e-9)
    }

    func testShortNoPositionLossROI() {
        // NO position: 100 @ 60¢ ($60 cost), sell @ 40¢. Gross 40, fee
        // ceil(0.07*100*0.40*0.60)=ceil(1.68)=1.68, net 38.32, pnl -21.68.
        let p = position(contracts: -100, avgCents: 60, sellPrice: 0.40)
        XCTAssertEqual(p.side, "No")
        XCTAssertEqual(p.realizedPnL, -21.68, accuracy: 1e-6)
        XCTAssertEqual(p.realizedROI, -21.68 / 60.0, accuracy: 1e-9)
    }

    func testTotalCostBasisFallsBackToEntryPriceWithoutExposure() {
        // No marketExposure → cost basis = contracts * entryPrice (from totalTraded).
        // 50 contracts, totalTraded 1250¢ → entry 0.25, basis $12.50.
        var p = Position(ticker: "FEE-TEST", position: 50, feesPaid: 0,
                         realizedPnl: 0, totalTraded: 1250, marketExposure: nil)
        p.currentPrice = 0.40
        XCTAssertEqual(p.entryPrice, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p.totalCostBasis, 12.50, accuracy: 1e-9)
    }

    func testNoPosQuantityReturnsZeroStats() {
        let p = position(contracts: 0, avgCents: 50, sellPrice: 0.50)
        XCTAssertEqual(p.realizedPnL, 0.0)
        XCTAssertEqual(p.netProceedsAfterFees, 0.0)
        XCTAssertEqual(p.realizedROI, 0.0)
    }

    func testZeroCostBasisReturnsZeroStats() {
        let p = position(contracts: 100, avgCents: 0, sellPrice: 0.50)
        XCTAssertEqual(p.realizedPnL, 0.0)
    }

    func testCashOutValueMatchesNetProceeds() {
        let p = position(contracts: 100, avgCents: 30, sellPrice: 0.60)
        XCTAssertEqual(p.cashOutValue, p.netProceedsAfterFees, accuracy: 1e-9)
    }

    func testShortNoPositionPnL() {
        // NO position: 100 @ 40¢ ($40 cost), sell @ 70¢. Gross 70, fee
        // ceil(0.07*100*0.70*0.30)=ceil(1.47)=1.47, net 68.53, pnl 28.53.
        let p = position(contracts: -100, avgCents: 40, sellPrice: 0.70)
        XCTAssertEqual(p.quantity, 100)
        XCTAssertEqual(p.side, "No")
        XCTAssertEqual(p.netProceedsAfterFees, 68.53, accuracy: 1e-6)
        XCTAssertEqual(p.realizedPnL, 28.53, accuracy: 1e-6)
    }

    // MARK: - Arbitrage profit (fee applied to the hedge buy)

    func testArbitrageProfitNetsHedgeFee() {
        // YES 100 @ 30¢ ($30). Buy 100 NO @ 10¢ = $10, fee ceil(0.63)=0.63.
        // Hedge 10.63; invested 40.63; payout 100; profit 59.37.
        var p = position(contracts: 100, avgCents: 30)
        p.noAsk = 0.10
        let arb = try? XCTUnwrap(p.detectArbitrage(minimumProfit: 1.0))
        XCTAssertEqual(arb?.guaranteedProfit ?? 0, 59.37, accuracy: 0.01)
        XCTAssertEqual(arb?.totalCostToHedge ?? 0, 10.63, accuracy: 0.01)
    }

    func testArbitrageBelowMinimumReturnsNil() {
        var p = position(contracts: 100, avgCents: 99)
        p.noAsk = 0.99
        XCTAssertNil(p.detectArbitrage(minimumProfit: 1.0))
    }

    func testArbitrageNoPositionDerivesYesAskFromNoBidParity() throws {
        // NO position 100 @ 40¢ ($40). Only noBid known → yesAsk = 1 - 0.85 = 0.15.
        // Buy 100 YES @ 0.15 = $15, fee ceil(0.07*100*0.15*0.85)=ceil(0.8925)=0.90.
        // Hedge 15.90; invested 55.90; payout 100; profit 44.10.
        var p = position(contracts: -100, avgCents: 40)
        p.noBid = 0.85   // yesAsk and noAsk intentionally nil — forces parity fallback
        let arb = try XCTUnwrap(p.detectArbitrage(minimumProfit: 1.0))
        XCTAssertEqual(arb.oppositeSidePrice, 0.15, accuracy: 1e-9)
        XCTAssertEqual(arb.guaranteedProfit, 44.10, accuracy: 0.01)
    }

    func testArbitrageMinimumProfitBoundaryIsInclusive() {
        // Profit is exactly $59.37. minimumProfit == profit must still fire (>=),
        // while a hair above it must not.
        var p = position(contracts: 100, avgCents: 30)
        p.noAsk = 0.10
        XCTAssertNotNil(p.detectArbitrage(minimumProfit: 59.37))
        XCTAssertNil(p.detectArbitrage(minimumProfit: 59.38))
    }

    func testArbitrageFlatPositionReturnsNil() {
        var p = position(contracts: 0, avgCents: 30)
        p.noAsk = 0.10
        XCTAssertNil(p.detectArbitrage(minimumProfit: 0.01))
    }
}

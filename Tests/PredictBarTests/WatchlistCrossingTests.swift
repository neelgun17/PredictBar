import XCTest
@testable import PredictBar

/// Watch alerts fire when the price reaches the target in the watched direction,
/// then disarm until the price moves 3¢ past the target the other way. These
/// tests pin the boundary and hysteresis behavior so a hovering price can't
/// flap notifications.
final class WatchlistCrossingTests: XCTestCase {

    // MARK: - At or below (buy-the-dip)

    func testBelowFiresAtExactTarget() {
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 25, armed: true)
        XCTAssertTrue(r.fire)
        XCTAssertFalse(r.armed)
    }

    func testBelowFiresUnderTarget() {
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 20, armed: true)
        XCTAssertTrue(r.fire)
        XCTAssertFalse(r.armed)
    }

    func testBelowDoesNotFireAboveTarget() {
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 26, armed: true)
        XCTAssertFalse(r.fire)
        XCTAssertTrue(r.armed)
    }

    func testBelowDoesNotRefireWhileDisarmed() {
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 24, armed: false)
        XCTAssertFalse(r.fire)
        XCTAssertFalse(r.armed)
    }

    func testBelowStaysDisarmedInsideBuffer() {
        // Price back above target but within the 3¢ re-arm buffer (25+3=28)
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 27, armed: false)
        XCTAssertFalse(r.fire)
        XCTAssertFalse(r.armed)
    }

    func testBelowRearmsAtBufferBoundary() {
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 28, armed: false)
        XCTAssertFalse(r.fire)
        XCTAssertTrue(r.armed)
    }

    // MARK: - At or above

    func testAboveFiresAtExactTarget() {
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrAbove, targetCents: 60, priceCents: 60, armed: true)
        XCTAssertTrue(r.fire)
        XCTAssertFalse(r.armed)
    }

    func testAboveDoesNotFireBelowTarget() {
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrAbove, targetCents: 60, priceCents: 59, armed: true)
        XCTAssertFalse(r.fire)
        XCTAssertTrue(r.armed)
    }

    func testAboveStaysDisarmedInsideBuffer() {
        // Price back below target but within the 3¢ re-arm buffer (60-3=57)
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrAbove, targetCents: 60, priceCents: 58, armed: false)
        XCTAssertFalse(r.fire)
        XCTAssertFalse(r.armed)
    }

    func testAboveRearmsAtBufferBoundary() {
        let r = WatchlistViewModel.evaluateCrossing(direction: .atOrAbove, targetCents: 60, priceCents: 57, armed: false)
        XCTAssertFalse(r.fire)
        XCTAssertTrue(r.armed)
    }

    // MARK: - Arming at add/edit time

    func testStartsDisarmedWhenTargetAlreadySatisfied() {
        // Adding "≤ 25" while the price is already 24 must not fire instantly
        XCTAssertFalse(WatchlistViewModel.initialArmed(direction: .atOrBelow, targetCents: 25, priceCents: 24))
        XCTAssertFalse(WatchlistViewModel.initialArmed(direction: .atOrAbove, targetCents: 60, priceCents: 61))
    }

    func testStartsArmedWhenTargetNotYetReached() {
        XCTAssertTrue(WatchlistViewModel.initialArmed(direction: .atOrBelow, targetCents: 25, priceCents: 26))
        XCTAssertTrue(WatchlistViewModel.initialArmed(direction: .atOrAbove, targetCents: 60, priceCents: 59))
    }

    // MARK: - Full cycle

    func testHitRearmRefireCycle() {
        // 30¢ → hits 25¢ target → fires and disarms
        var state = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 25, armed: true)
        XCTAssertTrue(state.fire)

        // bounces to 26¢ — inside buffer, stays disarmed
        state = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 26, armed: state.armed)
        XCTAssertFalse(state.fire)
        XCTAssertFalse(state.armed)

        // recovers to 30¢ — re-arms
        state = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 30, armed: state.armed)
        XCTAssertFalse(state.fire)
        XCTAssertTrue(state.armed)

        // drops to 25¢ again — fires again
        state = WatchlistViewModel.evaluateCrossing(direction: .atOrBelow, targetCents: 25, priceCents: 25, armed: state.armed)
        XCTAssertTrue(state.fire)
    }
}

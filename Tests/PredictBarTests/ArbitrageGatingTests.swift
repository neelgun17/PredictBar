import XCTest
@testable import PredictBar

/// The global "Enable Arbitrage Alerts" switch (and the master Notifications
/// switch) previously had no effect on detection — arbitrage fired purely on the
/// per-position flag. `shouldEvaluateArbitrage` is the single gate; every input
/// must be required (logical AND) and `status` must be "active".
final class ArbitrageGatingTests: XCTestCase {

    private func gate(
        notifications: Bool = true,
        globalArb: Bool = true,
        positionAlerts: Bool = true,
        positionArb: Bool = true,
        status: String? = "active"
    ) -> Bool {
        DashboardViewModel.shouldEvaluateArbitrage(
            notificationsEnabled: notifications,
            globalArbitrageEnabled: globalArb,
            positionAlertsEnabled: positionAlerts,
            positionArbitrageEnabled: positionArb,
            marketStatus: status
        )
    }

    func testAllEnabledAndActivePasses() {
        XCTAssertTrue(gate())
    }

    func testGlobalArbitrageOffBlocks() {
        // The bug being fixed: this used to evaluate anyway.
        XCTAssertFalse(gate(globalArb: false))
    }

    func testNotificationsOffBlocks() {
        XCTAssertFalse(gate(notifications: false))
    }

    func testPositionAlertsOffBlocks() {
        XCTAssertFalse(gate(positionAlerts: false))
    }

    func testPositionArbitrageOffBlocks() {
        XCTAssertFalse(gate(positionArb: false))
    }

    func testNonActiveStatusBlocks() {
        XCTAssertFalse(gate(status: "settled"))
        XCTAssertFalse(gate(status: "closed"))
        XCTAssertFalse(gate(status: nil))
    }
}

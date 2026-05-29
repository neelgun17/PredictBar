import XCTest
@testable import PredictBar

/// `/portfolio/balance` is the only money endpoint without schema-drift coverage,
/// and it still assumed integer cents while positions/markets/fills all migrated
/// to decimal-dollar strings. These tests pin a decoder that accepts BOTH shapes
/// so the menu-bar value and balance can't silently break if Kalshi flips it.
final class BalanceDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> NetworkManager.BalanceResponse {
        try NetworkManager.BalanceResponse.decode(from: Data(json.utf8))
    }

    func testDecodesLegacyIntegerCents() throws {
        let b = try decode(#"{ "balance": 12345, "portfolio_value": 6789 }"#)
        XCTAssertEqual(b.balance, 12345)
        XCTAssertEqual(b.portfolioValue, 6789)
    }

    func testDecodesNewDollarStrings() throws {
        let b = try decode(#"{ "balance_dollars": "123.45", "portfolio_value_dollars": "67.89" }"#)
        XCTAssertEqual(b.balance, 12345)      // "123.45" -> 12345 cents
        XCTAssertEqual(b.portfolioValue, 6789)
    }

    func testDecodesMixedSchema() throws {
        // Defensive: one field migrated, the other not.
        let b = try decode(#"{ "balance": 50000, "portfolio_value_dollars": "100.00" }"#)
        XCTAssertEqual(b.balance, 50000)
        XCTAssertEqual(b.portfolioValue, 10000)
    }

    func testSubCentDollarStringRoundsToNearestCent() throws {
        let b = try decode(#"{ "balance_dollars": "10.005", "portfolio_value_dollars": "0.004" }"#)
        XCTAssertEqual(b.balance, 1001)   // 10.005 -> 1000.5¢ -> 1001
        XCTAssertEqual(b.portfolioValue, 0) // 0.004 -> 0.4¢ -> 0
    }

    func testMissingFieldsDefaultToZero() throws {
        let b = try decode(#"{ }"#)
        XCTAssertEqual(b.balance, 0)
        XCTAssertEqual(b.portfolioValue, 0)
    }

    func testDollarStringUnderBareKeyStillDecodes() throws {
        // If Kalshi keeps the bare key name but sends a string value.
        let b = try decode(#"{ "balance": "42.00", "portfolio_value": "8.50" }"#)
        XCTAssertEqual(b.balance, 4200)
        XCTAssertEqual(b.portfolioValue, 850)
    }
}

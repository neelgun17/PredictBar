import XCTest
@testable import PredictBar

/// Candlestick history feeds the price series. The parser has a fallback ladder
/// (mid -> trade -> bid/ask avg -> bid -> ask -> *_dollars -> carry-forward) and
/// must return points in chronological order. (The bug that prompted extracting
/// this: `fetchMarketHistory` never invoked its inner runner, so this logic was
/// unreachable — now it's both wired up and pinned by tests.)
final class CandlestickParsingTests: XCTestCase {

    private func parse(_ json: String) throws -> [Double] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(NetworkManager.CandlestickResponse.self, from: Data(json.utf8))
        return NetworkManager.extractPrices(from: response)
    }

    private func assertPrices(_ actual: [Double], _ expected: [Double], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "price count mismatch", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: 1e-9, file: file, line: line)
        }
    }

    func testPrefersMidPriceClose() throws {
        let prices = try parse(#"""
        { "candlesticks": [ { "end_period_ts": 1, "mid_price": { "close": 42 }, "price": { "close": 99 } } ] }
        """#)
        assertPrices(prices, [0.42])   // mid_price wins over trade price
    }

    func testFallsBackToTradePrice() throws {
        let prices = try parse(#"""
        { "candlesticks": [ { "end_period_ts": 1, "price": { "close": 37 } } ] }
        """#)
        assertPrices(prices, [0.37])
    }

    func testFallsBackToBidAskAverage() throws {
        // No mid, no trade -> average of yes_bid/yes_ask closes: (40 + 44) / 200.
        let prices = try parse(#"""
        { "candlesticks": [ { "end_period_ts": 1, "yes_bid": { "close": 40 }, "yes_ask": { "close": 44 } } ] }
        """#)
        assertPrices(prices, [0.42])
    }

    func testFallsBackToDollarStringWhenNoIntegerClose() throws {
        let prices = try parse(#"""
        { "candlesticks": [ { "end_period_ts": 1, "yes_bid": { "close_dollars": "0.55" } } ] }
        """#)
        assertPrices(prices, [0.55])
    }

    func testSortsByEndPeriodTimestamp() throws {
        let prices = try parse(#"""
        { "candlesticks": [
            { "end_period_ts": 30, "price": { "close": 30 } },
            { "end_period_ts": 10, "price": { "close": 10 } },
            { "end_period_ts": 20, "price": { "close": 20 } }
        ] }
        """#)
        assertPrices(prices, [0.10, 0.20, 0.30])
    }

    func testCarriesForwardLastKnownPriceForEmptyCandle() throws {
        // Second candle has no usable field -> repeats the prior value.
        let prices = try parse(#"""
        { "candlesticks": [
            { "end_period_ts": 1, "price": { "close": 50 } },
            { "end_period_ts": 2 }
        ] }
        """#)
        assertPrices(prices, [0.50, 0.50])
    }

    func testEmptyResponseYieldsNoPrices() throws {
        XCTAssertTrue(try parse(#"{ "candlesticks": [] }"#).isEmpty)
    }
}

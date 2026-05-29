import XCTest
@testable import PredictBar

/// The live ticker stream drives real-time prices. Its decoder assumed integer
/// cents; if Kalshi migrates the socket to `*_dollars` strings the way it did the
/// REST API, prices would silently freeze. `parseTickerQuote` accepts both shapes
/// and these tests pin that.
final class WebSocketDecodingTests: XCTestCase {

    func testParsesLegacyIntegerCentsTicker() throws {
        let text = #"""
        { "type": "ticker", "msg": { "market_ticker": "KXTEST-A", "price": 41, "yes_bid": 40, "yes_ask": 43 } }
        """#
        let q = try XCTUnwrap(WebSocketManager.parseTickerQuote(from: text))
        XCTAssertEqual(q.ticker, "KXTEST-A")
        XCTAssertEqual(q.lastPrice, 41)
        XCTAssertEqual(q.yesBid, 40)
        XCTAssertEqual(q.yesAsk, 43)
    }

    func testParsesNewDollarStringTicker() throws {
        let text = #"""
        { "type": "ticker", "msg": { "market_ticker": "KXTEST-B", "price_dollars": "0.41", "yes_bid_dollars": "0.40", "yes_ask_dollars": "0.43" } }
        """#
        let q = try XCTUnwrap(WebSocketManager.parseTickerQuote(from: text))
        XCTAssertEqual(q.ticker, "KXTEST-B")
        XCTAssertEqual(q.lastPrice, 41)   // "0.41" -> 41 cents
        XCTAssertEqual(q.yesBid, 40)
        XCTAssertEqual(q.yesAsk, 43)
    }

    func testPartialQuoteKeepsMissingFieldsNil() throws {
        let text = #"{ "type": "ticker", "msg": { "market_ticker": "KXTEST-C", "yes_bid": 55 } }"#
        let q = try XCTUnwrap(WebSocketManager.parseTickerQuote(from: text))
        XCTAssertEqual(q.yesBid, 55)
        XCTAssertNil(q.lastPrice)
        XCTAssertNil(q.yesAsk)
    }

    func testNonTickerMessageReturnsNil() {
        let text = #"{ "type": "subscribed", "msg": { "channel": "ticker" } }"#
        XCTAssertNil(WebSocketManager.parseTickerQuote(from: text))
    }

    func testMissingMarketTickerReturnsNil() {
        let text = #"{ "type": "ticker", "msg": { "price": 41 } }"#
        XCTAssertNil(WebSocketManager.parseTickerQuote(from: text))
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(WebSocketManager.parseTickerQuote(from: "not json"))
    }
}

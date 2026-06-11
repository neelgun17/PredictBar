import XCTest
@testable import PredictBar

/// The watchlist add flow accepts either a pasted kalshi.com URL or a raw
/// ticker in one field. These tests pin the classification rules so the
/// resolution chain receives the right ticker kind.
final class WatchlistInputParserTests: XCTestCase {

    // MARK: - Raw tickers

    func testRawMarketTicker() {
        XCTAssertEqual(
            WatchlistInputParser.parse("KXBTC-EOY26-150K"),
            .marketOrEventTicker("KXBTC-EOY26-150K")
        )
    }

    func testTickerIsTrimmedAndUppercased() {
        XCTAssertEqual(
            WatchlistInputParser.parse("  kxfed-dec26-cut \n"),
            .marketOrEventTicker("KXFED-DEC26-CUT")
        )
    }

    func testTickerWithDotAndUnderscore() {
        XCTAssertEqual(
            WatchlistInputParser.parse("INXD-23DEC29-T4575.99"),
            .marketOrEventTicker("INXD-23DEC29-T4575.99")
        )
    }

    func testEmptyInputIsInvalid() {
        guard case .invalid = WatchlistInputParser.parse("   ") else {
            return XCTFail("Expected .invalid for empty input")
        }
    }

    func testGarbageInputIsInvalid() {
        guard case .invalid = WatchlistInputParser.parse("not a ticker!") else {
            return XCTFail("Expected .invalid for input with spaces/punctuation")
        }
    }

    // MARK: - URLs

    func testFullMarketURLYieldsEventTicker() {
        XCTAssertEqual(
            WatchlistInputParser.parse("https://kalshi.com/markets/kxfed/fed-decision/kxfed-26dec"),
            .url(seriesTicker: "KXFED", eventTicker: "KXFED-26DEC")
        )
    }

    func testSeriesAndSlugURLYieldsSeriesTicker() {
        XCTAssertEqual(
            WatchlistInputParser.parse("https://kalshi.com/markets/kxfed/fed-decision"),
            .url(seriesTicker: "KXFED", eventTicker: nil)
        )
    }

    func testSeriesOnlyURLYieldsSeriesTicker() {
        XCTAssertEqual(
            WatchlistInputParser.parse("https://kalshi.com/markets/kxfed"),
            .url(seriesTicker: "KXFED", eventTicker: nil)
        )
    }

    func testEventsPathYieldsEventTicker() {
        XCTAssertEqual(
            WatchlistInputParser.parse("https://kalshi.com/events/kxfed-26dec"),
            .url(seriesTicker: nil, eventTicker: "KXFED-26DEC")
        )
    }

    func testQueryParamTickerOverridesPath() {
        XCTAssertEqual(
            WatchlistInputParser.parse("https://kalshi.com/markets/kxfed/fed-decision?market=KXFED-26DEC-CUT"),
            .marketOrEventTicker("KXFED-26DEC-CUT")
        )
    }

    func testFragmentIsIgnored() {
        XCTAssertEqual(
            WatchlistInputParser.parse("https://kalshi.com/markets/kxfed/fed-decision/kxfed-26dec#order-book"),
            .url(seriesTicker: "KXFED", eventTicker: "KXFED-26DEC")
        )
    }

    func testSchemelessKalshiURLIsAccepted() {
        XCTAssertEqual(
            WatchlistInputParser.parse("kalshi.com/markets/kxfed/fed-decision/kxfed-26dec"),
            .url(seriesTicker: "KXFED", eventTicker: "KXFED-26DEC")
        )
    }

    func testSubdomainHostIsAccepted() {
        XCTAssertEqual(
            WatchlistInputParser.parse("https://www.kalshi.com/markets/kxfed"),
            .url(seriesTicker: "KXFED", eventTicker: nil)
        )
    }

    func testNonKalshiHostIsRejected() {
        guard case .invalid = WatchlistInputParser.parse("https://example.com/markets/kxfed") else {
            return XCTFail("Expected .invalid for non-kalshi host")
        }
    }

    func testKalshiURLWithoutMarketsPathIsRejected() {
        guard case .invalid = WatchlistInputParser.parse("https://kalshi.com/about") else {
            return XCTFail("Expected .invalid for URL without a markets path")
        }
    }
}

import XCTest
@testable import PredictBar

/// Guards against silent Kalshi API schema drift. Each fixture mirrors a real
/// response body captured from the live API (2026 decimal-string schema). If
/// Kalshi renames or retypes a field again, the matching test fails in CI
/// instead of the app shipping a broken decode.
final class SchemaDecodingTests: XCTestCase {

    // MARK: - Portfolio positions

    func testPositionDecodesDecimalSchema() throws {
        let json = """
        {
            "ticker": "KXNBAPLAYOFFWINS-26OKC-12",
            "position_fp": "50.00",
            "fees_paid_dollars": "0.10",
            "realized_pnl_dollars": "0.00",
            "total_traded_dollars": "11.00",
            "market_exposure_dollars": "11.00"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let p = try decoder.decode(Position.self, from: json)

        XCTAssertEqual(p.ticker, "KXNBAPLAYOFFWINS-26OKC-12")
        XCTAssertEqual(p.position, 50)              // position_fp "50.00" -> 50 contracts
        XCTAssertEqual(p.marketExposure, 1100)      // "11.00" dollars -> 1100 cents
        XCTAssertEqual(p.feesPaid, 10)              // "0.10" -> 10 cents
        XCTAssertEqual(p.entryPrice, 0.22, accuracy: 1e-9)
    }

    func testPositionDecodesNegativeAndFractionalDollars() throws {
        // Short (NO) position with a realized loss. Negative dollar strings must
        // decode to negative cents, and sub-cent values round to the nearest cent.
        let json = """
        {
            "ticker": "KXTEST-SHORT",
            "position_fp": "-100.00",
            "fees_paid_dollars": "0.125",
            "realized_pnl_dollars": "-12.34",
            "total_traded_dollars": "40.00",
            "market_exposure_dollars": "40.00"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let p = try decoder.decode(Position.self, from: json)

        XCTAssertEqual(p.position, -100)            // short position keeps its sign
        XCTAssertEqual(p.quantity, 100)
        XCTAssertEqual(p.side, "No")
        XCTAssertEqual(p.realizedPnl, -1234)        // "-12.34" -> -1234 cents
        XCTAssertEqual(p.feesPaid, 13)              // "0.125" -> 12.5¢ rounds to 13
        XCTAssertEqual(p.marketExposure, 4000)
        XCTAssertEqual(p.entryPrice, 0.40, accuracy: 1e-9)
    }

    // MARK: - Market

    func testMarketDecodesDecimalSchema() throws {
        let json = """
        {
            "market": {
                "ticker": "KXNBAMVP-26-JOKIC",
                "event_ticker": "KXNBAMVP-26",
                "title": "Will Nikola Jokic win 2026 NBA MVP?",
                "yes_sub_title": "Nikola Jokic",
                "last_price_dollars": "0.41",
                "yes_bid_dollars": "0.41",
                "no_bid_dollars": "0.58",
                "yes_ask_dollars": "0.43",
                "no_ask_dollars": "0.60",
                "status": "active",
                "series_ticker": "KXNBAMVP"
            }
        }
        """.data(using: .utf8)!

        let market = try JSONDecoder().decode(NetworkManager.MarketResponse.self, from: json).market

        XCTAssertEqual(market.ticker, "KXNBAMVP-26-JOKIC")
        XCTAssertEqual(market.subtitle, "Nikola Jokic")   // from yes_sub_title
        XCTAssertEqual(market.yesBid, 41)                 // "0.41" -> 41 cents
        XCTAssertEqual(market.noBid, 58)
        XCTAssertEqual(market.yesAsk, 43)
        XCTAssertEqual(market.lastPrice, 41)
        XCTAssertEqual(market.status, "active")
    }

    // MARK: - Fills

    func testFillsDecodeDecimalSchema() throws {
        // Real shape: count_fp, yes/no_price_dollars, fee_cost (all strings).
        let json = """
        {
            "cursor": "",
            "fills": [
                {
                    "action": "buy",
                    "side": "yes",
                    "count_fp": "1.00",
                    "created_time": "2026-05-27T20:42:21.407149Z",
                    "fee_cost": "0.020000",
                    "is_taker": true,
                    "market_ticker": "KXNBAPLAYOFFWINS-26OKC-12",
                    "no_price_dollars": "0.2200",
                    "trade_id": "1e33c461-c9c3-533e-b4ab-73c71491ecdf",
                    "yes_price_dollars": "0.7800"
                },
                {
                    "action": "buy",
                    "side": "no",
                    "count_fp": "3.00",
                    "created_time": "2026-05-24T04:22:28.587462Z",
                    "fee_cost": "0.020000",
                    "is_taker": true,
                    "market_ticker": "KXMLSGAME-26MAY23LAGHOU-LAG",
                    "no_price_dollars": "0.8200",
                    "trade_id": "684db309-194a-6910-5dae-0e780d805e84",
                    "yes_price_dollars": "0.1800"
                }
            ]
        }
        """.data(using: .utf8)!

        let fills = try JSONDecoder().decode(NetworkManager.FillsResponse.self, from: json).fills
        XCTAssertEqual(fills?.count, 2)

        let yesFill = try XCTUnwrap(fills?.first)
        XCTAssertEqual(yesFill.count, 1)
        XCTAssertEqual(yesFill.side, "yes")
        XCTAssertEqual(yesFill.price, 78)        // yes side -> yes_price_dollars "0.7800"
        XCTAssertEqual(yesFill.fee, 2)           // "0.020000" -> 2 cents

        let noFill = try XCTUnwrap(fills?.last)
        XCTAssertEqual(noFill.count, 3)
        XCTAssertEqual(noFill.side, "no")
        XCTAssertEqual(noFill.price, 82)         // no side -> no_price_dollars "0.8200"
    }

    func testFillRoundTripsThroughCacheEncoding() throws {
        let json = """
        {
            "action": "buy",
            "side": "no",
            "count_fp": "3.00",
            "fee_cost": "0.020000",
            "is_taker": true,
            "market_ticker": "KXMLSGAME-26MAY23LAGHOU-LAG",
            "no_price_dollars": "0.8200",
            "trade_id": "684db309-194a-6910-5dae-0e780d805e84",
            "yes_price_dollars": "0.1800"
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(Fill.self, from: json)
        let reencoded = try JSONEncoder().encode(original)
        let roundTripped = try JSONDecoder().decode(Fill.self, from: reencoded)

        XCTAssertEqual(roundTripped.tradeId, original.tradeId)
        XCTAssertEqual(roundTripped.count, original.count)
        XCTAssertEqual(roundTripped.price, original.price)
        XCTAssertEqual(roundTripped.fee, original.fee)
        XCTAssertEqual(roundTripped.side, original.side)
    }
}

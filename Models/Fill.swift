import Foundation

struct Fill: Codable, Identifiable {
    let tradeId: String
    let marketTicker: String
    let isTaker: Bool?
    let side: String // "yes" or "no"
    let count: Int
    let fee: Int?
    let sideFee: Int?
    let action: String // "buy" or "sell"
    let price: Int // in cents
    let createdTime: String? // ISO 8601
    
    var id: String { tradeId }
    
    var totalFeeVal: Int {
        return (fee ?? 0) + (sideFee ?? 0)
    }
    
    // Kalshi migrated fills to the same decimal-string schema as portfolio:
    // count -> count_fp, price (int cents) -> yes/no_price_dollars strings,
    // fee -> fee_cost string. We normalize back to cents/contracts here.
    enum CodingKeys: String, CodingKey {
        case tradeId = "trade_id"
        case marketTicker = "market_ticker"
        case isTaker = "is_taker"
        case side
        case countFp = "count_fp"
        case feeCost = "fee_cost"
        case action
        case yesPriceDollars = "yes_price_dollars"
        case noPriceDollars = "no_price_dollars"
        case createdTime = "created_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tradeId = try container.decode(String.self, forKey: .tradeId)
        marketTicker = try container.decode(String.self, forKey: .marketTicker)
        isTaker = try container.decodeIfPresent(Bool.self, forKey: .isTaker)
        side = try container.decode(String.self, forKey: .side)
        action = try container.decode(String.self, forKey: .action)
        createdTime = try container.decodeIfPresent(String.self, forKey: .createdTime)

        let countString = try container.decode(String.self, forKey: .countFp)
        count = Int((Double(countString) ?? 0).rounded())

        fee = Self.decodeDollarsToCents(container, key: .feeCost)
        sideFee = nil

        // Price paid per contract is the price of the side that was filled.
        let priceKey: CodingKeys = side.lowercased() == "no" ? .noPriceDollars : .yesPriceDollars
        price = Self.decodeDollarsToCents(container, key: priceKey) ?? 0
    }

    private static func decodeDollarsToCents(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        guard let s = try? c.decodeIfPresent(String.self, forKey: key), let d = Double(s) else { return nil }
        return Int((d * 100).rounded())
    }

    // Encode back into the API shape so cached fills round-trip through init(from:).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tradeId, forKey: .tradeId)
        try c.encode(marketTicker, forKey: .marketTicker)
        try c.encodeIfPresent(isTaker, forKey: .isTaker)
        try c.encode(side, forKey: .side)
        try c.encode(action, forKey: .action)
        try c.encodeIfPresent(createdTime, forKey: .createdTime)
        try c.encode(String(count), forKey: .countFp)
        if let fee = fee {
            try c.encode(String(format: "%.6f", Double(fee) / 100.0), forKey: .feeCost)
        }
        let priceKey: CodingKeys = side.lowercased() == "no" ? .noPriceDollars : .yesPriceDollars
        try c.encode(String(format: "%.4f", Double(price) / 100.0), forKey: priceKey)
    }
    
    // Default init for mocks
    init(tradeId: String, marketTicker: String, isTaker: Bool?, side: String, count: Int, fee: Int? = nil, sideFee: Int? = nil, action: String, price: Int, createdTime: String?) {
        self.tradeId = tradeId
        self.marketTicker = marketTicker
        self.isTaker = isTaker
        self.side = side
        self.count = count
        self.fee = fee
        self.sideFee = sideFee
        self.action = action
        self.price = price
        self.createdTime = createdTime
    }
    
    var date: Date? {
        guard let createdTime = createdTime else { return nil }
        
        // Try fractional seconds first
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdTime) {
            return date
        }
        
        // Try standard ISO8601
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: createdTime) {
            return date
        }
        
        // Fallback for simple Z
        let simpleFormatter = DateFormatter()
        simpleFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        simpleFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return simpleFormatter.date(from: createdTime)
    }
}

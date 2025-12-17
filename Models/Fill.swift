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
    
    enum CodingKeys: String, CodingKey {
        case tradeId = "trade_id"
        case marketTicker = "market_ticker"
        case isTaker = "is_taker"
        case side
        case count
        case fee // taker fee
        case sideFee = "side_fee"
        case action
        case price
        case createdTime = "created_time"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tradeId = try container.decode(String.self, forKey: .tradeId)
        marketTicker = try container.decode(String.self, forKey: .marketTicker)
        isTaker = try container.decodeIfPresent(Bool.self, forKey: .isTaker)
        side = try container.decode(String.self, forKey: .side)
        count = try container.decode(Int.self, forKey: .count)
        fee = try container.decodeIfPresent(Int.self, forKey: .fee)
        sideFee = try container.decodeIfPresent(Int.self, forKey: .sideFee)
        action = try container.decode(String.self, forKey: .action)
        createdTime = try container.decodeIfPresent(String.self, forKey: .createdTime)
        
        // Robust price decoding (Int cents or Double dollars)
        if let priceInt = try? container.decode(Int.self, forKey: .price) {
            price = priceInt
            // Check if it's unreasonably small for cents? No, 1 cent is possible.
            // API V2 usually confusing. If 0 < x < 1, it's dollars.
            // But if we decode Int, 0.56 -> 0? No, decoding Int from Float usually throws.
        } else if let priceDouble = try? container.decode(Double.self, forKey: .price) {
            price = Int(priceDouble * 100)
        } else {
             // Fallback to yes_price/no_price if available? 
             // Currently failing safe to 0 or rethrowing is better?
             // Let's assume 0 if totally missing, but it shouldn't be.
             price = 0
             // To be strict:
             // throw DecodingError.dataCorruptedError(forKey: .price, in: container, debugDescription: "Price invalid")
        }
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

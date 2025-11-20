import Foundation

enum WebSocketMessageType: String, Codable {
    case ticker
    case trade
    case fill
}

struct WebSocketMessage: Decodable {
    let type: WebSocketMessageType
    let channel: String?
    let msg: TickerMessage?
    
    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case msg
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        type = WebSocketMessageType(rawValue: typeString) ?? .ticker
        channel = try? container.decode(String.self, forKey: .channel)
        
        if type == .ticker {
            msg = try? container.decode(TickerMessage.self, forKey: .msg)
        } else {
            msg = nil
        }
    }
}

struct TickerMessage: Decodable {
    let market_ticker: String
    let price: Int // In cents
    let volume: Int
}

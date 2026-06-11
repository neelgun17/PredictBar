import Foundation
import Security
import Combine

class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()
    private var webSocketTask: URLSessionWebSocketTask?
    // Updated URL to the correct endpoint per documentation
    private let url = URL(string: "wss://api.elections.kalshi.com/trade-api/ws/v2")!
    
    @Published var isConnected = false
    
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    
    private init() {}
    
    func connect() {
        // Cancel any existing connection or timers
        disconnect()
        
        guard let request = createAuthenticatedRequest() else {
            return
        }
        
        webSocketTask = PinnedURLSession.shared.webSocketSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        isConnected = true
        
        receiveMessage()
        startPing()
        
        // Auto-subscribe after connection (if we have tickers)
        if !subscribedTickers.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.sendSubscription(for: self?.subscribedTickers ?? [])
            }
        }
    }
    
    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if error != nil {
                    self?.handleDisconnection()
                }
            }
        }
    }
    
    private func handleDisconnection() {
        guard isConnected else { return }
        isConnected = false
        pingTimer?.invalidate()
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
    
    private func createAuthenticatedRequest() -> URLRequest? {
        var request = URLRequest(url: url)
        
        // Retrieve credentials securely
        guard let credentials = try? CredentialsManager.shared.getCredentials() else {
            Log.websocket.error("Connection failed: missing API credentials.")
            return nil
        }
        
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        let path = "/trade-api/ws/v2"
        
        let messageToSign = timestamp + method + path
        
        guard let signature = CryptoUtils.sign(message: messageToSign, key: credentials.signingKey) else {
            return nil
        }
        
        request.addValue(credentials.apiKey, forHTTPHeaderField: "KALSHI-ACCESS-KEY")
        request.addValue(timestamp, forHTTPHeaderField: "KALSHI-ACCESS-TIMESTAMP")
        request.addValue(signature, forHTTPHeaderField: "KALSHI-ACCESS-SIGNATURE")
        
        return request
    }
    
    struct TickerQuote {
        let ticker: String
        let lastPrice: Int?
        let yesBid: Int?
        let yesAsk: Int?
    }
    
    // Publisher for price updates with executable context
    let priceUpdate = PassthroughSubject<TickerQuote, Never>()
    
    // Store subscribed tickers to re-subscribe on reconnection.
    // Two sources feed the subscription: portfolio positions and the watchlist.
    // Each updates its own set; the socket always subscribes to the union.
    private var subscribedTickers: [String] = []
    private var positionTickers: Set<String> = []
    private var watchlistTickers: Set<String> = []

    /// Replaces the position-driven half of the subscription (called on portfolio refresh).
    func setPositionTickers(_ tickers: [String]) {
        let newSet = Set(tickers)
        guard newSet != positionTickers else { return }
        positionTickers = newSet
        resubscribe()
    }

    /// Replaces the watchlist-driven half of the subscription (called on add/remove/prune).
    func setWatchlistTickers(_ tickers: [String]) {
        let newSet = Set(tickers)
        guard newSet != watchlistTickers else { return }
        watchlistTickers = newSet
        resubscribe()
    }

    private func resubscribe() {
        let union = positionTickers.union(watchlistTickers).sorted()
        guard !union.isEmpty else { return }
        subscribedTickers = union
        sendSubscription(for: union)
    }

    func subscribeToTickers(_ tickers: [String]) {
        setPositionTickers(tickers)
    }

    private func sendSubscription(for tickers: [String]) {
        guard !tickers.isEmpty else { return }

        // Construct the subscription message
        // Kalshi API expects "market_tickers" in params to filter
        let params: [String: Any] = [
            "channels": ["ticker"],
            "market_tickers": tickers
        ]
        
        let messageDict: [String: Any] = [
            "id": 1,
            "cmd": "subscribe",
            "params": params
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: messageDict),
              let messageString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        let messageOperation = URLSessionWebSocketTask.Message.string(messageString)
        webSocketTask?.send(messageOperation) { _ in }
    }
    
    func disconnect() {
        pingTimer?.invalidate()
        reconnectTimer?.invalidate()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure:
                self?.handleDisconnection()
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data:
                    break
                @unknown default:
                    break
                }
                // Continue receiving messages
                self?.receiveMessage()
            }
        }
    }
    
    // Structures for decoding WebSocket messages
    private struct WebSocketMessage: Decodable {
        let type: String?
        let msg: TickerData?
    }

    // Accepts both the legacy integer-cents shape (price/yes_bid/yes_ask) and the
    // 2026 decimal-dollar-string shape (price_dollars/yes_bid_dollars/yes_ask_dollars),
    // normalizing everything to Int cents — the representation the app expects.
    private struct TickerData: Decodable {
        let marketTicker: String?
        let priceCents: Int?
        let yesBidCents: Int?
        let yesAskCents: Int?

        enum CodingKeys: String, CodingKey {
            case marketTicker = "market_ticker"
            case price
            case priceDollars = "price_dollars"
            case yesBid = "yes_bid"
            case yesBidDollars = "yes_bid_dollars"
            case yesAsk = "yes_ask"
            case yesAskDollars = "yes_ask_dollars"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            marketTicker = try c.decodeIfPresent(String.self, forKey: .marketTicker)
            priceCents = Self.cents(c, centsKey: .price, dollarsKey: .priceDollars)
            yesBidCents = Self.cents(c, centsKey: .yesBid, dollarsKey: .yesBidDollars)
            yesAskCents = Self.cents(c, centsKey: .yesAsk, dollarsKey: .yesAskDollars)
        }

        private static func cents(_ c: KeyedDecodingContainer<CodingKeys>, centsKey: CodingKeys, dollarsKey: CodingKeys) -> Int? {
            if let v = (try? c.decodeIfPresent(Int.self, forKey: centsKey)) ?? nil { return v }
            if let s = (try? c.decodeIfPresent(String.self, forKey: dollarsKey)) ?? nil, let d = Double(s) {
                return Int((d * 100).rounded())
            }
            if let s = (try? c.decodeIfPresent(String.self, forKey: centsKey)) ?? nil, let d = Double(s) {
                return Int((d * 100).rounded())
            }
            return nil
        }
    }

    /// Parses a raw ticker-channel message into a `TickerQuote` (cents), or nil if
    /// the message is not a usable ticker update. Pure and side-effect free so the
    /// decode path is unit-testable.
    static func parseTickerQuote(from text: String) -> TickerQuote? {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(WebSocketMessage.self, from: data),
              message.type == "ticker",
              let tickerData = message.msg,
              let ticker = tickerData.marketTicker else {
            return nil
        }
        return TickerQuote(
            ticker: ticker,
            lastPrice: tickerData.priceCents,
            yesBid: tickerData.yesBidCents,
            yesAsk: tickerData.yesAskCents
        )
    }

    private func handleMessage(_ text: String) {
        guard let quote = Self.parseTickerQuote(from: text) else { return }
        DispatchQueue.main.async {
            self.priceUpdate.send(quote)
        }
    }
}

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
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        isConnected = true
        
        receiveMessage()
        startPing()
        
        // Auto-subscribe after connection (if we have tickers)
        // Note: Ideally we'd store the tickers and re-subscribe here
        if !subscribedTickers.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.subscribeToTickers(self?.subscribedTickers ?? [])
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
        guard let credentials = try? CredentialsManager.shared.get() else {
            print("❌ WebSocket connection failed: Missing API credentials.")
            return nil
        }
        
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        let path = "/trade-api/ws/v2"
        
        let messageToSign = timestamp + method + path
        
        guard let signature = CryptoUtils.sign(message: messageToSign, privateKeyPEM: credentials.privateKey) else {
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
    
    // Store subscribed tickers to re-subscribe on reconnection
    private var subscribedTickers: [String] = []
    
    func subscribeToTickers(_ tickers: [String]) {
        guard !tickers.isEmpty else { return }
        self.subscribedTickers = tickers
        
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
    
    private struct TickerData: Decodable {
        let market_ticker: String?
        let price: Int?
        let yes_bid: Int?
        let yes_ask: Int?
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
            
            if message.type == "ticker", let tickerData = message.msg, let ticker = tickerData.market_ticker {
                // print(text) // raw ticker data payload
                let quote = TickerQuote(
                    ticker: ticker,
                    lastPrice: tickerData.price,
                    yesBid: tickerData.yes_bid,
                    yesAsk: tickerData.yes_ask
                )
                
                DispatchQueue.main.async {
                    self.priceUpdate.send(quote)
                }
            }
        } catch {
            return
        }
    }
}

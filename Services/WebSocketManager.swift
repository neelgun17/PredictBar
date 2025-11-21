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
            print("Failed to create authenticated request. Check Secrets.swift.")
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        isConnected = true
        print("WebSocket connecting...")
        
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
                if let error = error {
                    print("Ping failed: \(error)")
                    self?.handleDisconnection()
                }
            }
        }
    }
    
    private func handleDisconnection() {
        guard isConnected else { return }
        print("WebSocket disconnected. Reconnecting in 5s...")
        isConnected = false
        pingTimer?.invalidate()
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
    
    private func createAuthenticatedRequest() -> URLRequest? {
        var request = URLRequest(url: url)
        
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        let path = "/trade-api/ws/v2"
        
        let messageToSign = timestamp + method + path
        
        guard let signature = sign(message: messageToSign, privateKeyPEM: Secrets.privateKey) else {
            print("Failed to generate signature")
            return nil
        }
        
        request.addValue(Secrets.keyId, forHTTPHeaderField: "KALSHI-ACCESS-KEY")
        request.addValue(timestamp, forHTTPHeaderField: "KALSHI-ACCESS-TIMESTAMP")
        request.addValue(signature, forHTTPHeaderField: "KALSHI-ACCESS-SIGNATURE")
        
        return request
    }
    
    private func sign(message: String, privateKeyPEM: String) -> String? {
        guard let data = message.data(using: .utf8) else { return nil }
        
        // 1. Clean PEM string
        let cleanPEM = privateKeyPEM
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let keyData = Data(base64Encoded: cleanPEM) else {
            print("Invalid private key format")
            return nil
        }
        
        // 2. Create SecKey
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            print("Failed to create SecKey: \(error!.takeRetainedValue())")
            return nil
        }
        
        // 3. Sign with RSA-PSS-SHA256
        let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePSSSHA256
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            print("Algorithm not supported")
            return nil
        }
        
        guard let signatureData = SecKeyCreateSignature(privateKey, algorithm, data as CFData, &error) else {
            print("Failed to sign data: \(error!.takeRetainedValue())")
            return nil
        }
        
        return (signatureData as Data).base64EncodedString()
    }
    
    // Publisher for price updates (Ticker, Price in Cents)
    let priceUpdate = PassthroughSubject<(String, Int), Never>()
    
    // Store subscribed tickers to re-subscribe on reconnection
    private var subscribedTickers: [String] = []
    
    func subscribeToTickers(_ tickers: [String]) {
        print("WebSocketManager: subscribeToTickers called with \(tickers)")
        guard !tickers.isEmpty else { return }
        self.subscribedTickers = tickers
        
        // Construct the subscription message
        // Note: Kalshi API expects "market_tickers" in params to filter
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
            print("Failed to create subscription message")
            return
        }
        
        let messageOperation = URLSessionWebSocketTask.Message.string(messageString)
        webSocketTask?.send(messageOperation) { error in
            if let error = error {
                print("WebSocket sending error: \(error)")
            } else {
                print("Subscribed to tickers: \(tickers)")
            }
        }
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
            case .failure(let error):
                print("WebSocket error: \(error)")
                self?.handleDisconnection()
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    print("Received data: \(data)")
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
                // Prioritize last traded price, then yes_bid
                let currentPrice = tickerData.price ?? tickerData.yes_bid ?? 0
                
                DispatchQueue.main.async {
                    self.priceUpdate.send((ticker, currentPrice))
                }
            }
        } catch {
            print("WebSocket decoding error: \(error)")
        }
    }
}

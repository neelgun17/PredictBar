import Foundation
import Security

class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()
    private var webSocketTask: URLSessionWebSocketTask?
    // Updated URL to the correct endpoint
    private let url = URL(string: "wss://api.elections.kalshi.com/trade-api/ws/v2")!
    
    @Published var isConnected = false
    
    private init() {}
    
    func connect() {
        guard let request = createAuthenticatedRequest() else {
            print("Failed to create authenticated request. Check Secrets.swift.")
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Note: isConnected should ideally be set upon successful connection open, 
        // but URLSessionWebSocketTask doesn't have a direct delegate for that.
        // We assume connected if no error immediately.
        isConnected = true
        receiveMessage()
        
        // Auto-subscribe after connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.subscribeToTickers()
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
    
    func subscribeToTickers() {
        // Example subscription message
        let message = """
        {
            "id": 1,
            "cmd": "subscribe",
            "params": {
                "channels": ["ticker"]
            }
        }
        """
        let messageOperation = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(messageOperation) { error in
            if let error = error {
                print("WebSocket sending error: \(error)")
            }
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket error: \(error)")
                self?.isConnected = false
                // Implement reconnection logic here
            case .success(let message):
                switch message {
                case .string(let text):
                    // print("Received string: \(text)")
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
    
    private func handleMessage(_ text: String) {
        // Parse JSON and notify observers
        // For now, just printing
        guard let data = text.data(using: .utf8) else { return }
        // Decode logic would go here
    }
}

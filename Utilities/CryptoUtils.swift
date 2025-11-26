import Foundation
import Security

struct CryptoUtils {
    static func sign(message: String, privateKeyPEM: String) -> String? {
        guard let data = message.data(using: .utf8) else { return nil }
        
        // 1. Clean PEM string
        // Robust cleaning: Remove headers/footers and any non-base64 characters
        let cleanPEM = privateKeyPEM
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("-----") }
            .joined()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let keyData = Data(base64Encoded: cleanPEM) else {
            print("❌ Failed to decode Private Key PEM. Please check format.")
            print("📝 Input length: \(privateKeyPEM.count), Cleaned length: \(cleanPEM.count)")
            // Debug: print first/last few chars to help debug (don't print whole key)
            if cleanPEM.count > 10 {
                print("📝 Cleaned start: \(cleanPEM.prefix(5))... end: ...\(cleanPEM.suffix(5))")
            }
            return nil
        }
        
        // 2. Create SecKey
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            print("❌ Failed to create SecKey from data: \(error?.takeRetainedValue().localizedDescription ?? "Unknown error")")
            return nil
        }
        
        // 3. Sign with RSA-PSS-SHA256
        let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePSSSHA256
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            print("❌ Private Key does not support RSA-PSS-SHA256 algorithm.")
            return nil
        }
        
        guard let signatureData = SecKeyCreateSignature(privateKey, algorithm, data as CFData, &error) else {
            print("❌ Failed to create signature: \(error?.takeRetainedValue().localizedDescription ?? "Unknown error")")
            return nil
        }
        
        return (signatureData as Data).base64EncodedString()
    }
}

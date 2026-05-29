import Foundation
import Security

struct CryptoUtils {
    /// Minimum acceptable RSA key size. Anything smaller is rejected at import.
    static let minimumKeyBits = 2048

    /// Imports a PEM-encoded RSA private key into an opaque `SecKey`.
    /// The Security framework manages the key material in wired memory once imported,
    /// so the PEM `String` can be discarded immediately by the caller.
    static func importPrivateKey(pem: String) -> SecKey? {
        // Strip header/footer lines, then any whitespace
        let cleanPEM = pem
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("-----") }
            .joined()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyData = Data(base64Encoded: cleanPEM) else {
            Log.crypto.error("Failed to decode private key PEM; check format.")
            return nil
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            Log.crypto.error("Failed to import private key: \(error?.takeRetainedValue().localizedDescription ?? "unknown error", privacy: .public)")
            return nil
        }

        // Reject keys below the minimum size
        if let attrs = SecKeyCopyAttributes(key) as? [String: Any],
           let bits = attrs[kSecAttrKeySizeInBits as String] as? Int {
            guard bits >= minimumKeyBits else {
                Log.crypto.error("RSA key is \(bits) bits; minimum required is \(minimumKeyBits).")
                return nil
            }
        }

        guard SecKeyIsAlgorithmSupported(key, .sign, .rsaSignatureMessagePSSSHA256) else {
            Log.crypto.error("Private key does not support RSA-PSS-SHA256 algorithm.")
            return nil
        }

        return key
    }

    /// Signs a message with the given `SecKey` using RSA-PSS-SHA256.
    static func sign(message: String, key: SecKey) -> String? {
        guard let data = message.data(using: .utf8) else { return nil }

        var error: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePSSSHA256,
            data as CFData,
            &error
        ) else {
            Log.crypto.error("Failed to create signature: \(error?.takeRetainedValue().localizedDescription ?? "unknown error", privacy: .public)")
            return nil
        }

        return (signatureData as Data).base64EncodedString()
    }
}

import Foundation
import Security

/// Manages secure storage and retrieval of API credentials using the macOS Keychain.
///
/// The private key is never cached as a Swift `String`. Instead, the imported
/// `SecKey` is held in memory; the raw PEM material lives only in the Keychain
/// (encrypted at rest) and on the heap briefly during `save()` and the first
/// `signingKey()` call.
class CredentialsManager {
    static let shared = CredentialsManager()

    private let service = "com.predictbar.app"
    private let accessKeyAccount = "kalshi-access-key"
    private let secretKeyAccount = "kalshi-access-secret"

    // In-memory cache. We hold ONLY the opaque SecKey (Security-framework-managed
    // wired memory). The PEM private key and the API key UUID are both read from
    // the Keychain on demand and dropped — neither is held as a long-lived String.
    private var cachedSigningKey: SecKey?

    private init() {}

    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case unexpectedData
        case invalidPrivateKey
        case unhandledError(status: OSStatus)

        var localizedDescription: String {
            switch self {
            case .itemNotFound: return "Credentials not found in Keychain."
            case .duplicateItem: return "Credentials already exist."
            case .unexpectedData: return "Found unexpected data in Keychain."
            case .invalidPrivateKey: return "Private key could not be imported. Verify it is a valid RSA key (>= 2048 bits) in PEM format."
            case .unhandledError(let status): return "Keychain error: \(status)"
            }
        }
    }

    // MARK: - Public API

    /// Saves the API Key and Private Key (PEM) to the Keychain. Overwrites if present.
    /// The PEM string is imported into a `SecKey` and the raw string is then dropped.
    func save(apiKey: String, privateKey: String) throws {
        // Validate the key imports cleanly before persisting anything.
        guard let signingKey = CryptoUtils.importPrivateKey(pem: privateKey) else {
            throw KeychainError.invalidPrivateKey
        }

        try saveItem(account: accessKeyAccount, value: apiKey)
        try saveItem(account: secretKeyAccount, value: privateKey)

        cachedSigningKey = signingKey
        print("✅ Credentials saved securely to Keychain.")
    }

    /// Returns the API Key (UUID identifier). Read fresh from the Keychain each call —
    /// we intentionally do not cache it as a Swift `String` so it cannot be recovered
    /// from a heap dump beyond the lifetime of a single request.
    func getApiKey() throws -> String? {
        return try getItem(account: accessKeyAccount)
    }

    /// Returns the signing key as an opaque `SecKey`. The PEM string is read from
    /// the Keychain at most once per process and discarded immediately after import.
    func getSigningKey() throws -> SecKey? {
        if let cached = cachedSigningKey { return cached }
        guard let pem = try getItem(account: secretKeyAccount) else { return nil }
        guard let key = CryptoUtils.importPrivateKey(pem: pem) else {
            throw KeychainError.invalidPrivateKey
        }
        cachedSigningKey = key
        return key
    }

    /// Convenience: returns both the API key and signing key if both are available.
    func getCredentials() throws -> (apiKey: String, signingKey: SecKey)? {
        guard let apiKey = try getApiKey(),
              let signingKey = try getSigningKey() else {
            return nil
        }
        return (apiKey, signingKey)
    }

    /// Deletes the API Key and Private Key from the Keychain.
    func delete() throws {
        try deleteItem(account: accessKeyAccount)
        try deleteItem(account: secretKeyAccount)
        cachedSigningKey = nil
        print("🗑️ Credentials removed from Keychain.")
    }

    /// Checks if credentials exist in the Keychain without retrieving the secrets.
    func hasCredentials() -> Bool {
        return (try? exists(account: accessKeyAccount)) == true &&
               (try? exists(account: secretKeyAccount)) == true
    }

    // MARK: - Private Helpers

    private func saveItem(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        if try exists(account: account) {
            // Update existing item
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.unhandledError(status: status)
            }
        } else {
            // Add new item — pin to this device, no iCloud sync, only readable while unlocked
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecAttrSynchronizable as String: false,
                kSecValueData as String: data
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unhandledError(status: status)
            }
        }
    }

    private func getItem(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
        guard let data = item as? Data, let result = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return result
    }

    private func deleteItem(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    private func exists(account: String) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw KeychainError.unhandledError(status: status)
    }
}

import Foundation
import Security

/// Manages secure storage and retrieval of Kalshi API credentials using the macOS Keychain.
/// Ensures secrets are never stored in plaintext on disk or logged.
class CredentialsManager {
    static let shared = CredentialsManager()
    
    private let service = "com.kalshimenubar"
    private let accessKeyAccount = "kalshi-access-key"
    private let secretKeyAccount = "kalshi-access-secret"
    
    // In-memory cache to prevent excessive Keychain prompts
    private var cachedCredentials: (apiKey: String, privateKey: String)?
    
    private init() {}
    
    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case unexpectedData
        case unhandledError(status: OSStatus)
        
        var localizedDescription: String {
            switch self {
            case .itemNotFound: return "Credentials not found in Keychain."
            case .duplicateItem: return "Credentials already exist."
            case .unexpectedData: return "Found unexpected data in Keychain."
            case .unhandledError(let status): return "Keychain error: \(status)"
            }
        }
    }
    
    // MARK: - Public API
    
    /// Saves the API Key and Private Key (Secret) to the Keychain.
    /// Overwrites existing credentials if present.
    func save(apiKey: String, privateKey: String) throws {
        try saveItem(account: accessKeyAccount, value: apiKey)
        try saveItem(account: secretKeyAccount, value: privateKey)
        
        // Update cache
        cachedCredentials = (apiKey, privateKey)
        print("✅ Kalshi credentials saved securely to Keychain.")
    }
    
    /// Retrieves the API Key and Private Key from the Keychain.
    /// Returns nil if either is missing.
    func get() throws -> (apiKey: String, privateKey: String)? {
        // Return cached if available
        if let cached = cachedCredentials {
            return cached
        }
        
        guard let apiKey = try getItem(account: accessKeyAccount),
              let privateKey = try getItem(account: secretKeyAccount) else {
            return nil
        }
        
        // Populate cache
        cachedCredentials = (apiKey, privateKey)
        return (apiKey, privateKey)
    }
    
    /// Deletes the API Key and Private Key from the Keychain.
    func delete() throws {
        try deleteItem(account: accessKeyAccount)
        try deleteItem(account: secretKeyAccount)
        
        // Clear cache
        cachedCredentials = nil
        print("🗑️ Kalshi credentials removed from Keychain.")
    }
    
    /// Checks if credentials exist in the Keychain without retrieving the secrets.
    func hasCredentials() -> Bool {
        if cachedCredentials != nil {
            return true
        }
        return (try? exists(account: accessKeyAccount)) == true &&
               (try? exists(account: secretKeyAccount)) == true
    }
    
    // MARK: - Private Helpers
    
    private func saveItem(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        
        // Check if item exists
        if try exists(account: account) {
            // Update
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
            // Add
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
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
        
        if status == errSecItemNotFound {
            return nil
        }
        
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
            kSecReturnAttributes as String: true // We only need attributes to confirm existence
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess {
            return true
        } else if status == errSecItemNotFound {
            return false
        } else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}

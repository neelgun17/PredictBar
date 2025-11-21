import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    static let shared = SettingsViewModel()
    
    // MARK: - AppStorage Properties
    // We use AppStorage-like behavior but wrapped in Published properties to trigger updates
    // or we can just use UserDefaults directly and expose Published properties that sync.
    // For simplicity in a ViewModel, we'll use UserDefaults and Published properties.
    
    @Published var menuBarMetric: String {
        didSet { UserDefaults.standard.set(menuBarMetric, forKey: "menuBarMetric") }
    }
    
    @Published var appearanceMode: String {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode") }
    }
    
    @Published var compactMode: Bool {
        didSet { UserDefaults.standard.set(compactMode, forKey: "compactMode") }
    }
    
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    
    @Published var highROIThreshold: Double {
        didSet { UserDefaults.standard.set(highROIThreshold, forKey: "highROIThreshold") }
    }
    
    @Published var lowROIThreshold: Double {
        didSet { UserDefaults.standard.set(lowROIThreshold, forKey: "lowROIThreshold") }
    }
    
    // MARK: - API Credentials (Keychain)
    @Published var apiKey: String = ""
    @Published var apiSecret: String = ""
    
    private init() {
        let defaults = UserDefaults.standard
        
        self.menuBarMetric = defaults.string(forKey: "menuBarMetric") ?? "ROI"
        self.appearanceMode = defaults.string(forKey: "appearanceMode") ?? "System"
        self.compactMode = defaults.bool(forKey: "compactMode")
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        
        // Handle potential missing keys for thresholds by setting defaults if 0 (unless 0 is valid, but for thresholds usually not default)
        // Better to just read and if nil/0 use default.
        let high = defaults.double(forKey: "highROIThreshold")
        self.highROIThreshold = high == 0 ? 20.0 : high
        
        let low = defaults.double(forKey: "lowROIThreshold")
        self.lowROIThreshold = low == 0 ? -20.0 : low
        
        loadCredentials()
    }
    
    func loadCredentials() {
        if let key = KeychainManager.shared.get(for: "kalshi_key") {
            self.apiKey = key
        }
        if let secret = KeychainManager.shared.get(for: "kalshi_token") {
            self.apiSecret = secret
        }
    }
    
    func saveCredentials() {
        if !apiKey.isEmpty {
            _ = KeychainManager.shared.save(apiKey, for: "kalshi_key")
        }
        if !apiSecret.isEmpty {
            _ = KeychainManager.shared.save(apiSecret, for: "kalshi_token")
        }
    }
}

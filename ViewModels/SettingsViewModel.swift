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
    
    @Published var autoEnableNewAlerts: Bool {
        didSet { UserDefaults.standard.set(autoEnableNewAlerts, forKey: "autoEnableNewAlerts") }
    }

    @Published var minimumArbitrageProfit: Double = 1.0 {
        didSet { UserDefaults.standard.set(minimumArbitrageProfit, forKey: "minimumArbitrageProfit") }
    }

    @Published var arbitrageAlertsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(arbitrageAlertsEnabled, forKey: "arbitrageAlertsEnabled") }
    }

    @Published var alertSettings: [String: AlertSettings] {
        didSet {
            if let encoded = try? JSONEncoder().encode(alertSettings) {
                UserDefaults.standard.set(encoded, forKey: "alertSettings")
            }
        }
    }
    
    // MARK: - API Credentials (Keychain)
    // MARK: - API Credentials (Keychain)
    @Published var hasCredentials: Bool = false
    
    private init() {
        let defaults = UserDefaults.standard

        self.menuBarMetric = defaults.string(forKey: "menuBarMetric") ?? "Cash Out"
        self.appearanceMode = defaults.string(forKey: "appearanceMode") ?? "System"
        self.compactMode = defaults.bool(forKey: "compactMode")
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        self.autoEnableNewAlerts = defaults.bool(forKey: "autoEnableNewAlerts")

        if let data = defaults.data(forKey: "alertSettings"),
           let decoded = try? JSONDecoder().decode([String: AlertSettings].self, from: data) {
            self.alertSettings = decoded
        } else {
            self.alertSettings = [:]
        }

        // Handle potential missing keys for thresholds by setting defaults if 0 (unless 0 is valid, but for thresholds usually not default)
        // Better to just read and if nil/0 use default.
        let high = defaults.double(forKey: "highROIThreshold")
        self.highROIThreshold = high == 0 ? 20.0 : high

        let low = defaults.double(forKey: "lowROIThreshold")
        self.lowROIThreshold = low == 0 ? -20.0 : low

        // Initialize arbitrage settings
        let minArb = defaults.double(forKey: "minimumArbitrageProfit")
        self.minimumArbitrageProfit = minArb == 0 ? 1.0 : minArb  // Default $1 minimum

        self.arbitrageAlertsEnabled = defaults.bool(forKey: "arbitrageAlertsEnabled")

        // All properties initialized, safe to call methods on self
        loadCredentialsState()
    }
    
    func loadCredentialsState() {
        self.hasCredentials = CredentialsManager.shared.hasCredentials()
    }
    
    func saveCredentials(key: String, secret: String) {
        guard !key.isEmpty, !secret.isEmpty else { return }
        
        do {
            try CredentialsManager.shared.save(apiKey: key, privateKey: secret)
            loadCredentialsState()
        } catch {
            print("Failed to save credentials: \(error)")
        }
    }
    
    func deleteCredentials() {
        do {
            try CredentialsManager.shared.delete()
            loadCredentialsState()
        } catch {
            print("Failed to delete credentials: \(error)")
        }
    }
    
    // MARK: - Helper Methods for Alerts
    
    func getAlertSettings(for ticker: String) -> AlertSettings {
        if let settings = alertSettings[ticker] {
            return settings
        }
        
        // If no settings exist, create default based on auto-enable preference
        // But we don't save it yet until explicitly interacted with
        return AlertSettings(isEnabled: autoEnableNewAlerts, useGlobal: true)
    }
    
    func updateAlertSettings(for ticker: String, settings: AlertSettings) {
        alertSettings[ticker] = settings
    }
    
    func toggleAlert(for ticker: String) {
        var settings = getAlertSettings(for: ticker)
        settings.isEnabled.toggle()
        updateAlertSettings(for: ticker, settings: settings)
    }
}

struct AlertSettings: Codable, Equatable {
    var isEnabled: Bool
    var useGlobal: Bool = true
    var highROI: Double?
    var lowROI: Double?
    var targetProfit: Double?
    var targetPrice: Double?
    var arbitrageEnabled: Bool = true  // Per-position arbitrage toggle

    // Stop-loss thresholds (downside protection)
    var stopLossMinPrice: Double?    // Minimum price in cents (0-100)
    var stopLossMinProfit: Double?   // Minimum profit in dollars
}

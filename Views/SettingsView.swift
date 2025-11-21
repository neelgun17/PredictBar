import SwiftUI

struct SettingsView: View {
    @AppStorage("highROIThreshold") private var highROIThreshold: Double = 20.0
    @AppStorage("lowROIThreshold") private var lowROIThreshold: Double = -20.0
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("menuBarMetric") private var menuBarMetric: String = "ROI" // ROI, PnL, Portfolio, Balance, None
    @AppStorage("appearanceMode") private var appearanceMode: String = "System" // System, Light, Dark
    @AppStorage("compactMode") private var compactMode: Bool = false
    
    @ObservedObject var viewModel: DashboardViewModel
    
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        Form {
            Section(header: Text("Menu Bar Display")) {
                Picker("Show Metric", selection: $menuBarMetric) {
                    Text("ROI").tag("ROI")
                    Text("P&L").tag("PnL")
                    Text("Portfolio Value").tag("Portfolio")
                    Text("Balance").tag("Balance")
                    Text("None").tag("None")
                }
                .pickerStyle(.menu)
                .onChange(of: menuBarMetric) { _ in
                    viewModel.updateMenuBarText()
                }
            }
            
            Section(header: Text("Appearance")) {
                Picker("Theme", selection: $appearanceMode) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }
                .pickerStyle(.menu)
                
                Toggle("Compact Mode (Top 3)", isOn: $compactMode)
            }
            
            Section(header: Text("Notifications")) {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                
                if notificationsEnabled {
                    VStack(alignment: .leading) {
                        Text("High ROI Threshold (%)")
                        TextField("High ROI", value: $highROIThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Low ROI Threshold (%)")
                        TextField("Low ROI", value: $lowROIThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            
            Section(header: Text("Kalshi API Credentials")) {
                SecureField("API Key", text: $apiKey)
                SecureField("API Secret", text: $apiSecret)
            }
            
            Button("Save Credentials") {
                // Save to Keychain
                if !apiKey.isEmpty {
                    _ = KeychainManager.shared.save(apiKey, for: "kalshi_key")
                }
                if !apiSecret.isEmpty {
                    _ = KeychainManager.shared.save(apiSecret, for: "kalshi_token")
                }
                presentationMode.wrappedValue.dismiss()
            }
        }
        .padding()
        .frame(width: 300)
    }
}

import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        Form {
            Section(header: Text("Kalshi API Credentials")) {
                SecureField("API Key", text: $apiKey)
                SecureField("API Secret", text: $apiSecret)
            }
            
            Button("Save Credentials") {
                // Save to Keychain
                _ = KeychainManager.shared.save(apiKey, for: "kalshi_key")
                _ = KeychainManager.shared.save(apiSecret, for: "kalshi_token") // Using token as secret for simplicity here
                presentationMode.wrappedValue.dismiss()
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

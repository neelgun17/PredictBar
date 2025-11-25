import SwiftUI

struct APISettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var showSavedMessage = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Kalshi API Credentials")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("API Key")
                        .frame(width: 80, alignment: .leading)
                    TextField("Enter API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("API Secret")
                        .frame(width: 80, alignment: .leading)
                    SecureField("Enter Private Key (PEM)", text: $apiSecret)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Spacer()
                        .frame(width: 88) // Align with text fields (80 label + 8 spacing)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button("Save Credentials") {
                                viewModel.saveCredentials(key: apiKey, secret: apiSecret)
                                
                                // Clear fields after save for security
                                apiKey = ""
                                apiSecret = ""
                                
                                withAnimation {
                                    showSavedMessage = true
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        showSavedMessage = false
                                    }
                                }
                            }
                            .disabled(apiKey.isEmpty || apiSecret.isEmpty)
                            
                            if showSavedMessage {
                                Text("Saved securely to Keychain ✓")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                    .transition(.opacity)
                            } else if viewModel.hasCredentials {
                                Text("Credentials stored ✓")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        
                        if viewModel.hasCredentials {
                            Button("Delete Credentials") {
                                viewModel.deleteCredentials()
                            }
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.top, 4)
                        }
                        
                        Text("Your credentials are stored securely in the macOS Keychain.")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.top, 4)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.top, 20)
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

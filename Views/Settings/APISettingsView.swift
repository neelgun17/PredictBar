import SwiftUI

struct APISettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    @State private var showSavedMessage = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Kalshi API Credentials")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("API Key")
                        .frame(width: 80, alignment: .leading)
                    SecureField("", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("API Secret")
                        .frame(width: 80, alignment: .leading)
                    SecureField("", text: $viewModel.apiSecret)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Spacer()
                        .frame(width: 88) // Align with text fields (80 label + 8 spacing)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button("Save Credentials") {
                                viewModel.saveCredentials()
                                withAnimation {
                                    showSavedMessage = true
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        showSavedMessage = false
                                    }
                                }
                            }
                            
                            if showSavedMessage {
                                Text("Saved ✓")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                    .transition(.opacity)
                            }
                        }
                        
                        Text("Your credentials are stored securely in the macOS Keychain.")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
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

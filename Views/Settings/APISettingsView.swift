import SwiftUI

struct APISettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    @State private var showSavedMessage = false
    
    var body: some View {
        Form {
            Section(header: Text("Kalshi API Credentials")) {
                SecureField("API Key", text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Secret", text: $viewModel.apiSecret)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Spacer()
                if showSavedMessage {
                    Text("Saved!")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
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
            }
        }
        .padding()
    }
}

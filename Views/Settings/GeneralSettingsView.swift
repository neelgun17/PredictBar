import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    
    var body: some View {
        Form {
            Picker("Theme", selection: $viewModel.appearanceMode) {
                Text("System").tag("System")
                Text("Light").tag("Light")
                Text("Dark").tag("Dark")
            }
            .pickerStyle(.inline)
            
            Text("Choose the appearance of the menu bar app.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

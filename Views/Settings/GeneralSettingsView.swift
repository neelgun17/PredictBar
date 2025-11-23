import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                
                Picker("", selection: $viewModel.appearanceMode) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden() // Hide the empty label space
                
                Text("Choose the appearance of the menu bar app.")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.top, 20)
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

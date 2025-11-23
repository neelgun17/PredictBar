import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Alerts")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)
                    
                    Text("Receive alerts when your portfolio ROI moves above or below your selected thresholds.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.leading, 24) // Indent to align with text
                }
                .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("High ROI (%)")
                            .frame(width: 100, alignment: .leading)
                        TextField("20", value: $viewModel.highROIThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .disabled(!viewModel.notificationsEnabled)
                    }
                    
                    HStack {
                        Text("Low ROI (%)")
                            .frame(width: 100, alignment: .leading)
                        TextField("-20", value: $viewModel.lowROIThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .disabled(!viewModel.notificationsEnabled)
                    }
                }
                .padding(.leading, 24)
                .opacity(viewModel.notificationsEnabled ? 1.0 : 0.5)
            }
            
            Spacer()
        }
        .padding(.top, 20)
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

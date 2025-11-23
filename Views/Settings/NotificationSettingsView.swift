import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    
    @State private var highROIText: String = ""
    @State private var lowROIText: String = ""
    
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
                    
                    Toggle("Enable alerts automatically for new positions", isOn: $viewModel.autoEnableNewAlerts)
                        .padding(.leading, 24)
                        .disabled(!viewModel.notificationsEnabled)
                }
                .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("High ROI (%)")
                            .frame(width: 100, alignment: .leading)
                        TextField("20", text: $highROIText)
                        .onChange(of: highROIText) { newValue in
                            if let value = Double(newValue) {
                                viewModel.highROIThreshold = value
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .disabled(!viewModel.notificationsEnabled)
                    }
                    
                    HStack {
                        Text("Low ROI (%)")
                            .frame(width: 100, alignment: .leading)
                        TextField("-20", text: $lowROIText)
                        .onChange(of: lowROIText) { newValue in
                            if let value = Double(newValue) {
                                viewModel.lowROIThreshold = value
                            }
                        }
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
        .onAppear {
            highROIText = String(format: "%.1f", viewModel.highROIThreshold)
            lowROIText = String(format: "%.1f", viewModel.lowROIThreshold)
        }
    }
}

import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    
    @State private var highROIText: String = ""
    @State private var lowROIText: String = ""
    @State private var highROIError: String? = nil
    @State private var lowROIError: String? = nil
    
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
                
                VStack(alignment: .leading, spacing: 12) {
                    // High ROI Input
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("High ROI (%)")
                                .frame(width: 100, alignment: .leading)
                            TextField("20", text: $highROIText)
                                .onChange(of: highROIText) { newValue in
                                    validateHighROI(newValue)
                                }
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.red, lineWidth: highROIError != nil ? 1 : 0)
                                )
                                .disabled(!viewModel.notificationsEnabled)
                            
                            if let error = highROIError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    // Low ROI Input
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Low ROI (%)")
                                .frame(width: 100, alignment: .leading)
                            TextField("-20", text: $lowROIText)
                                .onChange(of: lowROIText) { newValue in
                                    validateLowROI(newValue)
                                }
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.red, lineWidth: lowROIError != nil ? 1 : 0)
                                )
                                .disabled(!viewModel.notificationsEnabled)
                            
                            if let error = lowROIError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
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
    
    private func validateHighROI(_ value: String) {
        guard let doubleValue = Double(value) else {
            highROIError = "Invalid number"
            return
        }
        
        if doubleValue < 1 || doubleValue > 10000 {
            highROIError = "Must be 1% - 10,000%"
        } else {
            highROIError = nil
            viewModel.highROIThreshold = doubleValue
        }
    }
    
    private func validateLowROI(_ value: String) {
        guard let doubleValue = Double(value) else {
            lowROIError = "Invalid number"
            return
        }
        
        if doubleValue < -100 || doubleValue > -1 {
            lowROIError = "Must be -100% - -1%"
        } else {
            lowROIError = nil
            viewModel.lowROIThreshold = doubleValue
        }
    }
}

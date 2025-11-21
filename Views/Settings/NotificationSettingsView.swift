import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    
    var body: some View {
        Form {
            Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)
            
            if viewModel.notificationsEnabled {
                Section {
                    VStack(alignment: .leading) {
                        Text("High ROI Threshold (%)")
                        TextField("High ROI", value: $viewModel.highROIThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Low ROI Threshold (%)")
                        TextField("Low ROI", value: $viewModel.lowROIThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding()
    }
}

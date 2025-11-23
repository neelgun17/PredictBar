import SwiftUI

struct PositionAlertConfigurationView: View {
    let ticker: String
    let marketTitle: String
    @ObservedObject var viewModel = SettingsViewModel.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var settings: AlertSettings
    
    init(ticker: String, marketTitle: String) {
        self.ticker = ticker
        self.marketTitle = marketTitle
        _settings = State(initialValue: SettingsViewModel.shared.getAlertSettings(for: ticker))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Alerts for \(marketTitle)")
                .font(.headline)
            
            Toggle("Use global thresholds", isOn: $settings.useGlobal)
            
            if !settings.useGlobal {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("High ROI (%)")
                            .frame(width: 100, alignment: .leading)
                        TextField("Global", value: $settings.highROI, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Low ROI (%)")
                            .frame(width: 100, alignment: .leading)
                        TextField("Global", value: $settings.lowROI, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Target Profit ($)")
                            .frame(width: 100, alignment: .leading)
                        TextField("Optional", value: $settings.targetProfit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Target Price (¢)")
                            .frame(width: 100, alignment: .leading)
                        TextField("Optional", value: $settings.targetPrice, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity)
            }
            
            HStack {
                Spacer()
                Button("Done") {
                    viewModel.updateAlertSettings(for: ticker, settings: settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
        .onDisappear {
            // Ensure settings are saved even if dismissed via clicking outside
            viewModel.updateAlertSettings(for: ticker, settings: settings)
        }
    }
}

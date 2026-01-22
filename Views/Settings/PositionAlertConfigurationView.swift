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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Arbitrage Alerts", isOn: $settings.arbitrageEnabled)
                    .help("Alert when arbitrage opportunity detected for this position")

                Text("Receive alerts when you can buy the opposite side and guarantee profit.")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.leading, 24)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Stop-Loss Protection")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Alert when position drops below threshold (triggers once, resets when price recovers)")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.bottom, 4)

                HStack {
                    Text("Min Price (¢)")
                        .frame(width: 100, alignment: .leading)
                    TextField("Optional", value: $settings.stopLossMinPrice, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Text("Alert if price ≤ this")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }

                HStack {
                    Text("Min Profit ($)")
                        .frame(width: 100, alignment: .leading)
                    TextField("Optional", value: $settings.stopLossMinProfit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Text("Alert if P&L ≤ this (can be negative)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
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

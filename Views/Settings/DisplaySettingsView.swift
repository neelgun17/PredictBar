import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    
    var body: some View {
        Form {
            Picker("Menu Bar Metric", selection: $viewModel.menuBarMetric) {
                Text("ROI").tag("ROI")
                Text("P&L").tag("PnL")
                Text("Portfolio Value").tag("Portfolio")
                Text("Balance").tag("Balance")
                Text("None").tag("None")
            }
            .pickerStyle(.inline)
            
            Toggle("Compact Mode (Top 3)", isOn: $viewModel.compactMode)
            
            Text("Compact mode limits the dropdown to show only your top 3 positions.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

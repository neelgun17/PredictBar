import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Menu Bar Display")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Menu Bar Metric")
                
                Picker("", selection: $viewModel.menuBarMetric) {
                    Text("Cash Out").tag("Cash Out")
                    Text("ROI").tag("ROI")
                    Text("P&L").tag("PnL")
                    Text("Portfolio Value").tag("Portfolio")
                    Text("Balance").tag("Balance")
                    Text("None").tag("None")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                
                Text("Choose what summary metric appears in the menu bar.")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Compact Mode (Top 3)", isOn: $viewModel.compactMode)
                    
                    Text("Only show your top 3 positions in the dropdown.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.leading, 24) // Indent to align with text
                }
            }
            
            Spacer()
        }
        .padding(.top, 20)
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

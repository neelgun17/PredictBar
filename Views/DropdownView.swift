import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kalshi Dashboard")
                    .font(.headline)
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if viewModel.positions.isEmpty {
                Text("No active positions")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(viewModel.positions) { position in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(position.marketTicker)
                                .font(.system(size: 12, weight: .medium))
                            Text("\(position.quantity) shares @ \(String(format: "$%.2f", position.entryPrice))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(String(format: "$%.2f", position.currentPrice))
                                .font(.system(size: 12, weight: .bold))
                            Text(String(format: "%.1f%%", position.roi))
                                .font(.caption)
                                .foregroundColor(position.roi >= 0 ? .green : .red)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
                .frame(maxHeight: 300)
            }
            
            Divider()
            
            HStack {
                Text("Total ROI: \(String(format: "%.2f%%", viewModel.overallROI))")
                    .font(.caption)
                Spacer()
                Button("Open on Kalshi") {
                    if let url = URL(string: "https://kalshi.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 320)
        .popover(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

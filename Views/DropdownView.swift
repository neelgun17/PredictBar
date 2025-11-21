import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    @State private var showSettings = false
    // 0: ROI, 1: P&L, 2: Portfolio Value, 3: Account Balance
    @State private var displayMode = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kalshi Dashboard")
                    .font(.headline)
                    .onTapGesture {
                        if let url = URL(string: "https://kalshi.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .help("Open Kalshi Homepage")
                Spacer()
                Button(action: { viewModel.fetchData() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                
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
                ScrollView { // Added ScrollView to contain ForEach
                    VStack(spacing: 0) { // Added VStack to contain ForEach items and dividers
                        ForEach(viewModel.positions) { position in
                            VStack(alignment: .leading) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(position.title ?? position.marketTicker)
                                            .font(.headline)
                                            .lineLimit(1)
                                        
                                        // Show Side + Subtitle (e.g., "Yes - Denver")
                                        Text("\(position.side)\(position.subtitle?.isEmpty == false ? " - \(position.subtitle!)" : "")")
                                            .font(.subheadline) // Slightly larger than caption
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            
                                        Text("\(position.quantity) shares @ \(position.entryPrice, format: .currency(code: "USD"))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(position.currentPrice, format: .currency(code: "USD"))
                                            .font(.headline)

                                        Text("ROI")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Text(position.realizedROI, format: .percent.precision(.fractionLength(1)))
                                            .font(.caption)
                                            .foregroundColor(position.realizedROI >= 0 ? .green : .red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal) // Added horizontal padding for the content
                            .contentShape(Rectangle()) // Make entire row clickable
                            .onTapGesture {
                                if let url = position.marketUrl {
                                    NSWorkspace.shared.open(url)
                                } else if let eventTicker = position.eventTicker {
                                    // Fallback
                                    if let url = URL(string: "https://kalshi.com/markets/\(eventTicker)") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            
            Divider()
            
            HStack {
                Group {
                    switch displayMode {
                    case 0:
                        Text("TOTAL ROI: \(viewModel.overallROI.formatted(.percent.precision(.fractionLength(2))))")
                            .foregroundColor(viewModel.overallROI >= 0 ? .green : .red)
                    case 1:
                        Text("TOTAL P&L: \(viewModel.overallPnL.formatted(.currency(code: "USD")))")
                            .foregroundColor(viewModel.overallPnL >= 0 ? .green : .red)
                    case 2:
                        Text("POSITIONS: \(viewModel.portfolioValue.formatted(.currency(code: "USD")))")
                            .foregroundColor(.primary)
                    case 3:
                        Text("CASH: \(viewModel.accountBalance.formatted(.currency(code: "USD")))")
                            .foregroundColor(.primary)
                    default:
                        EmptyView()
                    }
                }
                .font(.caption)
                .fontWeight(.medium)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        displayMode = (displayMode + 1) % 4
                    }
                }
                .help("Click to cycle: ROI -> P&L -> Portfolio -> Balance")
                
                Spacer()
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

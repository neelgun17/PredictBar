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
                                    
                                    VStack(alignment: .trailing) {
                                        Text(position.currentPrice, format: .currency(code: "USD"))
                                            .font(.headline)
                                        
                                        Text("\(position.roi, specifier: "%.1f")%")
                                            .font(.caption)
                                            .foregroundColor(position.roi >= 0 ? .green : .red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal) // Added horizontal padding for the content
                            .contentShape(Rectangle()) // Make entire row clickable
                            .onTapGesture {
                                if let eventTicker = position.eventTicker {
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
                Text("Total ROI: \(String(format: "%.2f%%", viewModel.overallROI))")
                    .font(.caption)
                Spacer()
                Button("Open Kalshi") {
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

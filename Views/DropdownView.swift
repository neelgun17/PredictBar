import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    // 0: Cash Out, 1: ROI, 2: P&L, 3: Portfolio Value, 4: Account Balance
    @State private var displayMode = 0
    
    @AppStorage("appearanceMode") private var appearanceMode: String = "System"
//    @AppStorage("appearanceMode") private var appearanceMode: String = "System"
    @AppStorage("compactMode") private var compactMode: Bool = false
    
    var displayedPositions: [Position] {
        if compactMode {
            return Array(viewModel.positions.prefix(3))
        } else {
            return viewModel.positions
        }
    }
    
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("KALSHI DASHBOARD")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { viewModel.fetchData() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                    
                    Button(action: openSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .onTapGesture {
                if let url = URL(string: "https://kalshi.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Divider()
                .opacity(0.5)
            
            // Positions Section
            if viewModel.positions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Active Positions")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("POSITIONS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.8))
                        Spacer()
                        Text("PnL")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(displayedPositions) { position in
                                VStack(spacing: 0) {
                                    HStack(spacing: 10) {
                                        // Icon based on side
                                        Image(systemName: position.side == "Yes" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(position.side == "Yes" ? .green : .red)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(position.title ?? position.marketTicker)
                                                .font(.system(size: 13, weight: .medium))
                                                .lineLimit(1)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    Text(position.subtitle ?? position.side)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.primary.opacity(0.65))
                                                    
                                                    Text("·")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.primary.opacity(0.4))
                                                    
                                                    Text("Qty: \(position.quantity)")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.primary.opacity(0.65))
                                                }
                                                
                                                HStack(spacing: 4) {
                                                    Text("Avg \(position.entryPrice, format: .currency(code: "USD"))")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.primary.opacity(0.65))
                                                    
                                                    Text("·")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.primary.opacity(0.4))
                                                    
                                                    Text("Sell \(position.currentPrice, format: .currency(code: "USD"))")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.primary.opacity(0.65))
                                                }
                                            }
                                        }
                                        
                                        Spacer(minLength: 6)
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(position.realizedPnL, format: .currency(code: "USD").sign(strategy: .always()))
                                                .font(.system(size: 13, weight: .bold))
                                                .monospacedDigit()
                                                .foregroundColor(abs(position.realizedPnL) < 0.01 ? .secondary : (position.realizedPnL > 0 ? .green : .red))
                                            
                                            Text(position.realizedROI.formatted(.percent.precision(.fractionLength(1))))
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor((abs(position.realizedPnL) < 0.01 ? .secondary : (position.realizedPnL > 0 ? Color.green : Color.red)).opacity(0.8))
                                                .monospacedDigit()
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let url = position.marketUrl {
                                            NSWorkspace.shared.open(url)
                                        } else if let eventTicker = position.eventTicker {
                                            if let url = URL(string: "https://kalshi.com/markets/\(eventTicker)") {
                                                NSWorkspace.shared.open(url)
                                            }
                                        }
                                    }
                                    
                                    Divider()
                                        .padding(.leading, 38) // Indent divider to match text
                                        .opacity(0.12)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
            
            Divider()
                .opacity(0.5)
            
            // Account Section
            VStack(alignment: .leading, spacing: 0) {
                Text("ACCOUNT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                HStack(spacing: 10) {
                    Image(systemName: getIconForMode(displayMode))
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .frame(width: 16)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(getTitleForMode(displayMode))
                            .font(.system(size: 13, weight: .medium))
                        Text("Click to cycle")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(getValueForMode(displayMode))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(getColorForMode(displayMode))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        displayMode = (displayMode + 1) % 5
                    }
                }
            }
            .background(.ultraThinMaterial)
        }
        .frame(width: 340)
        .background(.ultraThinMaterial) // Main background
    }
    
    // Helper functions for cleaner body
    private func getIconForMode(_ mode: Int) -> String {
        switch mode {
        case 0: return "dollarsign.circle.fill"
        case 1: return "percent"
        case 2: return "chart.line.uptrend.xyaxis"
        case 3: return "briefcase.fill"
        case 4: return "banknote.fill"
        default: return "circle"
        }
    }
    
    private func getTitleForMode(_ mode: Int) -> String {
        switch mode {
        case 0: return "Total Cash Out"
        case 1: return "Total ROI"
        case 2: return "Total P&L"
        case 3: return "Portfolio Value"
        case 4: return "Available Balance"
        default: return ""
        }
    }
    
    private func getValueForMode(_ mode: Int) -> String {
        switch mode {
        case 0: return viewModel.totalCashOutValue.formatted(.currency(code: "USD"))
        case 1: return viewModel.overallROI.formatted(.percent.precision(.fractionLength(2)))
        case 2: return viewModel.overallPnL.formatted(.currency(code: "USD"))
        case 3: return viewModel.portfolioValue.formatted(.currency(code: "USD"))
        case 4: return viewModel.accountBalance.formatted(.currency(code: "USD"))
        default: return ""
        }
    }
    
    private func getColorForMode(_ mode: Int) -> Color {
        switch mode {
        case 1: return viewModel.overallROI >= 0 ? .green : .red
        case 2: return viewModel.overallPnL >= 0 ? .green : .red
        default: return .primary
        }
    }
    
    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
    
    private func openSettings() {
        SettingsWindowManager.shared.open()
    }
}

import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var settingsViewModel = SettingsViewModel.shared
    @Environment(\.openWindow) private var openWindow
    
    // 0: Cash Out, 1: ROI, 2: P&L, 3: Portfolio Value, 4: Account Balance
    @State private var displayMode = 2
    @State private var configuringPosition: Position?
    @State private var hoveredTicker: String?
    
    @AppStorage("appearanceMode") private var appearanceMode: String = "System"
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
                                        // Bell Icon for Alerts
                                        Button(action: {
                                            settingsViewModel.toggleAlert(for: position.ticker)
                                        }) {
                                            let isEnabled = settingsViewModel.getAlertSettings(for: position.ticker).isEnabled
                                            Image(systemName: isEnabled ? "bell.fill" : "bell")
                                                .font(.system(size: 12))
                                                .foregroundColor(isEnabled ? .accentColor : .secondary.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)
                                        .help(settingsViewModel.notificationsEnabled ? "Toggle Alerts" : "Enable notifications in Settings to use alerts")
                                        .disabled(!settingsViewModel.notificationsEnabled)
                                        

                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Text(position.title ?? position.marketTicker)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .lineLimit(1)
                                                if hoveredTicker == position.ticker {
                                                    Image(systemName: "arrow.up.right")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundColor(.secondary)
                                                        .transition(.opacity)
                                                }
                                            }
                                            .onHover { hovering in
                                                if hovering {
                                                    hoveredTicker = position.ticker
                                                } else if hoveredTicker == position.ticker {
                                                    hoveredTicker = nil
                                                }
                                            }
                                            .onTapGesture {
                                                if let url = position.marketUrl {
                                                    NSWorkspace.shared.open(url)
                                                }
                                            }
                                            .animation(.easeInOut(duration: 0.15), value: hoveredTicker == position.ticker)

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

                                                    // Compact arbitrage badge inline
                                                    if let arb = position.lastArbitrageOpportunity {
                                                        Text("·")
                                                            .font(.system(size: 11))
                                                            .foregroundColor(.primary.opacity(0.4))

                                                        HStack(spacing: 2) {
                                                            Image(systemName: "scalemass.fill")
                                                                .font(.system(size: 7))
                                                            Text("+\(arb.guaranteedProfit, format: .currency(code: "USD"))")
                                                                .font(.system(size: 9, weight: .semibold))
                                                        }
                                                        .padding(.horizontal, 3)
                                                        .padding(.vertical, 1)
                                                        .background(Color.green.opacity(0.15))
                                                        .foregroundColor(.green)
                                                        .cornerRadius(3)
                                                    }
                                                }
                                                
                                                HStack(spacing: 4) {
                                                    Text("Avg \(position.entryPrice, format: .currency(code: "USD"))")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.primary.opacity(0.65))
                                                    
                                                    Text("·")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.primary.opacity(0.4))
                                                    
                                                    if let sellURL = sellUrl(for: position) {
                                                        Button(action: {
                                                            NSWorkspace.shared.open(sellURL)
                                                        }) {
                                                            Text("Sell \(position.currentPrice, format: .currency(code: "USD"))")
                                                                .font(.system(size: 10, weight: .bold))
                                                                .lineLimit(1) // Prevent wrapping
                                                                .fixedSize()  // Force full width
                                                                .foregroundColor(.white)
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(Color.accentColor)
                                                                .cornerRadius(4)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .onHover { inside in
                                                            if inside {
                                                                NSCursor.pointingHand.push()
                                                            } else {
                                                                NSCursor.pop()
                                                            }
                                                        }
                                                    } else {
                                                        Text("Sell \(position.currentPrice, format: .currency(code: "USD"))")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .lineLimit(1)
                                                            .fixedSize()
                                                            .foregroundColor(.secondary)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.secondary.opacity(0.1))
                                                            .cornerRadius(4)
                                                    }
                                                    
                                                    Button(action: {
                                                        configuringPosition = position
                                                    }) {
                                                        Text("Alerts")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(.primary)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.secondary.opacity(0.1))
                                                            .cornerRadius(4)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .onHover { inside in
                                                        if inside {
                                                            NSCursor.pointingHand.push()
                                                        } else {
                                                            NSCursor.pop()
                                                        }
                                                    }

                                                    // Arbitrage Hedge button - compact version
                                                    if let arb = position.lastArbitrageOpportunity,
                                                       let hedgeURL = hedgeUrl(for: position, opportunity: arb) {
                                                        Button(action: {
                                                            NSWorkspace.shared.open(hedgeURL)
                                                        }) {
                                                            HStack(spacing: 2) {
                                                                Image(systemName: "scalemass.fill")
                                                                    .font(.system(size: 7))
                                                                Text("Hedge")
                                                                    .font(.system(size: 10, weight: .bold))
                                                                    .lineLimit(1)
                                                                    .fixedSize()
                                                            }
                                                            .foregroundColor(.white)
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 2)
                                                            .background(Color.green)
                                                            .cornerRadius(4)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Guaranteed profit: \(arb.guaranteedProfit.formatted(.currency(code: "USD")))")
                                                        .onHover { inside in
                                                            if inside {
                                                                NSCursor.pointingHand.push()
                                                            } else {
                                                                NSCursor.pop()
                                                            }
                                                        }
                                                    }
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
                                    .contextMenu {
                                        Button("Configure Alerts...") {
                                            configuringPosition = position
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
        .frame(width: 360)
        .background(.ultraThinMaterial) // Main background
        .popover(item: $configuringPosition) { position in
            PositionAlertConfigurationView(ticker: position.ticker, marketTitle: position.title ?? position.marketTicker)
        }
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
    
    private func sellUrl(for position: Position) -> URL? {
        let side = position.side.lowercased()
        let qty = abs(position.quantity)
        
        // Prefer the resolved market URL (markets/{series}/{slug}/{event}) and hint trade tab + sell side + qty.
        if let marketUrl = position.marketUrl,
           var components = URLComponents(url: marketUrl, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "tab", value: "trade"))
            items.append(URLQueryItem(name: "action", value: "sell"))
            items.append(URLQueryItem(name: "side", value: side))
            items.append(URLQueryItem(name: "quantity", value: "\(qty)"))
            components.queryItems = items
            return components.url
        }
        
        // If we have enough metadata, build the markets path directly.
        if let series = position.seriesTicker?.lowercased(),
           let event = position.eventTicker?.lowercased(),
           let seriesTitle = position.seriesTitle {
            let slug = seriesTitle
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .folding(options: .diacriticInsensitive, locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(.init(charactersIn: "-")))
                .joined()
            
            var components = URLComponents()
            components.scheme = "https"
            components.host = "kalshi.com"
            components.path = "/markets/\(series)/\(slug)/\(event)"
            components.queryItems = [
                URLQueryItem(name: "tab", value: "trade"),
                URLQueryItem(name: "action", value: "sell"),
                URLQueryItem(name: "side", value: side),
                URLQueryItem(name: "quantity", value: "\(qty)")
            ]
            return components.url
        }
        
        // Fallback to the trade route which typically opens the order form directly.
        var components = URLComponents()
        components.scheme = "https"
        components.host = "kalshi.com"
        components.path = "/trade/\(position.marketTicker.lowercased())"
        components.queryItems = [
            URLQueryItem(name: "action", value: "sell"),
            URLQueryItem(name: "side", value: side),
            URLQueryItem(name: "quantity", value: "\(qty)")
        ]
        return components.url
    }

    private func hedgeUrl(for position: Position, opportunity: Position.ArbitrageOpportunity) -> URL? {
        let oppositeSide = position.position > 0 ? "no" : "yes"
        let qty = abs(position.quantity)

        // Prefer the resolved market URL
        if let marketUrl = position.marketUrl,
           var components = URLComponents(url: marketUrl, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "tab", value: "trade"))
            items.append(URLQueryItem(name: "action", value: "buy"))
            items.append(URLQueryItem(name: "side", value: oppositeSide))
            items.append(URLQueryItem(name: "quantity", value: "\(qty)"))
            items.append(URLQueryItem(name: "limit_price", value: String(format: "%.2f", opportunity.oppositeSidePrice)))
            components.queryItems = items
            return components.url
        }

        // Fallback
        var components = URLComponents()
        components.scheme = "https"
        components.host = "kalshi.com"
        components.path = "/trade/\(position.ticker.lowercased())"
        components.queryItems = [
            URLQueryItem(name: "action", value: "buy"),
            URLQueryItem(name: "side", value: oppositeSide),
            URLQueryItem(name: "quantity", value: "\(qty)"),
            URLQueryItem(name: "limit_price", value: String(format: "%.2f", opportunity.oppositeSidePrice))
        ]
        return components.url
    }
}

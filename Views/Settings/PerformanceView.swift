import SwiftUI

struct PerformanceView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Refresh button
                HStack {
                    Spacer()
                    Button(action: { viewModel.refreshTradeHistory() }) {
                        HStack(spacing: 4) {
                            if viewModel.isLoadingFills {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            Text("Refresh")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isLoadingFills)
                }

                if let metrics = viewModel.tradeMetrics, metrics.totalTrades > 0 {
                    heroStatsSection(metrics)
                    pnlChartSection(metrics)
                    marketBreakdownSection(metrics)
                    recentTradesSection
                } else if viewModel.isLoadingFills {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading trade history...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No trade history yet")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text("Complete some trades to see your stats here.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 40)
                }
            }
            .padding()
        }
    }

    // MARK: - Hero Stats

    @ViewBuilder
    private func heroStatsSection(_ metrics: TradeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OVERVIEW")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // Win Rate Ring
                statCard {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                            .frame(width: 36, height: 36)
                        Circle()
                            .trim(from: 0, to: CGFloat(metrics.winRate))
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(metrics.winRate * 100))%")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                    }
                    Text("Win Rate")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Total P&L
                statCard {
                    Text(metrics.totalRealizedPnL >= 0 ? "+\(metrics.totalRealizedPnL.formatted(.currency(code: "USD")))" : metrics.totalRealizedPnL.formatted(.currency(code: "USD")))
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(metrics.totalRealizedPnL >= 0 ? .green : .red)
                    Text("Realized P&L")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Total Trades
                statCard {
                    Text("\(metrics.totalTrades)")
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                    Text("Round Trips")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Current Streak
                statCard {
                    HStack(spacing: 2) {
                        Text(metrics.currentStreak.type == .win ? "🔥" : "❄️")
                            .font(.system(size: 14))
                        Text(metrics.currentStreak.display)
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                    }
                    Text("Streak")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            // Secondary stats row
            HStack(spacing: 16) {
                miniStat(label: "Avg/Trade", value: metrics.avgProfitPerTrade.formatted(.currency(code: "USD")), color: metrics.avgProfitPerTrade >= 0 ? .green : .red)
                miniStat(label: "Best", value: metrics.bestTrade?.pnl.formatted(.currency(code: "USD")) ?? "-", color: .green)
                miniStat(label: "Worst", value: metrics.worstTrade?.pnl.formatted(.currency(code: "USD")) ?? "-", color: .red)
                miniStat(label: "Fees Paid", value: metrics.totalFeesPaid.formatted(.currency(code: "USD")), color: .secondary)
                miniStat(label: "Best Streak", value: "\(metrics.longestWinStreak)W", color: .green)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func statCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func miniStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - P&L Chart

    @ViewBuilder
    private func pnlChartSection(_ metrics: TradeMetrics) -> some View {
        if !metrics.pnlByMonth.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("P&L BY MONTH")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                let maxAbs = metrics.pnlByMonth.map { abs($0.pnl) }.max() ?? 1.0

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(metrics.pnlByMonth.enumerated()), id: \.offset) { _, entry in
                            VStack(spacing: 4) {
                                if entry.pnl >= 0 {
                                    Spacer(minLength: 0)
                                    Rectangle()
                                        .fill(Color.green.opacity(0.7))
                                        .frame(width: 28, height: max(4, CGFloat(entry.pnl / maxAbs) * 60))
                                        .cornerRadius(3)
                                } else {
                                    Rectangle()
                                        .fill(Color.red.opacity(0.7))
                                        .frame(width: 28, height: max(4, CGFloat(abs(entry.pnl) / maxAbs) * 60))
                                        .cornerRadius(3)
                                    Spacer(minLength: 0)
                                }

                                Text(shortMonth(entry.month))
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)

                                Text(shortCurrency(entry.pnl))
                                    .font(.system(size: 8, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundColor(entry.pnl >= 0 ? .green : .red)
                            }
                            .frame(height: 100)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 110)
                .padding(8)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Market Breakdown

    @ViewBuilder
    private func marketBreakdownSection(_ metrics: TradeMetrics) -> some View {
        if !metrics.marketBreakdown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CATEGORY BREAKDOWN")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                let topMarkets = Array(metrics.marketBreakdown.prefix(10))

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Category")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Trades")
                            .frame(width: 45, alignment: .trailing)
                        Text("Win %")
                            .frame(width: 45, alignment: .trailing)
                        Text("P&L")
                            .frame(width: 65, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider()

                    ForEach(Array(topMarkets.enumerated()), id: \.element.id) { index, market in
                        HStack {
                            Text(market.ticker)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(market.trades)")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .frame(width: 45, alignment: .trailing)
                            Text("\(Int(market.winRate * 100))%")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .frame(width: 45, alignment: .trailing)
                            Text(market.pnl >= 0 ? "+\(market.pnl.formatted(.currency(code: "USD")))" : market.pnl.formatted(.currency(code: "USD")))
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(market.pnl >= 0 ? .green : .red)
                                .frame(width: 65, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(index % 2 == 0 ? Color.clear : Color.secondary.opacity(0.04))
                    }
                }
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Recent Trades

    @ViewBuilder
    private var recentTradesSection: some View {
        if !viewModel.fills.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT TRADES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                let recentFills = Array(viewModel.fills.sorted {
                    ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
                }.prefix(20))

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Date")
                            .frame(width: 65, alignment: .leading)
                        Text("Market")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Side")
                            .frame(width: 32, alignment: .center)
                        Text("Act")
                            .frame(width: 30, alignment: .center)
                        Text("Qty")
                            .frame(width: 28, alignment: .trailing)
                        Text("Price")
                            .frame(width: 45, alignment: .trailing)
                        Text("Fee")
                            .frame(width: 40, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider()

                    ForEach(Array(recentFills.enumerated()), id: \.element.id) { index, fill in
                        HStack {
                            Text(fill.date.map { shortDate($0) } ?? "-")
                                .font(.system(size: 10))
                                .frame(width: 65, alignment: .leading)
                            Text(fill.marketTicker)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(fill.side.prefix(1).uppercased())
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 32, alignment: .center)
                            Text(fill.action == "buy" ? "B" : "S")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(fill.action == "buy" ? .blue : .orange)
                                .frame(width: 30, alignment: .center)
                            Text("\(fill.count)")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                            Text("$\(String(format: "%.2f", Double(fill.price) / 100.0))")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .frame(width: 45, alignment: .trailing)
                            Text("$\(String(format: "%.2f", Double(fill.totalFeeVal) / 100.0))")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(index % 2 == 0 ? Color.clear : Color.secondary.opacity(0.04))
                    }
                }
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Helpers

    private func shortMonth(_ full: String) -> String {
        // "Jan 2025" -> "Jan\n25"
        let parts = full.split(separator: " ")
        if parts.count == 2 {
            return "\(parts[0])\n'\(parts[1].suffix(2))"
        }
        return full
    }

    private func shortCurrency(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        if abs(value) >= 1000 {
            return "\(sign)$\(String(format: "%.0f", value))"
        }
        return "\(sign)$\(String(format: "%.2f", value))"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

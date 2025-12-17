import SwiftUI

struct BacktestingView: View {
    @StateObject private var viewModel = BacktestingViewModel()
    
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                // Period Selector
                VStack(alignment: .leading) {
                    Text("Time Period")
                        .font(.headline)
                    Picker("Period", selection: $viewModel.selectedPeriod) {
                        Text("Last 7 Days").tag(7)
                        Text("Last 30 Days").tag(30)
                        Text("Last 90 Days").tag(90)
                    }
                    .pickerStyle(.radioGroup)
                }
                
                Divider()
                
                // Strategy Selector
                VStack(alignment: .leading) {
                    Text("Strategy")
                        .font(.headline)
                    StrategyPicker(selectedStrategy: $viewModel.selectedStrategy)
                    
                    // Show strategy details
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Take Profit:")
                            Spacer()
                            Text(viewModel.selectedStrategy.defaultTP.formatted(.percent))
                        }
                        HStack {
                            Text("Stop Loss:")
                            Spacer()
                            Text(viewModel.selectedStrategy.defaultSL.formatted(.percent))
                        }
                    }
                    .font(.caption)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                if viewModel.isRunning {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.progress)
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    Button(action: { viewModel.runBacktest() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Run Backtest")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
            .navigationTitle("Configuration")
            
        } detail: {
            VStack(spacing: 0) {
                if let error = viewModel.errorMessage {
                    // Error State
                    if #available(macOS 14.0, *) {
                        ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.red)
                            Text(error)
                                .font(.title3)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if viewModel.isRunning {
                     // Loading State in Detail View
                     VStack(spacing: 16) {
                         ProgressView()
                             .scaleEffect(1.5)
                         Text(viewModel.statusMessage)
                             .foregroundColor(.secondary)
                     }
                     .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.results.isEmpty {
                    // Empty State
                    if viewModel.hasRun {
                        // Ran but no results
                        if #available(macOS 14.0, *) {
                            ContentUnavailableView("No Trades Found", systemImage: "magnifyingglass", description: Text("No closed trades found matching your criteria.\n\(viewModel.statusMessage)"))
                        } else {
                             VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No Trades Found")
                                    .font(.title2)
                                    .bold()
                                Text("No closed trades found matching your criteria.\n\(viewModel.statusMessage)")
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        // Initial State
                        if #available(macOS 14.0, *) {
                            ContentUnavailableView("Run a Backtest", systemImage: "chart.xyaxis.line", description: Text("Select a period and strategy to simulate historical performance."))
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                VStack(spacing: 4) {
                                    Text("Run a Backtest")
                                        .font(.title2)
                                        .bold()
                                    Text("Select a period and strategy to simulate historical performance.")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        }
                    }
                } else {
                    // Dashboard
                    ScrollView {
                        VStack(spacing: 16) {
                            // Summary Cards
                            HStack(spacing: 16) {
                                SummaryCard(title: "Strategy PnL", value: viewModel.strategyPnL.formatted(.currency(code: "USD")), color: viewModel.strategyPnL >= 0 ? .green : .red)
                                SummaryCard(title: "Win Rate", value: viewModel.winRate.formatted(.percent.precision(.fractionLength(1))), color: .blue)
                                SummaryCard(title: "Total Trades", value: "\(viewModel.tradeCount)", color: .primary)
                            }
                            .padding(.horizontal)
                            
                            HStack {
                                Text("Episode Details")
                                    .font(.headline)
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            // Table
                            ResultsTable(results: viewModel.results, episodes: viewModel.episodes)
                                .frame(height: 400) // Fixed height for scrolling table
                                .padding(.horizontal)
                            
                            // Disclaimer
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                Text("Backtest uses historical mid-market prices. Actual fills may vary.")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Backtest Results")
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

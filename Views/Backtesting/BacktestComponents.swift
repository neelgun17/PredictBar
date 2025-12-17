import SwiftUI

struct SummaryCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct StrategyPicker: View {
    @Binding var selectedStrategy: StrategyType
    
    var body: some View {
        Picker("Strategy", selection: $selectedStrategy) {
            ForEach(StrategyType.allCases) { strategy in
                Text(strategy.rawValue).tag(strategy)
            }
        }
        .pickerStyle(.menu)
    }
}

struct ResultsTable: View {
    let results: [SimulationResult]
    let episodes: [TradeEpisode]
    
    var body: some View {
        Table(results) {
            TableColumn("Market") { result in
                if let ep = episodes.first(where: { $0.id == result.episodeId }) {
                    VStack(alignment: .leading) {
                        Text(ep.ticker)
                            .font(.system(size: 11, weight: .medium))
                        Text(ep.side)
                            .font(.caption2)
                            .foregroundColor(ep.side.lowercased() == "yes" ? .green : .red)
                    }
                } else {
                    Text("Unknown")
                }
            }
            .width(min: 100, max: 200)
            
            TableColumn("Entry") { result in
                 if let ep = episodes.first(where: { $0.id == result.episodeId }) {
                     VStack(alignment: .leading) {
                         Text(ep.avgEntryPrice, format: .currency(code: "USD"))
                         Text(ep.entryTime.formatted(date: .numeric, time: .shortened))
                             .font(.caption2)
                             .foregroundColor(.secondary)
                     }
                 }
            }
            .width(min: 80, max: 120)
            
            TableColumn("Exit") { result in
                VStack(alignment: .leading) {
                    Text(result.exitPrice, format: .currency(code: "USD"))
                    Text(result.reason)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(reasonColor(result.reason))
                        .cornerRadius(4)
                }
            }
            .width(min: 80, max: 120)
            
            TableColumn("PnL") { result in
                Text(result.pnl, format: .currency(code: "USD"))
                    .foregroundColor(result.pnl >= 0 ? .green : .red)
            }
            .width(min: 60, max: 100)
            
            TableColumn("ROI") { result in
                Text(result.roi.formatted(.percent.precision(.fractionLength(1))))
                    .foregroundColor(result.roi >= 0 ? .green : .red)
            }
            .width(min: 60, max: 80)
        }
    }
    
    private func reasonColor(_ reason: String) -> Color {
        switch reason {
        case "TP": return .green.opacity(0.2)
        case "SL": return .red.opacity(0.2)
        case "Time": return .orange.opacity(0.2)
        default: return .secondary.opacity(0.1)
        }
    }
}

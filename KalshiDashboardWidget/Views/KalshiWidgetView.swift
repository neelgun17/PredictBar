import SwiftUI
import WidgetKit

/// Main widget view
struct KalshiWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WidgetEntry
    
    /// Maximum positions to show based on widget size
    private var maxPositions: Int {
        switch family {
        case .systemSmall:
            return 3
        case .systemMedium, .systemLarge:
            return 5
        @unknown default:
            return 3
        }
    }
    
    var body: some View {
        if entry.positions.isEmpty {
            // No data state
            VStack(spacing: 8) {
                Image(systemName: "chart.pie")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No Positions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Display positions
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("KALSHI DASHBOARD")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                
                // Position rows
                VStack(spacing: 0) {
                    ForEach(Array(entry.positions.prefix(maxPositions))) { position in
                        PositionRowView(position: position)
                            .padding(.horizontal, 12)
                        
                        if position.id != entry.positions.prefix(maxPositions).last?.id {
                            Divider()
                                .padding(.leading, 12)
                                .opacity(0.3)
                        }
                    }
                }
                
                Spacer(minLength: 0)
                
                // Footer timestamp
                HStack {
                    Spacer()
                    Text("Updated \(entry.date, style: .time)")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.trailing, 12)
                        .padding(.bottom, 6)
                }
            }
        }
    }
}

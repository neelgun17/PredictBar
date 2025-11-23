import SwiftUI

/// Single position row for widget display
struct PositionRowView: View {
    let position: WidgetPosition
    
    var body: some View {
        HStack(spacing: 8) {
            // Left: Icon + Title + Subtitle
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(position.isPositive ? .green : .red)
                        .rotationEffect(.degrees(position.isPositive ? 0 : 180))
                    
                    Text(position.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                
                Text(position.subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            // Middle: Sparkline
            WidgetSparklineView(
                data: position.history,
                color: position.isPositive ? .green : .red
            )
            .frame(width: 40, height: 20)
            
            Spacer(minLength: 4)
            
            // Right: Price + ROI
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(position.currentPrice, specifier: "%.2f")")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                
                Text("\(position.roi >= 0 ? "+" : "")\(position.roi * 100, specifier: "%.1f")%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(position.isPositive ? .green : .red)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

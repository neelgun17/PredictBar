import SwiftUI

/// Simplified sparkline view for widget
struct WidgetSparklineView: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            
            // Handle empty or small dataset
            guard data.count >= 2 else {
                // Draw flat midline for empty data
                Path { path in
                    let midY = size.height / 2
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: size.width, y: midY))
                }
                .stroke(color.opacity(0.3), lineWidth: 1)
                return
            }
            
            // Normalize data to 0...1 range
            let minValue = data.min() ?? 0
            let maxValue = data.max() ?? 1
            let range = maxValue - minValue
            
            // Avoid division by zero
            let normalizedData: [CGFloat]
            if range > 0.001 {
                normalizedData = data.map { CGFloat(($0 - minValue) / range) }
            } else {
                // Flat line if all values are the same
                normalizedData = data.map { _ in CGFloat(0.5) }
            }
            
            // Calculate points
            let stepX = size.width / CGFloat(normalizedData.count - 1)
            let points = normalizedData.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height * (1.0 - value) // Invert Y axis
                )
            }
            
            // Draw line
            Path { path in
                guard let firstPoint = points.first else { return }
                path.move(to: firstPoint)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

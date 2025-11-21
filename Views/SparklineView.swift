import SwiftUI

struct SparklineView: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            
            // Early exit for tiny datasets
            if data.count <= 1 {
                EmptyView()
            } else {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = max(maxVal - minVal, 0.000_1)
                let stepX = size.width / CGFloat(data.count - 1)
                
                // Build points once for reuse across layers
                let points: [CGPoint] = data.enumerated().map { index, value in
                    let x = CGFloat(index) * stepX
                    let yRatio = (value - minVal) / range
                    let y = size.height - CGFloat(yRatio) * size.height
                    return CGPoint(x: x, y: y)
                }
                
                // Light fill under the line for depth
                Path { path in
                    path.move(to: points.first ?? .zero)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.25),
                            color.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Dashed baseline near the lower band to match stock-style sparklines
                let baselineValue = minVal + (range * 0.25)
                let baselineY = size.height - CGFloat((baselineValue - minVal) / range) * size.height
                
                Path { path in
                    path.move(to: CGPoint(x: 0, y: baselineY))
                    path.addLine(to: CGPoint(x: size.width, y: baselineY))
                }
                .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                
                // Primary line
                Path { path in
                    path.move(to: points.first ?? .zero)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

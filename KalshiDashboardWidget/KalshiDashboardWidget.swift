import WidgetKit
import SwiftUI

@main
struct KalshiDashboardWidget: Widget {
    let kind: String = "KalshiDashboardWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KalshiWidgetProvider()) { entry in
            KalshiWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Kalshi Dashboard")
        .description("View your top Kalshi positions at a glance")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// Preview provider for Xcode previews
struct KalshiDashboardWidget_Previews: PreviewProvider {
    static var previews: some View {
        let samplePositions = [
            WidgetPosition(
                id: "MSTA-24DEC31-B50",
                ticker: "MSTA-24DEC31-B50",
                title: "Who will win MSTA?",
                subtitle: "MSTA · 20 @ $0.24",
                currentPrice: 0.38,
                roi: 0.515,
                history: [0.24, 0.26, 0.28, 0.30, 0.32, 0.35, 0.38],
                isPositive: true
            ),
            WidgetPosition(
                id: "DMAY-24DEC31-B40",
                ticker: "DMAY-24DEC31-B40",
                title: "Who will win DMAY?",
                subtitle: "DMAY · 20 @ $0.23",
                currentPrice: 0.31,
                roi: 0.283,
                history: [0.23, 0.24, 0.25, 0.27, 0.29, 0.30, 0.31],
                isPositive: true
            )
        ]
        
        let entry = WidgetEntry(date: Date(), positions: samplePositions)
        
        Group {
            KalshiWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            KalshiWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}

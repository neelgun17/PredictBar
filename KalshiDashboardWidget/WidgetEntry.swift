import WidgetKit
import SwiftUI

/// Timeline entry for the Kalshi widget
struct WidgetEntry: TimelineEntry {
    let date: Date
    let positions: [WidgetPosition]
    
    static var placeholder: WidgetEntry {
        WidgetEntry(date: Date(), positions: [])
    }
}

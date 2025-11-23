import WidgetKit
import SwiftUI

/// Timeline provider for Kalshi Dashboard widget
struct KalshiWidgetProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> WidgetEntry {
        // Return a placeholder entry for the widget gallery
        WidgetEntry.placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        // For widget preview - load current data or use placeholder
        if let snapshot = widgetDataStore.loadSnapshot() {
            let entry = WidgetEntry(date: snapshot.lastUpdate, positions: snapshot.positions)
            completion(entry)
        } else {
            completion(WidgetEntry.placeholder)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        // Load portfolio snapshot from shared container
        let currentDate = Date()
        
        if let snapshot = WidgetDataStore.shared.loadSnapshot() {
            let entry = WidgetEntry(date: currentDate, positions: snapshot.positions)
            
            // Schedule next update in 5 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            
            completion(timeline)
        } else {
            // No data available - show placeholder and retry in 1 minute
            let entry = WidgetEntry.placeholder
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            
            completion(timeline)
        }
    }
}

import SwiftUI
import UserNotifications

@main
struct KalshiMenuBarApp: App {
    @StateObject private var dashboardViewModel = DashboardViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            DropdownView(viewModel: dashboardViewModel)
                .onAppear {
                    print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
//                     UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                }
        } label: {
            MenuBarIconView(viewModel: dashboardViewModel)
        }
        .menuBarExtraStyle(.window) // Allows for complex SwiftUI views in the dropdown
    }
}

import SwiftUI
import UserNotifications

@main
struct KalshiMenuBarApp: App {
    @StateObject private var dashboardViewModel = DashboardViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            DropdownView(viewModel: dashboardViewModel)
                .onAppear {
                    if Bundle.main.bundleURL.pathExtension == "app" {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                    } else {
                        print("WARNING: App is not running inside a .app bundle. Notifications are disabled to prevent crashes.")
                    }
                }
        } label: {
            MenuBarIconView(viewModel: dashboardViewModel)
        }
        .menuBarExtraStyle(.window) // Allows for complex SwiftUI views in the dropdown
    }
}

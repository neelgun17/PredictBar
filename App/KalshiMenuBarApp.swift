import SwiftUI
import UserNotifications

@main
struct PredictBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @AppStorage("appearanceMode") private var appearanceMode: String = "System"
    
    private static func setSharedViewModel(_ vm: DashboardViewModel) {
        DashboardViewModel.shared = vm
    }

    var body: some Scene {
        let _ = Self.setSharedViewModel(dashboardViewModel)
        MenuBarExtra {
            DropdownView(viewModel: dashboardViewModel)
                .applyAppearance(appearanceMode)
        } label: {
            MenuBarIconView(viewModel: dashboardViewModel)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView(dashboardViewModel: dashboardViewModel)
                .applyAppearance(appearanceMode)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only setup notifications when running as a proper app bundle
        if let icon = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "App Icon") {
            // Tint it to match the app's accent color/theme if possible, or just use default
            // SF Symbols are template images, so we might need to config them.
            // Let's try simple first.
            NSApplication.shared.applicationIconImage = icon
        }

        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    
    // Handle notification click
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Extract ticker from title or body if needed, but easier if we attach it to userInfo
        // Try to open the URL from the notification payload
        
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: Open homepage
            if let url = URL(string: "https://kalshi.com") {
                NSWorkspace.shared.open(url)
            }
        }
        
        completionHandler()
    }
    
    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

extension View {
    @ViewBuilder
    func applyAppearance(_ mode: String) -> some View {
        switch mode {
        case "Light": self.environment(\.colorScheme, .light)
        case "Dark": self.environment(\.colorScheme, .dark)
        default: self
        }
    }
}

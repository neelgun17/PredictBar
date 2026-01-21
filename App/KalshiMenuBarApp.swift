import SwiftUI
import UserNotifications

@main
struct KalshiMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @AppStorage("appearanceMode") private var appearanceMode: String = "System"
    
    var body: some Scene {
        MenuBarExtra {
            DropdownView(viewModel: dashboardViewModel)
                .applyAppearance(appearanceMode)
        } label: {
            MenuBarIconView(viewModel: dashboardViewModel)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .applyAppearance(appearanceMode)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only setup notifications when running as a proper app bundle
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
        // For now, let's just open the main Kalshi site or try to parse the ticker
        // Ideally, we should pass the URL in the notification payload
        
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: Open Kalshi homepage
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

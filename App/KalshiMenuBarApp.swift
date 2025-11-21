import SwiftUI
import UserNotifications

@main
struct KalshiMenuBarApp: App {
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @AppStorage("appearanceMode") private var appearanceMode: String = "System"
    
    var body: some Scene {
        MenuBarExtra {
            DropdownView(viewModel: dashboardViewModel)
                .applyAppearance(appearanceMode)
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
        
        Settings {
            SettingsView()
                .applyAppearance(appearanceMode)
        }
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

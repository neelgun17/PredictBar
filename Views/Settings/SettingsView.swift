import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            DisplaySettingsView()
                .tabItem {
                    Label("Display", systemImage: "display")
                }
            
            NotificationSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
            
            APISettingsView()
                .tabItem {
                    Label("API", systemImage: "network")
                }
        }
        .frame(width: 450, height: 250)
        .padding()
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

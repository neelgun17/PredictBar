import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsViewModel = SettingsViewModel.shared
    var dashboardViewModel: DashboardViewModel?

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

            if let vm = dashboardViewModel ?? DashboardViewModel.shared {
                PerformanceView(viewModel: vm)
                    .tabItem {
                        Label("Performance", systemImage: "chart.bar.fill")
                    }
            }
        }
        .frame(width: 550, height: 450)
        .padding()
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

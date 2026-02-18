import SwiftUI
import AppKit
import Combine

/// Opens the SwiftUI Settings view even when the app isn't running from a `.app` bundle.
/// This provides a manual fallback for menu bar builds launched via `swift run` or other CLI entrypoints.
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Observe appearance changes
        SettingsViewModel.shared.$appearanceMode
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateWindowAppearance()
                }
            }
            .store(in: &cancellables)
    }
    
    func open() {
        if window == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView(dashboardViewModel: DashboardViewModel.shared)
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentViewController = hostingController
            
            self.window = window
        }
        
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        
        // Ensure window appearance matches preference
        updateWindowAppearance()
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func updateWindowAppearance() {
        let mode = SettingsViewModel.shared.appearanceMode
        switch mode {
        case "Light":
            window?.appearance = NSAppearance(named: .aqua)
        case "Dark":
            window?.appearance = NSAppearance(named: .darkAqua)
        default:
            window?.appearance = nil // System
        }
    }
}

import SwiftUI
import AppKit

/// Opens the SwiftUI Settings view even when the app isn't running from a `.app` bundle.
/// This provides a manual fallback for menu bar builds launched via `swift run` or other CLI entrypoints.
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    
    private init() {}
    
    func open() {
        if window == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView()
                    .applyAppearance(SettingsViewModel.shared.appearanceMode)
            )
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 260),
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
        NSApp.activate(ignoringOtherApps: true)
    }
}

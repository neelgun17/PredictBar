import SwiftUI
import AppKit

struct MenuBarIconView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: Self.glyph)
                .renderingMode(.template)
            if !viewModel.menuBarText.isEmpty {
                Text(viewModel.menuBarText)
                    .monospacedDigit()
            }
        }
    }

    /// Custom menu-bar glyph loaded from the app bundle. It's a template image, so
    /// macOS recolors it to match light/dark menu bars automatically. Falls back to
    /// an SF Symbol when the resource isn't present (e.g. the unbundled debug binary).
    private static let glyph: NSImage = {
        if let resources = Bundle.main.resourcePath {
            let path = resources + "/MenuBarGlyph.png"
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                img.isTemplate = true
                let h: CGFloat = 16
                let w = h * (img.size.width / max(img.size.height, 1))
                img.size = NSSize(width: w, height: h)
                return img
            }
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        return NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "PredictBar")?
            .withSymbolConfiguration(cfg) ?? NSImage()
    }()
}

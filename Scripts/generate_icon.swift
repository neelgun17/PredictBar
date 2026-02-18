#!/usr/bin/env swift
// Generates AppIcon.icns from the SF Symbol "chart.pie"
// Run: swift generate_icon.swift

import AppKit

let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

// Create temporary iconset directory
let iconsetPath = "/tmp/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Background: rounded rect with gradient
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.2
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Dark blue-to-teal gradient
    let gradient = NSGradient(colors: [
        NSColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1.0),
        NSColor(red: 0.1, green: 0.25, blue: 0.4, alpha: 1.0),
    ])!
    gradient.draw(in: path, angle: -45)

    // Draw SF Symbol
    let symbolSize = size * 0.55
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let x = (size - symbolSize.width) / 2
        let y = (size - symbolSize.height) / 2
        NSColor.white.setFill()
        symbol.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()

    // Save as PNG
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to render \(name)")
        continue
    }
    try png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}

// Convert iconset to icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", "Resources/AppIcon.icns"]

// Ensure Resources directory exists
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)

try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("✅ Created Resources/AppIcon.icns")
} else {
    print("❌ iconutil failed with status \(process.terminationStatus)")
}

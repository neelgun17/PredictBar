// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KalshiMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "KalshiMenuBar",
            targets: ["KalshiMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "KalshiMenuBar",
            path: ".",
            sources: [
                "App",
                "Models",
                "Services",
                "ViewModels",
                "Views",
                "Utilities"
            ]
        )
    ]
)

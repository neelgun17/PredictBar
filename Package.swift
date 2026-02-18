// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PredictBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PredictBar",
            targets: ["PredictBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PredictBar",
            path: ".",
            exclude: [
                "Resources",
                "Scripts",
                ".github",
                "Info.plist",
                "PredictBar.entitlements",
                "Makefile",
                "restart.sh",
                "README.md",
                "CONTRIBUTING.md",
                "SECURITY.md",
                "CLAUDE.md",
                "LICENSE"
            ],
            sources: [
                "App",
                "Models",
                "Services",
                "ViewModels",
                "Views",
                "Utilities"
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"])
            ]
        )
    ]
)

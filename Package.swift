// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceSearchCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "VoiceSearchCore",
            targets: ["VoiceSearchCore"]
        ),
        .executable(
            name: "VoiceSearchApp",
            targets: ["VoiceSearchApp"]
        ),
    ],
    targets: [
        .target(
            name: "VoiceSearchCore"
        ),
        .executableTarget(
            name: "VoiceSearchApp",
            dependencies: ["VoiceSearchCore"],
            linkerSettings: [
                .linkedFramework("AVKit"),
            ]
        ),
        .testTarget(
            name: "VoiceSearchCoreTests",
            dependencies: ["VoiceSearchCore"]
        ),
    ]
)

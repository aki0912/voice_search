// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let voiceSearchCLIInfoPlistPath = "AppResources/CLIInfo.plist"

let package = Package(
    name: "VoiceSearchCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "VoiceSearchCore",
            targets: ["VoiceSearchCore"]
        ),
        .library(
            name: "VoiceSearchServices",
            targets: ["VoiceSearchServices"]
        ),
        .executable(
            name: "VoiceSearchApp",
            targets: ["VoiceSearchApp"]
        ),
        .executable(
            name: "VoiceSearchCLI",
            targets: ["VoiceSearchCLI"]
        ),
    ],
    targets: [
        .target(
            name: "VoiceSearchCore"
        ),
        .target(
            name: "VoiceSearchServices",
            dependencies: ["VoiceSearchCore"],
            path: "Sources/VoiceSearchApp/Services"
        ),
        .executableTarget(
            name: "VoiceSearchApp",
            dependencies: ["VoiceSearchCore", "VoiceSearchServices"],
            exclude: ["Services"],
            linkerSettings: [
                .linkedFramework("AVKit"),
            ]
        ),
        .executableTarget(
            name: "VoiceSearchCLI",
            dependencies: ["VoiceSearchCore", "VoiceSearchServices"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", voiceSearchCLIInfoPlistPath,
                ]),
            ]
        ),
        .testTarget(
            name: "VoiceSearchCoreTests",
            dependencies: ["VoiceSearchCore"]
        ),
        .testTarget(
            name: "VoiceSearchServicesTests",
            dependencies: ["VoiceSearchServices", "VoiceSearchCore"]
        ),
    ]
)

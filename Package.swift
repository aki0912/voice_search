// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let voiceSearchCLIInfoPlistPath = "AppResources/CLIInfo.plist"
let voiceSearchAppInfoPlistPath = "AppResources/Info.plist"

let package = Package(
    name: "VoiceSearchCore",
    defaultLocalization: "ja",
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
            name: "VoiceSearchCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "VoiceSearchServices",
            dependencies: ["VoiceSearchCore"],
            path: "Sources/VoiceSearchApp/Services",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "VoiceSearchApp",
            dependencies: ["VoiceSearchCore", "VoiceSearchServices"],
            exclude: ["Services"],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AVKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", voiceSearchAppInfoPlistPath,
                ]),
            ]
        ),
        .executableTarget(
            name: "VoiceSearchCLI",
            dependencies: ["VoiceSearchCore", "VoiceSearchServices"],
            resources: [
                .process("Resources"),
            ],
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
        .testTarget(
            name: "VoiceSearchAppTests",
            dependencies: ["VoiceSearchApp", "VoiceSearchCore"]
        ),
    ]
)

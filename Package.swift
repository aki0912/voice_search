// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let voiceSearchAppInfoPlistPath = "AppResources/Info.plist"

let package = Package(
    name: "VoiceSearch",
    defaultLocalization: "ja",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "VoiceSearchApp",
            targets: ["VoiceSearchApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "VoiceSearchApp",
            path: "VoiceSearch/VoiceSearch",
            exclude: [
                "Assets.xcassets",
            ],
            resources: [
                .process("Resources"),
                .process("en.lproj"),
                .process("ja.lproj"),
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
        .testTarget(
            name: "VoiceSearchTests",
            dependencies: ["VoiceSearchApp"],
            path: "VoiceSearch/VoiceSearchTests"
        ),
    ]
)

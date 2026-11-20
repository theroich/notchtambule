// swift-tools-version: 6.0
//
//  Package.swift
//  NotchTubeAudio
//
//  Created by NotchTubeAudio.
//

import PackageDescription

let package = Package(
    name: "NotchTubeAudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "NotchTubeAudio",
            targets: ["NotchTubeAudio"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/MrKai77/DynamicNotchKit",
            .upToNextMinor(from: "1.1.0")
        )
    ],
    targets: [
        .executableTarget(
            name: "NotchTubeAudio",
            dependencies: [
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit")
            ],
            path: "Sources/NotchTubeAudio",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "NotchTubeAudioTests",
            dependencies: ["NotchTubeAudio"],
            path: "Tests/NotchTubeAudioTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

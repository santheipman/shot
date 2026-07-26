// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Shot",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Shot", targets: ["Shot"]),
    ],
    targets: [
        .executableTarget(
            name: "Shot",
            path: "Sources/Shot",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "ShotTests",
            dependencies: ["Shot"],
            path: "Tests/ShotTests"
        ),
    ]
)

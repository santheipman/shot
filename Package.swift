// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AeroShot",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "AeroShot", targets: ["AeroShot"]),
    ],
    targets: [
        .executableTarget(
            name: "AeroShot",
            path: "Sources/AeroShot",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "AeroShotTests",
            dependencies: ["AeroShot"],
            path: "Tests/AeroShotTests"
        ),
    ]
)

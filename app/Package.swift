// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RadioMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RadioMenuBar", targets: ["RadioMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "RadioMenuBar",
            path: "Sources/RadioMenuBar"
        )
    ]
)

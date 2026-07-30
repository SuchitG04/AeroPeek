// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AeroPeek",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AeroPeek", targets: ["AeroPeek"])
    ],
    targets: [
        .executableTarget(
            name: "AeroPeek",
            path: "Sources/AeroPeek"
        )
    ]
)

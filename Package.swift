// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Cadence",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cadence", targets: ["Cadence"])
    ],
    targets: [
        .executableTarget(name: "Cadence"),
        .testTarget(name: "CadenceTests", dependencies: ["Cadence"], resources: [.copy("Fixtures")])
    ]
)

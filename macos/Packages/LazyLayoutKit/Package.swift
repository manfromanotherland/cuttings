// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LazyLayoutKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "LazyLayoutKit", targets: ["LazyLayoutKit"])],
    targets: [
        .target(name: "LazyLayoutKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "LazyLayoutKitTests",
            dependencies: ["LazyLayoutKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

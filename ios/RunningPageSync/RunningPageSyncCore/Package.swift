// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RunningPageSyncCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "RunningPageSyncCore",
            targets: ["RunningPageSyncCore"]
        )
    ],
    targets: [
        .target(name: "RunningPageSyncCore"),
        .testTarget(
            name: "RunningPageSyncCoreTests",
            dependencies: ["RunningPageSyncCore"]
        )
    ]
)

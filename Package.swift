// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BTNotify",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BTNotify", targets: ["BTNotify"]),
        .library(name: "BTNotifyCore", targets: ["BTNotifyCore"])
    ],
    targets: [
        .target(name: "BTNotifyCore"),
        .executableTarget(name: "BTNotify", dependencies: ["BTNotifyCore"]),
        .testTarget(name: "BTNotifyCoreTests", dependencies: ["BTNotifyCore"])
    ]
)

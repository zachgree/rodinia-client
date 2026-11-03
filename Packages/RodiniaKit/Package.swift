// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RodiniaKit",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "RodiniaKit", targets: ["RodiniaKit"]),
    ],
    targets: [
        .target(name: "RodiniaKit"),
        .testTarget(name: "RodiniaKitTests", dependencies: ["RodiniaKit"]),
    ]
)

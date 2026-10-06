// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FolkeCore",
    defaultLocalization: "da",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FolkeCore", targets: ["FolkeCore"]),
    ],
    targets: [
        .target(name: "FolkeCore"),
        .testTarget(name: "FolkeCoreTests", dependencies: ["FolkeCore"]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LayerHop",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "LayerHop", targets: ["LayerHop"]),
    ],
    targets: [
        .target(name: "LayerHop"),
        .testTarget(name: "LayerHopTests", dependencies: ["LayerHop"]),
    ],
    swiftLanguageVersions: [.v5]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BirdCount",
    platforms: [ .iOS(.v16) ],
    products: [
        .library(name: "BirdCount", targets: ["BirdCount"]),
    ],
    targets: [
        .target(name: "BirdCount"),
        .testTarget(name: "BirdCountTests", dependencies: ["BirdCount"])
    ]
)

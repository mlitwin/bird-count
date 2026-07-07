// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BirdCount",
    // Keep SPM platform at a supported level for PackageDescription 5.10; Xcode target controls actual app deployment (18.5)
    platforms: [ .iOS(.v16) ],
    products: [
        .library(name: "BirdCount", targets: ["BirdCount"]),
    ],
    targets: [
        .target(name: "BirdCount"),
        .testTarget(name: "BirdCountTests", dependencies: ["BirdCount"])
    ]
)

// swift-tools-version: 5.10
// SPM manifest for the platform-neutral core ONLY (fast `swift test` from
// the CLI). The app itself builds via XcodeGen (`make generate`) — this
// target mirrors the BirdCountCore target in project.yml (Models + Stores,
// minus iOS-only LocationManager); keep the two in sync.
import PackageDescription

let package = Package(
    name: "BirdCountCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [
        .library(name: "BirdCountCore", targets: ["BirdCountCore"]),
    ],
    targets: [
        .target(
            name: "BirdCountCore",
            path: "BirdCount",
            exclude: ["Stores/LocationManager.swift"],
            sources: ["Models", "Stores"]
        ),
        .testTarget(
            name: "BirdCountCoreTests",
            dependencies: ["BirdCountCore"],
            path: "TestsCore"
        ),
    ]
)

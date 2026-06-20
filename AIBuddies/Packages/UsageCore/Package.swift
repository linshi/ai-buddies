// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "usage-cli", targets: ["UsageCLI"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "UsageCLI", dependencies: ["UsageCore"]),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

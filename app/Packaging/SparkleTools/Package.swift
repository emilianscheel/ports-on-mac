// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SparkleTools",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "SparkleTools",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
    ]
)

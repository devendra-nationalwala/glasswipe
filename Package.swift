// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Glasswipe",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Glasswipe", targets: ["Glasswipe"]),
        .library(name: "GlasswipeCore", targets: ["GlasswipeCore"]),
    ],
    targets: [
        .target(
            name: "GlasswipeCore",
            resources: [.copy("Resources/junk-rules.json")]
        ),
        .executableTarget(
            name: "Glasswipe",
            dependencies: ["GlasswipeCore"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "GlasswipeCoreTests",
            dependencies: ["GlasswipeCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

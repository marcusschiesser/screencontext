// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenContext",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ScreenContext", targets: ["ScreenContext"]),
        .library(name: "ScreenContextCore", targets: ["ScreenContextCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift.git", exact: "2.2.5"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", exact: "3.69.8"),
    ],
    targets: [
        .target(
            name: "ScreenContextCore",
            dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit.swift"),
            ],
            resources: [.copy("Resources/Templates")]
        ),
        .executableTarget(
            name: "ScreenContext",
            dependencies: [
                "ScreenContextCore",
                .product(name: "PostHog", package: "posthog-ios"),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "LocalizationValidationPlugin")]
        ),
        .executableTarget(
            name: "LocalizationValidator",
            path: "Tools/LocalizationValidator"
        ),
        .plugin(
            name: "LocalizationValidationPlugin",
            capability: .buildTool(),
            dependencies: ["LocalizationValidator"]
        ),
        .testTarget(
            name: "ScreenContextCoreTests",
            dependencies: ["ScreenContextCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

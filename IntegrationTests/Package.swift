// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenContextIntegrationTests",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "ScreenContext", path: ".."),
    ],
    targets: [
        .testTarget(
            name: "ScreenContextIntegrationTests",
            dependencies: [
                .product(name: "ScreenContextCore", package: "ScreenContext"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

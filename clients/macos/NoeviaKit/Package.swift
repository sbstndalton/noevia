// swift-tools-version:6.0
// NoeviaKit: the typed core API client for the native macOS client (#273, first slice).
// Swift 6 language mode (complete strict concurrency) is the default for tools 6.0.
import PackageDescription

let package = Package(
    name: "NoeviaKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NoeviaKit", targets: ["NoeviaKit"]),
    ],
    targets: [
        .target(
            name: "NoeviaKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NoeviaKitTests",
            dependencies: ["NoeviaKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

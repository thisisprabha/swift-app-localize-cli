// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "i18n-cli",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Matches Apple Swift 6.2 toolchains.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .executableTarget(
            name: "i18n-cli",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "i18n-cliTests",
            dependencies: ["i18n-cli"]
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwistPad",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TwistPad",
            path: "Sources/TwistPad",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

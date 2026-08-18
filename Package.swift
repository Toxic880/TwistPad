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
        ),
        // The gesture gates decide whether a touch is a twist or a scroll, and
        // getting that wrong is the whole failure mode of the app. They take
        // plain structs in and call a delegate out, so they can be driven
        // frame by frame without a trackpad.
        .testTarget(
            name: "TwistPadTests",
            dependencies: ["TwistPad"],
            path: "Tests/TwistPadTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

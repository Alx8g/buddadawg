// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Buddadawg",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "BarkCore", swiftSettings: [.define("ACCELERATE_NEW_LAPACK")], linkerSettings: [.linkedFramework("Accelerate"), .linkedFramework("CoreML")]),
        .executableTarget(name: "BarkBench", dependencies: ["BarkCore"]),
        .executableTarget(name: "Buddadawg", dependencies: ["BarkCore"]),
    ],
    swiftLanguageModes: [.v5]  // AppKit + event-tap callbacks; strict Swift 6 isolation adds noise without benefit here
)

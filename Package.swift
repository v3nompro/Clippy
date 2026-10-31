// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Clippy", targets: ["Clippy"])],
    targets: [
        .target(name: "ClippyCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Clippy", dependencies: ["ClippyCore"]),
        .executableTarget(name: "ClippyChecks", dependencies: ["ClippyCore"], path: "Tests/ClippyCoreTests")
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlodoOpen",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "FlodoOpen", targets: ["FlodoOpen"]),
        .executable(name: "flowctl", targets: ["flowctl"]),
        .library(name: "FlowCore", targets: ["FlowCore"])
    ],
    targets: [
        .target(name: "FlowCore"),
        .executableTarget(name: "FlodoOpen", dependencies: ["FlowCore"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "flowctl", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
        .testTarget(name: "AppTests", dependencies: ["FlodoOpen", "FlowCore"])
    ],
    swiftLanguageModes: [.v5]
)

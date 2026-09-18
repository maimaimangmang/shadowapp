// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexMulti",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexMulti", targets: ["CodexMulti"]),
        .library(name: "CodexMultiCore", targets: ["CodexMultiCore"])
    ],
    targets: [
        .target(name: "CodexMultiCore"),
        .executableTarget(name: "CodexMulti", dependencies: ["CodexMultiCore"]),
        .executableTarget(name: "CodexMultiTests", dependencies: ["CodexMultiCore"], path: "Tests/CodexMultiCoreTests")
    ]
)

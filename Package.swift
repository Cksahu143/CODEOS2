// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "CodeOS",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodeOS", targets: ["CodeOSApp"]),
        .library(name: "CodeOSCore", targets: ["CodeOSCore"])
    ],
    targets: [
        .target(name: "CodeOSCore", path: "Sources/CodeOSCore"),
        .executableTarget(name: "CodeOSApp", dependencies: ["CodeOSCore"], path: "Sources/CodeOSApp"),
        .testTarget(name: "CodeOSCoreTests", dependencies: ["CodeOSCore"], path: "Tests/CodeOSCoreTests")
    ]
)

// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "CodeOS",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodeOS", targets: ["CodeOSApp"]),
        .executable(name: "codeos-fanctl", targets: ["CodeOSFanHelper"]),
        .library(name: "CodeOSCore", targets: ["CodeOSCore"])
    ],
    targets: [
        .target(name: "CodeOSCore", path: "Sources/CodeOSCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "CodeOSApp", dependencies: ["CodeOSCore"], path: "Sources/CodeOSApp",
                          linkerSettings: [.linkedFramework("QuickLookUI")]),
        .executableTarget(name: "CodeOSFanHelper", dependencies: ["CodeOSCore"], path: "Sources/CodeOSFanHelper"),
        .testTarget(name: "CodeOSCoreTests", dependencies: ["CodeOSCore"], path: "Tests/CodeOSCoreTests")
    ]
)

// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "CodeOS",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.0"),
    ],
    products: [
        .executable(name: "CodeOS", targets: ["CodeOSApp"]),
        .executable(name: "codeos-fanctl", targets: ["CodeOSFanHelper"]),
        .library(name: "CodeOSCore", targets: ["CodeOSCore"])
    ],
    targets: [
        .target(name: "CodeOSCore", path: "Sources/CodeOSCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "CodeOSApp", dependencies: ["CodeOSCore", .product(name: "SwiftTerm", package: "SwiftTerm")], path: "Sources/CodeOSApp",
                          linkerSettings: [.linkedFramework("QuickLookUI")]),
        .executableTarget(name: "CodeOSFanHelper", dependencies: ["CodeOSCore"], path: "Sources/CodeOSFanHelper"),
        .testTarget(name: "CodeOSCoreTests", dependencies: ["CodeOSCore"], path: "Tests/CodeOSCoreTests")
    ]
)

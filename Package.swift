// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CVEtool",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CVEtoolCore", targets: ["CVEtoolCore"]),
        .executable(name: "CVEtool", targets: ["CVEtoolApp"]),
    ],
    targets: [
        .target(name: "CVEtoolCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "CVEtoolApp", dependencies: ["CVEtoolCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CVEtoolCoreTests", dependencies: ["CVEtoolCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CVEtoolAppTests", dependencies: ["CVEtoolApp"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Veylume",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VeylumeCore", targets: ["VeylumeCore"]),
        .library(name: "VeylumeKit", targets: ["VeylumeKit"]),
        .executable(name: "Veylume", targets: ["Veylume"]),
        .executable(name: "VeylumeVerify", targets: ["VeylumeVerify"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "c8b41f98eae668794dd0083bbe028fe7e6585051", traits: []),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", revision: "1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "VeylumeCore", dependencies: ["CSQLite"], path: "Veylume/Core"),
        .target(name: "VeylumeKit", dependencies: [
            "VeylumeCore", .product(name: "FluidAudio", package: "FluidAudio"),
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
            .product(name: "Sparkle", package: "Sparkle")
        ], path: "Veylume/Kit", resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Veylume", dependencies: ["VeylumeKit"], path: "Veylume/App"),
        .executableTarget(name: "VeylumeVerify", dependencies: ["VeylumeKit"], path: "Tools/Verify"),
        .testTarget(name: "VeylumeCoreTests", dependencies: ["VeylumeCore", "CSQLite"], path: "VeylumeTests/Core"),
        .testTarget(name: "VeylumeSystemTests", dependencies: ["VeylumeKit"], path: "VeylumeTests/System", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)

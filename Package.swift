// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AntiFish",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AntiFishCore", targets: ["AntiFishCore"]),
        .executable(name: "antifish", targets: ["antifish"]),
        .executable(name: "AntiFishApp", targets: ["AntiFishApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx.git", exact: "1.13.8"),
    ],
    targets: [
        .target(
            name: "AntiFishCore",
            dependencies: [.product(name: "sherpa-onnx", package: "sherpa-onnx")],
            path: "AntiFishCore/Sources/AntiFishCore",
            linkerSettings: [.linkedLibrary("c++"), .linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "antifish",
            dependencies: ["AntiFishCore"],
            path: "AntiFishCore/Sources/antifish"
        ),
        .executableTarget(
            name: "AntiFishApp",
            dependencies: ["AntiFishCore"],
            path: "AntiFish",
            exclude: ["Resources", "App/Info.plist", "App/AntiFish.entitlements", "App/AntiFish-Debug.entitlements"]
        ),
        .testTarget(
            name: "AntiFishCoreTests",
            dependencies: ["AntiFishCore"],
            path: "AntiFishCore/Tests/AntiFishCoreTests"
        ),
    ]
)

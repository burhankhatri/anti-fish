// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AntiFishCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AntiFishCore", targets: ["AntiFishCore"]),
        .executable(name: "antifish", targets: ["antifish"]),
    ],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx.git", exact: "1.13.8"),
    ],
    targets: [
        .target(
            name: "AntiFishCore",
            dependencies: [
                .product(name: "sherpa-onnx", package: "sherpa-onnx"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(name: "antifish", dependencies: ["AntiFishCore"]),
        .testTarget(name: "AntiFishCoreTests", dependencies: ["AntiFishCore"]),
    ]
)

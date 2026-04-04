// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vaakya",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.18.0"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.17.0"),
    ],
    targets: [
        .executableTarget(
            name: "Vaakya",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "SpeakerKit", package: "WhisperKit"),
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            path: "Sources",
            exclude: ["Resources"]
        )
    ]
)

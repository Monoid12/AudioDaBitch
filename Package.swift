// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioDaBitch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AudioDaBitch", targets: ["AudioDaBitchApp"])],
    targets: [.executableTarget(name: "AudioDaBitchApp", path: "Sources/AudioDaBitchApp")]
)

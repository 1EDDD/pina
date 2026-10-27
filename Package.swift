// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PinaTVLab",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "PinaTVLab", targets: ["PinaTVLab"])],
    targets: [
        .target(name: "PinaTVLab", path: "Sources"),
        .testTarget(name: "PinaTVLabTests", dependencies: ["PinaTVLab"], path: "Tests/PinaTVLabTests")
    ]
)

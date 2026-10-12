// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenGymKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "OpenGymKit", targets: ["OpenGymKit"])],
    targets: [
        .target(name: "OpenGymKit"),
        .testTarget(name: "OpenGymKitTests", dependencies: ["OpenGymKit"], resources: [.process("Fixtures")])
    ]
)

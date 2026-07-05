// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RoarFareCore",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "RoarFareCore", targets: ["RoarFareCore"])
    ],
    targets: [
        .target(
            name: "RoarFareCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RoarFareCoreTests",
            dependencies: ["RoarFareCore"]
        )
    ]
)

// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "FanMaster",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "fanmaster", targets: ["FanMaster"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FanMaster",
            dependencies: ["FanMasterCore"],
            path: "Sources/FanMaster"
        ),
        .target(
            name: "FanMasterCore",
            dependencies: [],
            path: "Sources/FanMasterCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UnifiedBuds",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "UnifiedBuds",
            path: "Sources/UnifiedBuds",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)

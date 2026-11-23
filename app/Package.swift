// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SpyWater",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SpyWater",
            path: "Sources/SpyWater",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)

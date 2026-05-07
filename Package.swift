// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Minmeta",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Minmeta",
            path: "Sources/Minmeta"
        )
    ]
)

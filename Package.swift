// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Todone",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Todone",
            path: "Sources",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)

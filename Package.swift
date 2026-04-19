// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Todone",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Todone",
            path: "Sources",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "TodoneTests",
            dependencies: ["Todone"],
            path: "Tests"
        ),
    ]
)

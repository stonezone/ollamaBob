// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OllamaBob",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    ],
    targets: [
        .executableTarget(
            name: "OllamaBob",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "OllamaBob",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "OllamaBobTests",
            dependencies: [
                "OllamaBob",
            ],
            path: "Tests/OllamaBobTests"
        ),
    ]
)

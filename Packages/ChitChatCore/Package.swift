// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChitChatCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChitChatCore", targets: ["ChitChatCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "ChitChatCore",
            dependencies: ["SwiftWhisper"]
        ),
        .testTarget(
            name: "ChitChatCoreTests",
            dependencies: ["ChitChatCore"]
        ),
    ]
)

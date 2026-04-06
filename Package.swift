// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeMonitor", targets: ["ClaudeMonitor"]),
        .executable(name: "claude-monitor-bridge", targets: ["Bridge"]),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeMonitor",
            path: "Sources/ClaudeMonitor"
        ),
        .executableTarget(
            name: "Bridge",
            path: "Sources/Bridge"
        ),
    ]
)

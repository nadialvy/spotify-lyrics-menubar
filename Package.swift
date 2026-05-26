// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LyricsMenuBar",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "LyricsMenuBar"),
        .testTarget(name: "LyricsMenuBarTests", dependencies: ["LyricsMenuBar"])
    ]
)

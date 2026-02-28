// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VividTeam",
    platforms: [
        .macOS(.v14)   // @Observable requires macOS 14+
    ],
    targets: [
        .executableTarget(
            name: "VividTeam",
            path: "VividTeam",
            exclude: ["Info.plist"],
            resources: [
                .copy("study-buddy-icon.png"),
                .copy("news-anchor-icon.png")
            ]
        )
    ]
)

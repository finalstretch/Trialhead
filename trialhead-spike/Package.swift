// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrialheadSpike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TrialheadSpike", path: "Sources/TrialheadSpike")
    ]
)

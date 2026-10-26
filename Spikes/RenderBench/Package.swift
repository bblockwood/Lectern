// swift-tools-version: 6.0
// Spike C: render benchmark (SPEC §11 M0). Throwaway; never shipped.
import PackageDescription

let package = Package(
    name: "RenderBench",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "RenderBench",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

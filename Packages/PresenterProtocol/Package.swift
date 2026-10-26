// swift-tools-version: 6.0
// PresenterProtocol: Foundation-only types shared by the host apps and the remotes.
// Must build for watchOS. No other imports.
import PackageDescription

let package = Package(
    name: "PresenterProtocol",
    platforms: [.macOS("26.0"), .iOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "PresenterProtocol", targets: ["PresenterProtocol"])
    ],
    targets: [
        .target(name: "PresenterProtocol", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "PresenterProtocolTests", dependencies: ["PresenterProtocol"], swiftSettings: [.swiftLanguageMode(.v6)])
    ]
)

// swift-tools-version: 6.0
// PresenterCore: the platform-independent heart of Lectern (SPEC §3.1).
// Imports only Foundation, CoreGraphics, PDFKit, os (logging/signposts) and PresenterProtocol.
import PackageDescription

let package = Package(
    name: "PresenterCore",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "PresenterCore", targets: ["PresenterCore"])
    ],
    dependencies: [
        .package(path: "../PresenterProtocol")
    ],
    targets: [
        .target(
            name: "PresenterCore",
            dependencies: [.product(name: "PresenterProtocol", package: "PresenterProtocol")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PresenterCoreTests",
            dependencies: ["PresenterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

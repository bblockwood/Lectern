import Foundation

/// Locates the repo's Fixtures/ directory relative to this source file.
enum Fixtures {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        // Packages/PresenterCore/Tests/PresenterCoreTests/Fixtures.swift -> repo root
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Fixtures")
    }()

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
}

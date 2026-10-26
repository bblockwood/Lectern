import Foundation
import os

/// Reads and writes the sidecar next to the deck when that directory is writable, otherwise in the app's
/// Application Support keyed by a stable hash of the deck's bookmark (SPEC §3.4).
public enum SidecarStore {
    private static let log = Logger(subsystem: "dev.lectern", category: "sidecar")

    public static func sidecarName(forDeck deck: URL) -> String {
        deck.deletingPathExtension().lastPathComponent + ".lectern.json"
    }

    /// Where the sidecar for `deck` lives (whether or not it exists yet).
    public static func url(forDeck deck: URL, container: URL = defaultContainer()) -> URL {
        let directory = deck.deletingLastPathComponent()
        let beside = directory.appendingPathComponent(sidecarName(forDeck: deck))
        if FileManager.default.fileExists(atPath: beside.path) { return beside }
        if FileManager.default.isWritableFile(atPath: directory.path) { return beside }
        return container.appendingPathComponent(containerKey(forDeck: deck) + ".lectern.json")
    }

    public static func defaultContainer() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Lectern/Sidecars", isDirectory: true)
    }

    /// Stable key for a deck when the sidecar cannot sit beside it: a hash of the bookmark data, falling back to the path.
    static func containerKey(forDeck deck: URL) -> String {
        let data = (try? deck.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data(deck.path.utf8)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// Loads the deck's sidecar. Returns nil when there is none or it is unreadable; a bad file is logged, never fatal.
    public static func load(forDeck deck: URL, container: URL = defaultContainer()) -> SidecarDocument? {
        let url = self.url(forDeck: deck, container: container)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try load(from: url)
        } catch {
            log.error("ignoring unreadable sidecar \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public static func load(from url: URL) throws -> SidecarDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(SidecarDocument.self, from: data)
        if document.version > SidecarDocument.currentVersion {
            log.notice("sidecar \(url.lastPathComponent, privacy: .public) is version \(document.version), newer than \(SidecarDocument.currentVersion); unknown keys are kept out")
        }
        return document
    }

    /// Writes atomically. Throws when neither location is writable; callers log and carry on.
    public static func save(_ document: SidecarDocument, forDeck deck: URL, container: URL = defaultContainer()) throws {
        let url = self.url(forDeck: deck, container: container)
        try save(document, to: url)
    }

    public static func save(_ document: SidecarDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

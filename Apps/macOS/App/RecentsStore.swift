import Foundation
import Observation

/// Recently opened decks, kept as file bookmarks in UserDefaults so renames survive.
@MainActor
@Observable
final class RecentsStore {
    private static let key = "recentDocuments"
    private static let limit = 10
    private(set) var urls: [URL] = []

    init() {
        load()
    }

    func add(_ url: URL) {
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        urls.insert(url, at: 0)
        if urls.count > RecentsStore.limit { urls.removeLast(urls.count - RecentsStore.limit) }
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        save()
    }

    func clear() {
        urls = []
        save()
    }

    private func load() {
        guard let bookmarks = UserDefaults.standard.array(forKey: RecentsStore.key) as? [Data] else { return }
        urls = bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    private func save() {
        let bookmarks = urls.compactMap { try? $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        UserDefaults.standard.set(bookmarks, forKey: RecentsStore.key)
    }
}

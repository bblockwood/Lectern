import Foundation

/// Appends one CSV per transport under ~/Library/Application Support/LecternSpikeB/
/// and mirrors each row to stdout so a terminal launch shows everything live.
actor CSVLogger {
    private let directory: URL
    private var handles: [String: FileHandle] = [:]
    private let wallClock = ISO8601DateFormatter()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        directory = base.appending(path: "LecternSpikeB", directoryHint: .isDirectory)
        wallClock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    var directoryPath: String { directory.path(percentEncoded: false) }

    /// `fields` are written after the wall-clock timestamp.
    func append(transport: String, fields: [String]) {
        let row = ([wallClock.string(from: Date())] + fields).joined(separator: ",")
        print("[\(transport)] \(row)")
        do {
            let handle = try handle(for: transport)
            try handle.write(contentsOf: Data((row + "\n").utf8))
        } catch {
            print("CSV write failed: \(error)")
        }
    }

    private func handle(for transport: String) throws -> FileHandle {
        if let existing = handles[transport] { return existing }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(transport).csv")
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            let header = "wall_time,kind,id_or_count,sender_t_send_ns_or_median_ms,host_receive_ns_or_p95_ms\n"
            try Data(header.utf8).write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        handles[transport] = handle
        return handle
    }
}

import Foundation

/// A minimal read-only ZIP reader for Office documents: central directory, stored and deflated entries.
/// No ZIP64, no encryption. Deflate goes through Foundation's `NSData.decompressed(using: .zlib)` (raw DEFLATE).
public struct ZipArchive: Sendable {
    public enum ZipError: Error, Equatable { case notAZip, corrupt(String), unsupportedMethod(Int), entryNotFound(String) }

    public struct Entry: Hashable, Sendable {
        public let name: String
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    public let entries: [Entry]

    public init(data: Data) throws {
        self.data = data
        self.entries = try ZipArchive.readCentralDirectory(data)
    }

    public func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    public func contents(of name: String) throws -> Data {
        guard let entry = entry(named: name) else { throw ZipError.entryNotFound(name) }
        return try contents(of: entry)
    }

    public func contents(of entry: Entry) throws -> Data {
        let local = entry.localHeaderOffset
        guard local + 30 <= data.count, u32(at: local) == 0x04034b50 else { throw ZipError.corrupt("local header of \(entry.name)") }
        let nameLength = Int(u16(at: local + 26))
        let extraLength = Int(u16(at: local + 28))
        let start = local + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt("data of \(entry.name)") }
        let raw = data.subdata(in: start..<(start + entry.compressedSize))
        switch entry.method {
        case 0:
            return raw
        case 8:
            guard let inflated = try? (raw as NSData).decompressed(using: .zlib) as Data else { throw ZipError.corrupt("deflate of \(entry.name)") }
            return inflated
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    // MARK: - Parsing

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ZipError.notAZip }
        // End of central directory record: scan back over a possible comment (max 65535 bytes).
        let minimum = max(0, data.count - 22 - 65535)
        var eocd = -1
        var i = data.count - 22
        while i >= minimum {
            if data.u32(at: i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(data.u16(at: eocd + 10))
        let directoryOffset = Int(data.u32(at: eocd + 16))
        var entries: [Entry] = []
        var offset = directoryOffset
        for _ in 0..<count {
            guard offset + 46 <= data.count, data.u32(at: offset) == 0x02014b50 else { throw ZipError.corrupt("central directory") }
            let method = Int(data.u16(at: offset + 10))
            let compressedSize = Int(data.u32(at: offset + 20))
            let uncompressedSize = Int(data.u32(at: offset + 24))
            let nameLength = Int(data.u16(at: offset + 28))
            let extraLength = Int(data.u16(at: offset + 30))
            let commentLength = Int(data.u16(at: offset + 32))
            let localHeaderOffset = Int(data.u32(at: offset + 42))
            guard offset + 46 + nameLength <= data.count else { throw ZipError.corrupt("entry name") }
            let name = String(decoding: data.subdata(in: (offset + 46)..<(offset + 46 + nameLength)), as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: compressedSize,
                                 uncompressedSize: uncompressedSize, localHeaderOffset: localHeaderOffset))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private func u16(at offset: Int) -> UInt16 { data.u16(at: offset) }
    private func u32(at offset: Int) -> UInt32 { data.u32(at: offset) }
}

extension Data {
    func u16(at offset: Int) -> UInt16 {
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func u32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) | (UInt32(self[base + 1]) << 8) | (UInt32(self[base + 2]) << 16) | (UInt32(self[base + 3]) << 24)
    }
}

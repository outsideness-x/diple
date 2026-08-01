import Foundation

/// A minimal ZIP writer, just enough to emit an EPUB container.
///
/// Why hand-rolled rather than a zip library: an EPUB is a ZIP with one hard rule the
/// convenience APIs do not expose — the `mimetype` entry must come first and must be stored
/// uncompressed, so that a reader can identify the format by byte offset without inflating
/// anything. A writer that only ever stores entries satisfies that rule by construction.
///
/// Deflate is deliberately absent. The payload here is one article: tens of kilobytes of
/// markup next to images that are already JPEG or PNG and would not shrink. Compression would
/// buy nothing and cost the only part of the format that is easy to get wrong.
///
/// The archive is assembled in memory. That is safe because the caller bounds what goes in —
/// see `ArticleImporter.maximumImageBytes`.
struct ZIPWriter {
    private var payload = Data()
    private var entries: [CentralDirectoryEntry] = []
    private let modified: Date

    init(modified: Date = Date()) {
        self.modified = modified
    }

    private struct CentralDirectoryEntry {
        let path: String
        let crc32: UInt32
        let size: UInt32
        let offset: UInt32
    }

    enum WriteError: Error {
        /// A path that cannot be encoded, or an entry past the 4 GB the classic format allows.
        case invalidEntry(String)
    }

    /// Appends one file. `path` is the location inside the archive, e.g. `EPUB/nav.xhtml`.
    mutating func append(path: String, data: Data) throws {
        guard let pathBytes = path.data(using: .utf8),
              pathBytes.count <= UInt16.max,
              data.count <= UInt32.max,
              payload.count <= UInt32.max
        else {
            throw WriteError.invalidEntry(path)
        }

        let crc = CRC32.checksum(data)
        entries.append(
            CentralDirectoryEntry(
                path: path,
                crc32: crc,
                size: UInt32(data.count),
                offset: UInt32(payload.count)
            )
        )

        payload.appendUInt32(0x0403_4B50)           // local file header signature
        payload.appendUInt16(10)                    // version needed: 1.0, enough for stored
        payload.appendUInt16(0)                     // flags
        payload.appendUInt16(0)                     // method: stored
        payload.appendUInt16(dosTime)
        payload.appendUInt16(dosDate)
        payload.appendUInt32(crc)
        payload.appendUInt32(UInt32(data.count))    // compressed size == uncompressed
        payload.appendUInt32(UInt32(data.count))
        payload.appendUInt16(UInt16(pathBytes.count))
        payload.appendUInt16(0)                     // extra field length
        payload.append(pathBytes)
        payload.append(data)
    }

    mutating func append(path: String, text: String) throws {
        try append(path: path, data: Data(text.utf8))
    }

    /// Closes the archive: central directory followed by the end-of-central-directory record.
    func finalize() throws -> Data {
        var archive = payload
        let directoryOffset = archive.count

        for entry in entries {
            guard let pathBytes = entry.path.data(using: .utf8) else {
                throw WriteError.invalidEntry(entry.path)
            }
            archive.appendUInt32(0x0201_4B50)       // central directory header signature
            archive.appendUInt16(20)                // version made by
            archive.appendUInt16(10)                // version needed
            archive.appendUInt16(0)                 // flags
            archive.appendUInt16(0)                 // method: stored
            archive.appendUInt16(dosTime)
            archive.appendUInt16(dosDate)
            archive.appendUInt32(entry.crc32)
            archive.appendUInt32(entry.size)
            archive.appendUInt32(entry.size)
            archive.appendUInt16(UInt16(pathBytes.count))
            archive.appendUInt16(0)                 // extra field length
            archive.appendUInt16(0)                 // file comment length
            archive.appendUInt16(0)                 // disk number start
            archive.appendUInt16(0)                 // internal attributes
            archive.appendUInt32(0)                 // external attributes
            archive.appendUInt32(entry.offset)
            archive.append(pathBytes)
        }

        let directorySize = archive.count - directoryOffset
        guard entries.count <= UInt16.max,
              directorySize <= UInt32.max,
              directoryOffset <= UInt32.max
        else {
            throw WriteError.invalidEntry("archive too large")
        }

        archive.appendUInt32(0x0605_4B50)           // end of central directory signature
        archive.appendUInt16(0)                     // this disk
        archive.appendUInt16(0)                     // disk with the directory
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(directorySize))
        archive.appendUInt32(UInt32(directoryOffset))
        archive.appendUInt16(0)                     // archive comment length

        return archive
    }

    // MARK: - MS-DOS timestamp

    private var dateComponents: DateComponents {
        Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: modified
        )
    }

    /// Packed as `hhhhhmmmmmmsssss`; seconds are stored in two-second units, which is the
    /// resolution the 1980s format has, not a rounding bug.
    private var dosTime: UInt16 {
        let parts = dateComponents
        let hour = UInt16(parts.hour ?? 0)
        let minute = UInt16(parts.minute ?? 0)
        let second = UInt16((parts.second ?? 0) / 2)
        return (hour << 11) | (minute << 5) | second
    }

    /// Packed as `yyyyyyymmmmddddd`, with the year counted from 1980. Anything earlier cannot
    /// be represented, so it clamps to the epoch of the format rather than wrapping.
    private var dosDate: UInt16 {
        let parts = dateComponents
        let year = UInt16(max((parts.year ?? 1980) - 1980, 0))
        let month = UInt16(parts.month ?? 1)
        let day = UInt16(parts.day ?? 1)
        return (year << 9) | (month << 5) | day
    }
}

/// CRC-32 as ZIP defines it: the IEEE 802.3 polynomial in reversed bit order.
private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1 == 1) ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    /// ZIP is little-endian throughout, on every platform it has ever run on.
    mutating func appendUInt16(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }
}

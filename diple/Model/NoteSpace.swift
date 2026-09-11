import Foundation
import GRDB

/// A place notes are kept in: Things' Area, Apple Notes' folder.
///
/// Flat — a space holds notes, not other spaces — and in the reader's own order. It carries a
/// name and one monochrome glyph from a short list, and nothing else: no colour, because the
/// app's whole colour vocabulary is the accent, destructive and success, and a sidebar of
/// tinted folders would be a fourth.
///
/// **A note never dies with its space.** Deleting one sends what it held back to the Inbox. And
/// a note that arrives from iCloud before its space does is shown in the Inbox until the space
/// catches up, but its `spaceId` is left alone: clearing it would lose a filing to nothing more
/// than the order two records happened to be delivered in.
public nonisolated struct NoteSpace: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public static let databaseTableName = "space"

    public var id: String
    public var name: String
    /// An SF Symbol name from `symbols`. Stored as the name rather than an index so the list can
    /// be reordered or grown without moving anyone's glyph.
    public var symbol: String
    /// Fractional, so a space can be put *between* two others by taking the midpoint — one row
    /// written and one record synced, rather than renumbering every space after it. With whole
    /// numbers, two devices that each reordered something would fight over every row.
    public var sortIndex: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        symbol: String = NoteSpace.defaultSymbol,
        sortIndex: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static let defaultSymbol = "folder"

    /// The glyphs a space can wear. Monochrome, all of them, and all of a family with the shelf
    /// and the page the rest of the app draws in.
    public static let symbols: [String] = [
        "folder", "tray.full", "archivebox", "book.closed",
        "books.vertical", "text.book.closed", "graduationcap", "briefcase",
        "hammer", "lightbulb", "sparkles", "leaf",
        "heart", "star", "flag", "bookmark",
        "calendar", "house", "globe", "person.2",
        "music.note", "paintbrush", "camera", "cup.and.saucer"
    ]

    /// Where a space goes when it is put between two neighbours. `nil` on either side means the
    /// end of the list: before the first, or after the last.
    public static func sortIndex(between before: Double?, and after: Double?) -> Double {
        switch (before, after) {
        case let (before?, after?): return (before + after) / 2
        case let (before?, nil): return before + 1
        case let (nil, after?): return after - 1
        case (nil, nil): return 1
        }
    }
}

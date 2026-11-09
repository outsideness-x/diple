import Foundation
import GRDB

/// What the reading log remembers about a source, so that its record does not depend on the
/// source still being on the shelf.
///
/// **Why the log needs its own memory.** A sitting outlives its book — `readingSession.bookId`
/// is left dangling on purpose, as `highlight.bookId` is — but until this table the sitting was
/// the only thing that did: the title went with the `book` row and the cover went with the
/// book's folder, so a year's statistics printed "A source no longer in the library" under a
/// blank where a cover had stood. A record of what was read cannot be emptied by tidying the
/// shelf. Highlights solved the same problem with a snapshot frozen into each passage
/// (`v8_addHighlightBookSnapshot`); the log is keyed by source rather than by row, so it keeps
/// one snapshot per source instead of one per sitting.
///
/// **What it holds, and when it is written.** The snapshot fields are written in the
/// transaction that deletes the book — locally or on a deletion arriving from iCloud — and only
/// for a source the log has something to say about: a sitting with it, or a finish. While the
/// book lives its own row is read instead, so a renamed title or a replaced cover is never
/// stale here. `finishedAt` is the exception: it is written the moment a book is marked
/// finished, because nothing else in the database records *when* that happened.
///
/// **Local, like the sittings it describes.** Not synchronised, for the reason recorded on
/// `ReadingSession`; a source finished on another device is still dated here from the
/// `lastOpenedAt` that `markBookAsFinished` stamps and iCloud does carry — see
/// `inferredFinishDate(of:lastSitting:)`.
public nonisolated struct ReadingLogSource: Codable, Sendable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "readingLogSource"

    public var bookId: String
    public var title: String
    public var author: String?
    public var sourceKind: PublicationKind
    /// The kept cover, relative to Documents like `Book.coverPath` (`Covers/<id>.jpg`), so the
    /// same `BookCoverView` and cache draw it. `nil` while the book is alive — its own cover is
    /// drawn then — and for a source that never had one.
    public var coverPath: String?
    /// When the source was last marked finished. `nil` for one never finished, and for one
    /// finished before this column existed, whose date is inferred at read time instead.
    public var finishedAt: Date?

    public var id: String { bookId }

    public init(
        bookId: String,
        title: String,
        author: String? = nil,
        sourceKind: PublicationKind = .epub,
        coverPath: String? = nil,
        finishedAt: Date? = nil
    ) {
        self.bookId = bookId
        self.title = title
        self.author = author
        self.sourceKind = sourceKind
        self.coverPath = coverPath
        self.finishedAt = finishedAt
    }

    /// Where a deleted source's cover is kept, relative to Documents.
    ///
    /// Outside `Books/`, which is the folder deletion removes, and one flat file per source:
    /// the log reads covers by id and never lists the folder.
    public static func keptCoverPath(forBookId bookId: String) -> String {
        "Covers/\(bookId).jpg"
    }

    /// The date of a finish nobody recorded: `lastOpenedAt` first — `markBookAsFinished` stamps
    /// it, and a book read to its end stamped it on the last page — then the last measured
    /// sitting, then the day it was added. Used by the statistics for a live book and by the
    /// deletion that freezes the date, so a finish is dated the same way before and after the
    /// book is gone.
    public static func inferredFinishDate(of book: Book, lastSitting: Date?) -> Date {
        book.lastOpenedAt ?? lastSitting ?? book.addedAt
    }
}

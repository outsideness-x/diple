import Foundation
import GRDB

/// One sitting with a book, as it was actually measured.
///
/// **What this is not.** It is not "the app was open for 40 minutes". The figures come from
/// `ReadingSpeedSampler`, which already refuses everything that is not reading — a page left
/// open while the kettle boils, a jump through the table of contents, a drag of the progress
/// bar — because the reading-speed estimate could not survive counting those. The log inherits
/// that refusal, and it inherits its cost too: a sitting that never accumulated a couple of
/// pages leaves no row at all. A ledger that says less than happened is worth more than one
/// that says a pocket was reading.
///
/// **It is not synchronised.** `DipleBook`, `DipleHighlight` and `DipleNote` are already
/// waiting on a CloudKit production schema deploy (see the tags note and
/// `app-store/readiness-report.md`), and a fourth record type would deepen a block that is
/// holding a release. So the log is local, an iPad keeps its own, and the day this changes it
/// is one more record type of five plain fields — nothing here is shaped to prevent it.
public struct ReadingSession: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "readingSession"

    public let id: String
    public let bookId: String
    /// When the first measured passage of this sitting was read, and when the last was. Not the
    /// moment the reader opened the book and closed it — see above.
    public let startedAt: Date
    public let endedAt: Date
    /// Characters of prose actually passed, and the seconds they took. Kept apart rather than
    /// reduced to a pace, because the ledger prints both and a pace divides out of them
    /// whenever it is wanted.
    public let characters: Double
    public let seconds: Double

    public init(
        id: String = UUID().uuidString,
        bookId: String,
        startedAt: Date,
        endedAt: Date,
        characters: Double,
        seconds: Double
    ) {
        self.id = id
        self.bookId = bookId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.characters = characters
        self.seconds = seconds
    }
}

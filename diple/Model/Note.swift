import Foundation
import GRDB

/// A free-form user note. `bookId` is the optional library item the note is tagged with;
/// it is cleared rather than cascaded when that book is deleted, so notes outlive books.
///
/// **Two kinds of column, written by two kinds of call.** `title`, `body` and `bookId` are what
/// the note *says*, and `saveNote` writes them. `spaceId`, `pinnedAt`, `trashedAt` and
/// `dailyDate` are where the note *lives*, and only the organising calls move them — `moveNotes`,
/// `setPinned`, `trashNote` — while `saveNote` keeps whatever the stored row already holds. Every
/// editor in the app builds a fresh `Note` from its own fields on each autosave, and a note moved
/// to a space while its page was open would otherwise be moved back by the next keystroke. The
/// same rule the tags already follow: filing is not writing (see `setTags(_:forNoteID:)`).
public struct Note: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String?
    public var body: String
    public var bookId: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// The space the note is filed in. `nil` with no `bookId` either is the Inbox; `nil` with a
    /// source is filed under that source in From reading. A space that has not arrived from
    /// iCloud yet is treated as absent for display and **kept** — see `NoteSpace`.
    public var spaceId: String?
    /// When it was pinned; `nil` is not pinned. A date rather than a flag because it is also the
    /// order the pins stand in.
    public var pinnedAt: Date?
    /// When it went to Recently deleted; `nil` is alive. The date is where the thirty days are
    /// counted from.
    public var trashedAt: Date?
    /// `yyyy-MM-dd` for a day's page, `nil` for every other note. Locale-free on purpose: the
    /// key has to mean the same day on every device the note syncs to.
    ///
    /// **Not unique**, deliberately. Two devices offline on the same morning can each start the
    /// day's page, and a UNIQUE index would make the second one arriving from iCloud abort the
    /// whole batch it came in. Both survive; the day's page is the earliest of them.
    public var dailyDate: String?

    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        body: String,
        bookId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        spaceId: String? = nil,
        pinnedAt: Date? = nil,
        trashedAt: Date? = nil,
        dailyDate: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.bookId = bookId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.spaceId = spaceId
        self.pinnedAt = pinnedAt
        self.trashedAt = trashedAt
        self.dailyDate = dailyDate
    }

    public var isPinned: Bool { pinnedAt != nil }
    public var isTrashed: Bool { trashedAt != nil }

    /// How long a note stays in Recently deleted before it is gone for good.
    public static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    /// The key of the day's page for `date`, in the reader's own calendar — the day they are
    /// living in, not the one in Greenwich.
    public static func dailyKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }
}

/// Free-text tag attached to a note. Tags are stored one row per pair so the notes tab can
/// list every tag in use without parsing packed strings.
public struct NoteTag: Codable, FetchableRecord, PersistableRecord, Equatable, Hashable, Sendable {
    public var noteId: String
    public var tag: String

    public init(noteId: String, tag: String) {
        self.noteId = noteId
        self.tag = tag
    }

    /// Tags are matched case-insensitively, so they are stored in a single normalized form.
    /// The rule itself lives in `TagName`, shared with `BookTag`.
    public static func normalized(_ raw: String) -> String? {
        TagName.normalized(raw)
    }
}

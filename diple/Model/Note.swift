import Foundation
import GRDB

/// A free-form user note. `bookId` is the optional library item the note is tagged with;
/// it is cleared rather than cascaded when that book is deleted, so notes outlive books.
public struct Note: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String?
    public var body: String
    public var bookId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        body: String,
        bookId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.bookId = bookId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

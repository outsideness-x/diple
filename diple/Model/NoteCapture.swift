import Foundation

/// Writing a thought down from outside the app: onto today's page, or into the Inbox.
///
/// Both land through `AppDatabase.saveNote`, the same door every editor uses, so a captured line
/// is indexed, synced and backed up exactly like one typed on the page — there is no second way
/// a note comes into being.
public enum NoteCapture {
    /// What a captured line does to a page that already has words on it: it starts a paragraph
    /// of its own. A blank line rather than a single break, because a single break after a list
    /// item would make the new line part of that item in any Markdown reader.
    public static func appending(_ text: String, to body: String) -> String {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return body }
        guard !existing.isEmpty else { return line }
        return existing + "\n\n" + line
    }

    public enum CaptureError: LocalizedError {
        case nothingToAdd

        public var errorDescription: String? {
            switch self {
            case .nothingToAdd: return String(localized: "There was nothing to add.")
            }
        }
    }

    /// Adds a line to today's page — the one already begun, or a new one that begins with it —
    /// and returns the page's title, which is the day, for the reply to name.
    @discardableResult
    public static func addToToday(
        _ text: String,
        in database: AppDatabase,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureError.nothingToAdd
        }
        let key = Note.dailyKey(for: now, calendar: calendar)

        if var page = try database.fetchDailyNote(forKey: key) {
            let tags = try database.fetchTags(forNoteID: page.id)
            page.body = appending(text, to: page.body)
            page.updatedAt = now
            try database.saveNote(page, tags: tags)
            return page.title ?? Note.dailyTitle(forKey: key, calendar: calendar)
        }

        let title = Note.dailyTitle(forKey: key, calendar: calendar)
        let page = Note(
            title: title,
            body: appending(text, to: ""),
            createdAt: now,
            updatedAt: now,
            dailyDate: key
        )
        try database.saveNote(page, tags: [])
        return title
    }

    /// A note of its own in the Inbox, under a given id.
    ///
    /// The id is the caller's so a retry cannot write the same thought twice: a queue that is
    /// drained, crashes after the write and before it forgets the entry, finds the note already
    /// there on the next pass — the same arrangement the shared-link queue uses for articles.
    public static func addToInbox(
        _ text: String,
        id: String,
        in database: AppDatabase,
        now: Date = Date()
    ) throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw CaptureError.nothingToAdd }
        guard try database.fetchNote(id: id) == nil else { return }
        try database.saveNote(Note(id: id, body: body, createdAt: now, updatedAt: now), tags: [])
    }
}

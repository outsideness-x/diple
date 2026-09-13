import Foundation

/// What the notes widget shows — the Inbox, the open tasks, today's page — left in the App Group
/// by the app.
///
/// The same arrangement as `DailyQuoteSnapshot`, for the same reason: a widget cannot open the
/// library's database, and every number here is the one the Desk shows, counted once by the rule
/// the Desk uses (`NotesDesk`), not recounted by a second implementation in another process.
public nonisolated struct NotesSnapshot: Codable, Sendable, Equatable {
    /// Today's page as it stood when the snapshot was written.
    public struct Today: Codable, Sendable, Equatable {
        /// `DailyQuoteDay.key` of the day this page belongs to. The widget compares it with its own
        /// today, so a snapshot left over from yesterday is not shown as this morning's page.
        public let day: String
        public let title: String
        /// The page's words without their notation, the first few lines of them.
        public let preview: String

        public init(day: String, title: String, preview: String) {
            self.day = day
            self.title = title
            self.preview = preview
        }
    }

    public let generatedAt: Date
    public let inboxCount: Int
    public let openTaskCount: Int
    public let today: Today?

    public init(generatedAt: Date, inboxCount: Int, openTaskCount: Int, today: Today?) {
        self.generatedAt = generatedAt
        self.inboxCount = inboxCount
        self.openTaskCount = openTaskCount
        self.today = today
    }

    /// Today's page if it is today's, measured against the widget's own clock.
    public func today(on date: Date) -> Today? {
        guard let today, today.day == DailyQuoteDay.key(for: date) else { return nil }
        return today
    }
}

public nonisolated struct NotesSnapshotStore: Sendable {
    public static let fileName = "notes-snapshot.json"

    private let fileURL: URL

    public static func shared() throws -> Self {
        guard let directoryURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedLinkInbox.appGroupIdentifier
        ) else {
            throw SharedLinkInbox.InboxError.appGroupUnavailable
        }
        return Self(directoryURL: directoryURL)
    }

    public init(directoryURL: URL) {
        self.fileURL = directoryURL.appendingPathComponent(Self.fileName)
    }

    public func read() -> NotesSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NotesSnapshot.self, from: data)
    }

    public func write(_ snapshot: NotesSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}

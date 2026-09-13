import Foundation

/// Words shared into diple — a paragraph selected in Mail, a line from Messages, a quote from
/// another reader — waiting for the app to make them notes in the Inbox.
///
/// The same hand-off as `SharedLinkInbox`, for the same reason: the share sheet runs in a
/// process that must not open the library database, so it leaves the text in the App Group and
/// the app writes the note on its next activation. The entry's id becomes the note's id, which
/// is what makes a drain that crashes between writing the note and forgetting the entry harmless:
/// the next pass finds the note already there.
public nonisolated struct SharedNoteInbox: Sendable {
    public struct Entry: Codable, Hashable, Identifiable, Sendable {
        public let id: UUID
        public let text: String
        public let createdAt: Date

        public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
            self.id = id
            self.text = text
            self.createdAt = createdAt
        }
    }

    public enum InboxError: LocalizedError {
        case empty
        case inboxFull

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "There’s no text in what was shared."
            case .inboxFull:
                return "diple’s shared inbox is full. Open the app to finish saving what’s waiting."
            }
        }
    }

    /// The same ceiling as the link queue, and the same reason: a hundred waiting means the app
    /// has not had a chance to drain, and saying so beats silently dropping the oldest.
    private static let maximumPendingCount = 100
    public static let fileName = "shared-note-inbox.json"

    /// Rung by the share sheet after it writes, heard by an app that is already running.
    ///
    /// Activation is not enough on its own: sharing from inside diple — a note's Share Markdown,
    /// straight back into the Inbox — never takes the app out of the foreground, so there is no
    /// activation to wait for, and the note would appear only the next time the app was opened.
    /// A Darwin notification is the one signal both processes can reach; it carries nothing, the
    /// queue is the message.
    public static let didEnqueueNotification = "com.chemical-pink.diple.sharedNoteInbox.didEnqueue"

    public static func announceEnqueue() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(didEnqueueNotification as CFString),
            nil,
            nil,
            true
        )
    }

    private let queue: AppGroupJSONFile<Entry>

    public static func live() throws -> Self {
        guard let directoryURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedLinkInbox.appGroupIdentifier
        ) else {
            throw SharedLinkInbox.InboxError.appGroupUnavailable
        }
        return Self(directoryURL: directoryURL)
    }

    public init(directoryURL: URL) {
        self.queue = AppGroupJSONFile(directoryURL: directoryURL, fileName: Self.fileName)
    }

    @discardableResult
    public func enqueue(_ text: String, at date: Date = Date()) throws -> Entry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InboxError.empty }
        return try queue.mutate { entries in
            // The same words shared twice before the app opened are one note, not two.
            if let existing = entries.first(where: { $0.text == trimmed }) {
                return existing
            }
            guard entries.count < Self.maximumPendingCount else { throw InboxError.inboxFull }
            let entry = Entry(text: trimmed, createdAt: date)
            entries.append(entry)
            return entry
        }
    }

    public func pending() throws -> [Entry] {
        try queue.read().sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(id: UUID) throws {
        _ = try queue.mutate { entries in
            entries.removeAll { $0.id == id }
        }
    }

    /// Whether shared text is a note or a link to import.
    ///
    /// A share that is only an address — trimmed, one token, a web URL — is a link, and goes to
    /// the article importer as it always has. Anything with words around it is something someone
    /// wanted to keep as words, even when a link sits inside it: a paragraph that cites a page is
    /// a thought about the page, not a request to save the page.
    public static func linkOnly(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed)
        else { return nil }
        return SharedLinkInbox.normalized(url)
    }
}

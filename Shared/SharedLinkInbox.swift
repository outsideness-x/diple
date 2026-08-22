import Foundation

/// The tiny cross-process hand-off between the Share Extension and the app.
///
/// The extension deliberately does not open the library database or run the article parser:
/// both belong to the containing app and its sandbox. It only records a validated web address
/// in the shared App Group. The app removes an entry after the existing `ArticleImporter` has
/// committed the generated EPUB and its database row, so suspension or a network failure cannot
/// turn a successful-looking share into a lost article.
public nonisolated struct SharedLinkInbox: Sendable {
    public static let appGroupIdentifier = "group.com.chemical-pink.diple"

    public struct Entry: Codable, Hashable, Identifiable, Sendable {
        public let id: UUID
        public let urlString: String
        public let createdAt: Date
        public var attemptCount: Int
        public var lastAttemptAt: Date?
        public var lastError: String?

        public var url: URL? { URL(string: urlString) }

        public init(
            id: UUID = UUID(),
            urlString: String,
            createdAt: Date = Date(),
            attemptCount: Int = 0,
            lastAttemptAt: Date? = nil,
            lastError: String? = nil
        ) {
            self.id = id
            self.urlString = urlString
            self.createdAt = createdAt
            self.attemptCount = attemptCount
            self.lastAttemptAt = lastAttemptAt
            self.lastError = lastError
        }

        private enum CodingKeys: String, CodingKey {
            case id, urlString, createdAt, attemptCount, lastAttemptAt, lastError
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            urlString = try values.decode(String.self, forKey: .urlString)
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            attemptCount = try values.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
            lastAttemptAt = try values.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
            lastError = try values.decodeIfPresent(String.self, forKey: .lastError)
        }
    }

    public enum InboxError: LocalizedError {
        case appGroupUnavailable
        case unsupportedURL
        case queueUnavailable
        case inboxFull

        public var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return "diple’s shared inbox isn’t available on this device."
            case .unsupportedURL:
                return "That item doesn’t contain a secure web link."
            case .queueUnavailable:
                return "diple couldn’t update its shared inbox."
            case .inboxFull:
                return "diple’s shared inbox is full. Open the app to finish saving the waiting links."
            }
        }
    }

    private static let maximumPendingCount = 100
    private let directoryURL: URL
    private let queueURL: URL

    public static func live() throws -> Self {
        guard let directoryURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw InboxError.appGroupUnavailable
        }
        return Self(directoryURL: directoryURL)
    }

    /// An injectable directory keeps queue semantics testable without requiring signed App
    /// Group entitlements in the XCTest host.
    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.queueURL = directoryURL.appendingPathComponent("shared-link-inbox.json")
    }

    @discardableResult
    public func enqueue(_ candidate: URL, at date: Date = Date()) throws -> Entry {
        guard let normalized = Self.normalized(candidate) else { throw InboxError.unsupportedURL }
        return try mutate { entries in
            if let existing = entries.first(where: { $0.urlString == normalized.absoluteString }) {
                return existing
            }

            // A successful share must never evict an older one behind the reader's back. One
            // hundred pending links already means the containing app has not had a chance to
            // drain the queue; reporting that honestly is safer than turning the oldest
            // success into silent data loss.
            guard entries.count < Self.maximumPendingCount else { throw InboxError.inboxFull }

            let entry = Entry(urlString: normalized.absoluteString, createdAt: date)
            entries.append(entry)
            return entry
        }
    }

    public func pending() throws -> [Entry] {
        try coordinate { try readQueue() }
    }

    public func remove(id: UUID) throws {
        _ = try mutate { entries in
            entries.removeAll { $0.id == id }
        }
    }

    public func markFailed(id: UUID, message: String, at date: Date = Date()) throws {
        _ = try mutate { entries in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].attemptCount += 1
            entries[index].lastAttemptAt = date
            entries[index].lastError = message
        }
    }

    public func clearFailure(id: UUID) throws {
        _ = try mutate { entries in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].lastAttemptAt = nil
            entries[index].lastError = nil
        }
    }

    /// Failed network imports stay queued, but automatic retries are spaced out so every app
    /// activation does not immediately repeat the same request. An explicit Retry clears this
    /// gate and processes the entry at once.
    public static func isReady(_ entry: Entry, at date: Date = Date()) -> Bool {
        guard let lastAttemptAt = entry.lastAttemptAt else { return true }
        let exponent = max(0, min(entry.attemptCount - 1, 8))
        let delay = min(15 * pow(2, Double(exponent)), 60 * 60)
        return date.timeIntervalSince(lastAttemptAt) >= delay
    }

    public static func normalized(_ candidate: URL) -> URL? {
        guard var components = URLComponents(url: candidate, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else { return nil }

        // The containing app has no ATS exception. Canonicalizing legacy HTTP shares to HTTPS
        // here keeps queue deduplication stable and avoids promising an import iOS will block.
        components.scheme = "https"
        components.host = host.lowercased()
        components.fragment = nil
        return components.url
    }

    private func mutate<Output>(_ change: (inout [Entry]) throws -> Output) throws -> Output {
        try coordinate {
            var entries = try readQueue()
            let result = try change(&entries)
            try writeQueue(entries)
            return result
        }
    }

    private func coordinate<Output>(_ work: () throws -> Output) throws -> Output {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<Output, Error>?
        coordinator.coordinate(
            writingItemAt: directoryURL,
            options: .forMerging,
            error: &coordinationError
        ) { _ in
            outcome = Result { try work() }
        }

        if let coordinationError { throw coordinationError }
        guard let outcome else { throw InboxError.queueUnavailable }
        return try outcome.get()
    }

    private func readQueue() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: queueURL.path) else { return [] }
        let data = try Data(contentsOf: queueURL, options: .mappedIfSafe)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Entry].self, from: data)
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func writeQueue(_ entries: [Entry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entries).write(to: queueURL, options: .atomic)
    }
}

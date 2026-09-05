import Foundation

/// The passage of the day, and the days after it, left where the widget can read them.
///
/// A widget runs in its own process with its own container: it cannot open the library's SQLite
/// file, and moving that file into the App Group to let it try would put a shared lock on the
/// one thing the whole app depends on, to draw a card. So the app writes a small snapshot
/// beside `shared-link-inbox.json`, and the widget only reads.
///
/// It carries **several days**, not one, and that is the whole design. A widget refreshes on the
/// system's schedule, not the app's, and a phone that is not opened for a week would otherwise
/// show Monday's passage on Friday. The app resolves the next fortnight with the same pure rule
/// Home uses — `DailyResurfacingService.candidate(for:from:)` — so what the Lock Screen shows on
/// Thursday is exactly what Home will show when it is opened on Thursday.
public nonisolated struct DailyQuoteSnapshot: Codable, Sendable, Equatable {
    /// One day's passage, already chosen.
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        /// `yyyy-MM-dd` in the device's calendar, which is what the widget matches a date to.
        public let day: String
        public let quoteID: String
        public let text: String
        public let bookTitle: String?
        public let bookAuthor: String?
        public let colorHex: String

        public var id: String { day }

        public init(
            day: String,
            quoteID: String,
            text: String,
            bookTitle: String?,
            bookAuthor: String?,
            colorHex: String
        ) {
            self.day = day
            self.quoteID = quoteID
            self.text = text
            self.bookTitle = bookTitle
            self.bookAuthor = bookAuthor
            self.colorHex = colorHex
        }
    }

    public let generatedAt: Date
    public let entries: [Entry]
    /// How many passages the library holds. The widget uses it to tell "you have not saved
    /// anything yet" apart from "the app has not run since you did".
    public let totalQuoteCount: Int

    public init(generatedAt: Date, entries: [Entry], totalQuoteCount: Int) {
        self.generatedAt = generatedAt
        self.entries = entries
        self.totalQuoteCount = totalQuoteCount
    }

    public func entry(for day: String) -> Entry? {
        entries.first { $0.day == day }
    }
}

/// Reads and writes the snapshot file in the App Group.
public nonisolated struct DailyQuoteSnapshotStore: Sendable {
    public static let fileName = "daily-quote-snapshot.json"

    /// How far ahead the app resolves. Two weeks is longer than any plausible gap between
    /// launches on a phone whose owner reads, and short enough that a fortnight of passages is
    /// a few kilobytes.
    public static let horizonInDays = 14

    private let fileURL: URL

    public static func shared() throws -> Self {
        guard let directoryURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedLinkInbox.appGroupIdentifier
        ) else {
            throw SharedLinkInbox.InboxError.appGroupUnavailable
        }
        return Self(directoryURL: directoryURL)
    }

    /// An injectable directory, for the same reason the link inbox has one: the App Group
    /// entitlement is not available to the XCTest host.
    public init(directoryURL: URL) {
        self.fileURL = directoryURL.appendingPathComponent(Self.fileName)
    }

    public func read() -> DailyQuoteSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DailyQuoteSnapshot.self, from: data)
    }

    public func write(_ snapshot: DailyQuoteSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// Removing the file is how "the library is empty now" travels. Writing an empty snapshot
    /// would work too, but a missing file is the state a fresh install is already in, and one
    /// meaning per state is cheaper than two.
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// The day key both sides agree on.
///
/// A fixed Gregorian calendar and POSIX locale, because this string is a key, not a date shown
/// to anybody: a reader whose phone is on the Buddhist calendar must still match the day the
/// app wrote. The time zone is deliberately the device's own — the day a passage belongs to is
/// the reader's day, not UTC's.
public nonisolated enum DailyQuoteDay {
    public static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Midnight that begins the day after `date`, which is when a widget's entry stops being
    /// today's.
    public static func startOfNextDay(after date: Date, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date.addingTimeInterval(86_400)
    }
}

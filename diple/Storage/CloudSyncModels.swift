import Foundation
import GRDB

/// Stable CloudKit record namespaces. They are deliberately independent of Swift type names,
/// so a future refactor cannot silently change record IDs already stored in iCloud.
public nonisolated enum SyncEntityType: String, CaseIterable, Sendable {
    case book
    case bookAsset
    case highlight
    case bookmark
    case note
    case settings
}

public nonisolated enum SyncOperation: String, Sendable {
    case save
    case delete
}

public nonisolated struct SyncOutboxEntry: Decodable, FetchableRecord, Sendable {
    public let entityType: String
    public let entityID: String
    public let operation: String
    public let modifiedAt: Date

    public var entity: SyncEntityType? { SyncEntityType(rawValue: entityType) }
    public var pendingOperation: SyncOperation? { SyncOperation(rawValue: operation) }
}

public nonisolated struct SyncMetadata: Decodable, FetchableRecord, Sendable {
    public let entityType: String
    public let entityID: String
    public let modifiedAt: Date
    public let systemFields: Data?
}

public nonisolated struct SyncedNote: Sendable {
    public let note: Note
    public let tags: [String]
}

extension Notification.Name {
    /// Posted after a remote batch has been committed to the local store.
    static let dipleRemoteDataDidChange = Notification.Name("diple.remoteDataDidChange")
    /// A daily-resurfacing local notification was opened. The phone shell selects Highlights,
    /// while the desktop shell selects its equivalent sidebar source.
    static let dipleOpenDailyResurfacing = Notification.Name("diple.openDailyResurfacing")
    /// A source finished importing on *this* device, from a file or from a link. Carries the
    /// new `Book`; read it with `Notification.dipleImportedBook`.
    ///
    /// The importer is a lower layer than any one screen, and an import started on Home has to
    /// reach the shelf, which is a different `LibraryViewModel` in a different tab. Posting it
    /// once, where the row is actually written, is what keeps that from becoming a callback
    /// threaded through four view models. This is not the remote notification above: that one
    /// says iCloud changed something, this one says the reader just added something and is
    /// about to go looking for it.
    static let dipleSourceDidImport = Notification.Name("diple.sourceDidImport")
    /// A screen asked for Settings. The shell presents it, because the shell is the only place
    /// that outlives an accent change — see `dipleApp`.
    static let dipleOpenSettings = Notification.Name("diple.openSettings")
}

extension Notification {
    /// Keeps the `userInfo` key in one place rather than spelled out at each end.
    fileprivate static let dipleImportedBookKey = "book"

    /// The source carried by `.dipleSourceDidImport`.
    var dipleImportedBook: Book? { userInfo?[Notification.dipleImportedBookKey] as? Book }

    /// Builds the payload for `.dipleSourceDidImport`.
    static func dipleImportPayload(_ book: Book) -> [AnyHashable: Any] {
        [dipleImportedBookKey: book]
    }
}

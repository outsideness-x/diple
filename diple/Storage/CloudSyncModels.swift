import Foundation
import GRDB

/// Stable CloudKit record namespaces. They are deliberately independent of Swift type names,
/// so a future refactor cannot silently change record IDs already stored in iCloud.
public nonisolated enum SyncEntityType: String, CaseIterable, Sendable {
    case book
    case bookAsset
    case highlight
    case highlightReview
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
}

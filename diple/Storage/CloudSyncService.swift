import CloudKit
import Foundation
import os

/// Mirrors the offline-first GRDB store into the user's private iCloud database.
///
/// CKSyncEngine owns scheduling, retry backoff, subscriptions and change tokens. SQLite owns
/// the durable outbox and conflict timestamps, which keeps a user edit safe even if the process
/// exits between the local transaction and CloudKit's next send window.
public actor CloudSyncService: CKSyncEngineDelegate {
    public static let shared = CloudSyncService()

    public nonisolated static let containerIdentifier = "iCloud.com.chemical-pink.diple"

    private static let zoneName = "Diple"
    private static let stateKey = "diple_cloudkit_sync_engine_state_v1"
    private static let enabledKey = "diple_icloud_sync_enabled"
    private static let logger = Logger(subsystem: "com.chemical-pink.diple", category: "CloudSync")

    private let database = AppDatabase.shared
    private var syncEngine: CKSyncEngine?
    private var hasStarted = false

    /// Device-local — deliberately not part of `AppSettings`, which is itself synced through
    /// CloudKit: a synced flag could silently switch sync back on for a device where the user
    /// just turned it off. `UserDefaults.bool(forKey:)` already defaults to `false` when unset,
    /// which is exactly "off by default" with no separate migration to write.
    public nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Called from every local write (`AppDatabase.signalSyncIfNeeded`), so the disabled path
    /// has to stay cheap: checking the flag here — before ever hopping onto the actor — skips
    /// spawning a `Task` at all instead of spawning one that immediately no-ops.
    public nonisolated static func signalLocalChanges() {
        guard isEnabled else { return }
        Task { await shared.enqueueOutbox() }
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        // Unit-test hosts are intentionally built without application entitlements in CI.
        // Constructing an explicitly named CKContainer in that process traps before XCTest can
        // connect, so tests exercise the durable database bridge without starting live iCloud.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        do {
            try database.prepareInitialSync()
        } catch {
            Self.logger.error("Unable to prepare initial sync: \(error.localizedDescription)")
        }

        let stateSerialization: CKSyncEngine.State.Serialization? = {
            guard let data = UserDefaults.standard.data(forKey: Self.stateKey) else { return nil }
            return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }()
        var configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        syncEngine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
        await enqueueOutbox()

        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            // Automatic sync keeps retrying transient account/network failures.
            Self.logger.info("Initial iCloud sync deferred: \(error.localizedDescription)")
        }
    }

    /// Drops the running engine so a later `start()` (the user flipping the Settings toggle
    /// back on) builds a fresh one instead of finding `hasStarted` permanently latched. The
    /// engine's own serialized state in `UserDefaults` is left alone, so resuming continues
    /// from where it left off rather than re-uploading everything.
    public func stop() async {
        guard hasStarted else { return }
        syncEngine = nil
        hasStarted = false
    }

    private static var recordZone: CKRecordZone {
        CKRecordZone(zoneID: CKRecordZone.ID(zoneName: zoneName))
    }

    private static var zoneID: CKRecordZone.ID { recordZone.zoneID }

    private func enqueueOutbox() async {
        guard let syncEngine else { return }
        do {
            let entries = try database.fetchSyncOutbox()
            let pending = entries.compactMap { entry -> CKSyncEngine.PendingRecordZoneChange? in
                guard let entity = entry.entity, let operation = entry.pendingOperation else { return nil }
                let recordID = Self.recordID(entity: entity, id: entry.entityID)
                switch operation {
                case .save: return .saveRecord(recordID)
                case .delete: return .deleteRecord(recordID)
                }
            }
            syncEngine.state.add(pendingRecordZoneChanges: pending)
        } catch {
            Self.logger.error("Unable to read sync outbox: \(error.localizedDescription)")
        }
    }

    // MARK: CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            do {
                let data = try JSONEncoder().encode(event.stateSerialization)
                UserDefaults.standard.set(data, forKey: Self.stateKey)
            } catch {
                Self.logger.error("Unable to persist sync state: \(error.localizedDescription)")
            }
        case .accountChange(let event):
            await handleAccountChange(event)
        case .fetchedDatabaseChanges(let event):
            await handleFetchedDatabaseChanges(event)
        case .fetchedRecordZoneChanges(let event):
            await handleFetchedRecordZoneChanges(event, syncEngine: syncEngine)
        case .sentRecordZoneChanges(let event):
            await handleSentRecordZoneChanges(event, syncEngine: syncEngine)
        case .sentDatabaseChanges(let event):
            handleSentDatabaseChanges(event, syncEngine: syncEngine)
        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges:
            break
        @unknown default:
            Self.logger.info("Received an unknown CKSyncEngine event")
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.recordToSave(for: recordID)
        }
    }

    // MARK: Sending

    private func recordToSave(for recordID: CKRecord.ID) async -> CKRecord? {
        guard let key = Self.parse(recordID: recordID) else { return nil }
        do {
            let metadata = try database.fetchSyncMetadata(entity: key.entity, id: key.id)
            let record = Self.restoreRecord(from: metadata?.systemFields)
                ?? CKRecord(recordType: Self.recordType(for: key.entity), recordID: recordID)
            let modifiedAt = metadata?.modifiedAt ?? Date()
            record["modifiedAt"] = modifiedAt as CKRecordValue

            switch key.entity {
            case .book:
                guard let book = try database.fetchBookForSync(id: key.id) else { return nil }
                Self.populate(book: book, record: record)
            case .bookAsset:
                guard let book = try database.fetchBookForSync(id: key.id) else { return nil }
                let publicationURL = BookStorageService.shared.absoluteURL(for: book.filePath)
                guard FileManager.default.fileExists(atPath: publicationURL.path) else { return nil }
                record["publication"] = CKAsset(fileURL: publicationURL)
                record["fileName"] = publicationURL.lastPathComponent as CKRecordValue
                if let coverPath = book.coverPath {
                    let coverURL = BookStorageService.shared.absoluteURL(for: coverPath)
                    if FileManager.default.fileExists(atPath: coverURL.path) {
                        record["cover"] = CKAsset(fileURL: coverURL)
                        record["coverFileName"] = coverURL.lastPathComponent as CKRecordValue
                    }
                } else {
                    record["cover"] = nil
                    record["coverFileName"] = nil
                }
            case .highlight:
                guard let highlight = try database.fetchHighlightForSync(id: key.id) else { return nil }
                Self.populate(highlight: highlight, record: record)
            case .bookmark:
                guard let bookmark = try database.fetchBookmarkForSync(id: key.id) else { return nil }
                Self.populate(bookmark: bookmark, record: record)
            case .note:
                guard let note = try database.fetchNoteForSync(id: key.id) else { return nil }
                Self.populate(note: note, record: record)
            case .settings:
                let data = try await MainActor.run { try AppSettingsManager.shared.encodedSettings() }
                record["payload"] = data as CKRecordValue
            }
            return record
        } catch {
            Self.logger.error("Unable to build record \(recordID.recordName): \(error.localizedDescription)")
            return nil
        }
    }

    private static func populate(book: Book, record: CKRecord) {
        record["title"] = book.title as CKRecordValue
        record["author"] = book.author as CKRecordValue?
        record["fileName"] = URL(fileURLWithPath: book.filePath).lastPathComponent as CKRecordValue
        record["coverFileName"] = book.coverPath.map { URL(fileURLWithPath: $0).lastPathComponent } as CKRecordValue?
        record["addedAt"] = book.addedAt as CKRecordValue
        record["lastOpenedAt"] = book.lastOpenedAt as CKRecordValue?
        record["progress"] = NSNumber(value: book.progress)
        record["locator"] = book.locator as CKRecordValue?
        record["sourceURL"] = book.sourceURL as CKRecordValue?
        record["sourceKind"] = book.sourceKind.rawValue as CKRecordValue
    }

    private static func populate(highlight: Highlight, record: CKRecord) {
        record["bookID"] = highlight.bookId as CKRecordValue
        record["locator"] = highlight.locator as CKRecordValue
        record["text"] = highlight.text as CKRecordValue
        record["comment"] = highlight.comment as CKRecordValue?
        record["colorHex"] = highlight.colorHex as CKRecordValue
        record["createdAt"] = highlight.createdAt as CKRecordValue
        record["bookTitle"] = highlight.bookTitle as CKRecordValue?
        record["bookAuthor"] = highlight.bookAuthor as CKRecordValue?
    }

    private static func populate(bookmark: Bookmark, record: CKRecord) {
        record["bookID"] = bookmark.bookId as CKRecordValue
        record["locator"] = bookmark.locator as CKRecordValue
        record["name"] = bookmark.name as CKRecordValue
        record["colorHex"] = bookmark.colorHex as CKRecordValue
        record["createdAt"] = bookmark.createdAt as CKRecordValue
    }

    private static func populate(note: SyncedNote, record: CKRecord) {
        record["title"] = note.note.title as CKRecordValue?
        record["body"] = note.note.body as CKRecordValue
        record["bookID"] = note.note.bookId as CKRecordValue?
        record["createdAt"] = note.note.createdAt as CKRecordValue
        record["updatedAt"] = note.note.updatedAt as CKRecordValue
        record["tags"] = note.tags as CKRecordValue
    }

    // MARK: Receiving

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        var changed = false
        let modifications = event.modifications.sorted {
            Self.parse(recordID: $0.record.recordID)?.entity == .bookAsset &&
            Self.parse(recordID: $1.record.recordID)?.entity != .bookAsset
        }
        for modification in modifications {
            do {
                let applied = try await applyRemoteRecord(modification.record)
                changed = changed || applied
                if !applied, let key = Self.parse(recordID: modification.record.recordID) {
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.recordID(entity: key.entity, id: key.id))])
                }
            } catch {
                Self.logger.error("Unable to apply fetched record: \(error.localizedDescription)")
            }
        }

        for deletion in event.deletions {
            guard let key = Self.parse(recordID: deletion.recordID) else { continue }
            do {
                let applied = try database.applyRemoteDeletion(entity: key.entity, id: key.id)
                if applied {
                    if key.entity == .book {
                        try? BookStorageService.shared.deleteBookFolder(id: key.id)
                    }
                    changed = true
                } else {
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(deletion.recordID)])
                }
            } catch {
                Self.logger.error("Unable to apply fetched deletion: \(error.localizedDescription)")
            }
        }

        if changed {
            await enqueueOutbox()
            await MainActor.run {
                NotificationCenter.default.post(name: .dipleRemoteDataDidChange, object: nil)
            }
        }
    }

    private func applyRemoteRecord(_ record: CKRecord) async throws -> Bool {
        guard let key = Self.parse(recordID: record.recordID),
              let modifiedAt = record["modifiedAt"] as? Date
        else { return true }
        let systemFields = try Self.archiveSystemFields(of: record)

        switch key.entity {
        case .book:
            guard let title = record["title"] as? String,
                  let fileName = record["fileName"] as? String,
                  let addedAt = record["addedAt"] as? Date
            else { return true }
            let book = Book(
                id: key.id,
                title: title,
                author: record["author"] as? String,
                filePath: "Books/\(key.id)/\(URL(fileURLWithPath: fileName).lastPathComponent)",
                coverPath: (record["coverFileName"] as? String).map {
                    "Books/\(key.id)/\(URL(fileURLWithPath: $0).lastPathComponent)"
                },
                addedAt: addedAt,
                lastOpenedAt: record["lastOpenedAt"] as? Date,
                progress: (record["progress"] as? NSNumber)?.doubleValue ?? 0,
                locator: record["locator"] as? String,
                sourceURL: record["sourceURL"] as? String,
                sourceKind: (record["sourceKind"] as? String).flatMap(PublicationKind.init(rawValue:))
            )
            return try database.applyRemoteBook(book, modifiedAt: modifiedAt, systemFields: systemFields)
        case .bookAsset:
            guard try database.shouldAcceptRemoteChange(entity: .bookAsset, id: key.id, modifiedAt: modifiedAt) else {
                return false
            }
            guard let publication = record["publication"] as? CKAsset,
                  let publicationURL = publication.fileURL
            else { return true }
            let fileName = record["fileName"] as? String ?? "book.epub"
            _ = try BookStorageService.shared.installSyncedFile(
                from: publicationURL,
                bookId: key.id,
                suggestedName: fileName,
                fallbackName: "book.epub"
            )
            if let cover = record["cover"] as? CKAsset, let coverURL = cover.fileURL {
                let coverName = record["coverFileName"] as? String ?? "cover"
                let path = try BookStorageService.shared.installSyncedFile(
                    from: coverURL,
                    bookId: key.id,
                    suggestedName: coverName,
                    fallbackName: "cover"
                )
                await MainActor.run {
                    CoverImageCache.shared.invalidate(relativePath: path)
                }
            }
            return try database.applyRemoteBookAssetMetadata(
                id: key.id,
                modifiedAt: modifiedAt,
                systemFields: systemFields
            )
        case .highlight:
            guard let bookID = record["bookID"] as? String,
                  let locator = record["locator"] as? String,
                  let text = record["text"] as? String,
                  let colorHex = record["colorHex"] as? String,
                  let createdAt = record["createdAt"] as? Date
            else { return true }
            // Records written before this field existed simply lack it — `as?` decodes those
            // as nil, and `applyRemoteHighlight` refills them from the local book when it can.
            return try database.applyRemoteHighlight(
                Highlight(
                    id: key.id,
                    bookId: bookID,
                    locator: locator,
                    text: text,
                    comment: record["comment"] as? String,
                    colorHex: colorHex,
                    createdAt: createdAt,
                    bookTitle: record["bookTitle"] as? String,
                    bookAuthor: record["bookAuthor"] as? String
                ),
                modifiedAt: modifiedAt,
                systemFields: systemFields
            )
        case .bookmark:
            guard let bookID = record["bookID"] as? String,
                  let locator = record["locator"] as? String,
                  let name = record["name"] as? String,
                  let colorHex = record["colorHex"] as? String,
                  let createdAt = record["createdAt"] as? Date
            else { return true }
            return try database.applyRemoteBookmark(
                Bookmark(id: key.id, bookId: bookID, locator: locator, name: name, colorHex: colorHex, createdAt: createdAt),
                modifiedAt: modifiedAt,
                systemFields: systemFields
            )
        case .note:
            guard let body = record["body"] as? String,
                  let createdAt = record["createdAt"] as? Date,
                  let updatedAt = record["updatedAt"] as? Date
            else { return true }
            let synced = SyncedNote(
                note: Note(
                    id: key.id,
                    title: record["title"] as? String,
                    body: body,
                    bookId: record["bookID"] as? String,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                ),
                tags: record["tags"] as? [String] ?? []
            )
            return try database.applyRemoteNote(synced, modifiedAt: modifiedAt, systemFields: systemFields)
        case .settings:
            guard let payload = record["payload"] as? Data else { return true }
            guard try database.shouldAcceptRemoteChange(entity: .settings, id: "current", modifiedAt: modifiedAt) else {
                return false
            }
            try await MainActor.run { try AppSettingsManager.shared.applySyncedSettings(payload) }
            return try database.applyRemoteSettingsMetadata(modifiedAt: modifiedAt, systemFields: systemFields)
        }
    }

    // MARK: Event recovery

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        for record in event.savedRecords {
            guard let key = Self.parse(recordID: record.recordID),
                  let modifiedAt = record["modifiedAt"] as? Date,
                  let systemFields = try? Self.archiveSystemFields(of: record)
            else { continue }
            try? database.acknowledgeSavedRecord(
                entity: key.entity,
                id: key.id,
                modifiedAt: modifiedAt,
                systemFields: systemFields
            )
        }
        for recordID in event.deletedRecordIDs {
            guard let key = Self.parse(recordID: recordID) else { continue }
            try? database.acknowledgeDeletedRecord(entity: key.entity, id: key.id)
        }

        for failure in event.failedRecordSaves {
            guard let key = Self.parse(recordID: failure.record.recordID) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                if let serverRecord = failure.error.serverRecord {
                    _ = try? await applyRemoteRecord(serverRecord)
                }
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
            case .zoneNotFound:
                try? database.clearServerSystemFields(entity: key.entity, id: key.id)
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
            case .unknownItem:
                try? database.clearServerSystemFields(entity: key.entity, id: key.id)
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
            default:
                Self.logger.info("CloudKit will retry save failure: \(failure.error.localizedDescription)")
            }
        }

        for (recordID, error) in event.failedRecordDeletes {
            guard let key = Self.parse(recordID: recordID) else { continue }
            if error.code == .unknownItem {
                try? database.acknowledgeDeletedRecord(entity: key.entity, id: key.id)
            } else if error.code == .zoneNotFound {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
                syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }
        }
        await enqueueOutbox()
    }

    private func handleSentDatabaseChanges(
        _ event: CKSyncEngine.Event.SentDatabaseChanges,
        syncEngine: CKSyncEngine
    ) {
        for failure in event.failedZoneSaves where failure.error.code == .zoneNotFound || failure.error.code == .unknownItem {
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
        }
    }

    private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) async {
        if event.deletions.contains(where: { $0.zoneID.zoneName == Self.zoneName }) {
            try? database.queueFullResync()
            syncEngine?.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
            await enqueueOutbox()
        }
    }

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) async {
        switch event.changeType {
        case .signIn, .switchAccounts:
            // Local content remains available offline and is intentionally carried to the
            // newly selected private iCloud account rather than being destructively erased.
            try? database.queueFullResync()
            syncEngine?.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
            await enqueueOutbox()
        case .signOut:
            break
        @unknown default:
            break
        }
    }

    // MARK: Record identity and system fields

    private struct RecordKey {
        let entity: SyncEntityType
        let id: String
    }

    private static func recordID(entity: SyncEntityType, id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(entity.rawValue)|\(id)", zoneID: zoneID)
    }

    private static func parse(recordID: CKRecord.ID) -> RecordKey? {
        let parts = recordID.recordName.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let entity = SyncEntityType(rawValue: String(parts[0])) else { return nil }
        return RecordKey(entity: entity, id: String(parts[1]))
    }

    private static func recordType(for entity: SyncEntityType) -> String {
        switch entity {
        case .book: return "DipleBook"
        case .bookAsset: return "DipleBookAsset"
        case .highlight: return "DipleHighlight"
        case .bookmark: return "DipleBookmark"
        case .note: return "DipleNote"
        case .settings: return "DipleSettings"
        }
    }

    private static func archiveSystemFields(of record: CKRecord) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func restoreRecord(from data: Data?) -> CKRecord? {
        guard let data, let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }
}

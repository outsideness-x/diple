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

    /// How long a record that CloudKit refused sits out before it is offered again, and the
    /// ceiling that repeated refusals climb to. Five minutes is deliberately far longer than
    /// any network hiccup: the failures this covers are the ones no amount of hurry fixes.
    private static let retryDelay: TimeInterval = 300
    private static let maxRetryDelay: TimeInterval = 1800
    /// Failures with a known repair (a stale change tag, a missing zone) converge in an attempt
    /// or two, so those are re-queued at once — but only this many times. A record that keeps
    /// failing after its repair falls back to the slow retry like any other.
    private static let immediateRetryLimit = 3

    private let database = AppDatabase.shared
    private var syncEngine: CKSyncEngine?
    private var hasStarted = false
    private var lastIssue: String?

    /// A record CloudKit rejected, with the moment it may be sent again.
    ///
    /// Without this, one permanently failing save is an unbounded loop at network speed:
    /// `handleSentRecordZoneChanges` ends in `enqueueOutbox()`, which re-offers every row of the
    /// durable outbox — including the row that just failed — `automaticallySync` sends it within
    /// the same second, and it fails again. The engine's own backoff never engages, because from
    /// its side each cycle is a *successful* send that happened to carry a per-record error.
    /// What the reader sees is Settings flipping between "Syncing" and "Needs Attention" several
    /// times a second, with the layout jumping under their thumb.
    private var failedChanges: [String: ChangeFailure] = [:]
    private var deferredRetryTask: Task<Void, Never>?

    private struct ChangeFailure {
        var attempts: Int
        var readyAt: Date
    }

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
        Task { await shared.localChangesArrived() }
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        await publish(.checking)

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
            lastIssue = "The local library couldn’t be prepared for iCloud."
            hasStarted = false
            await publish(.attention, message: lastIssue)
            return
        }

        let container = CKContainer(identifier: Self.containerIdentifier)
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                lastIssue = Self.accountMessage(for: status)
                hasStarted = false
                await publish(.attention, message: lastIssue)
                return
            }
        } catch {
            lastIssue = "diple couldn’t check your iCloud account: \(error.localizedDescription)"
            hasStarted = false
            await publish(.attention, message: lastIssue)
            return
        }
        lastIssue = nil

        let stateSerialization: CKSyncEngine.State.Serialization? = {
            guard let data = UserDefaults.standard.data(forKey: Self.stateKey) else { return nil }
            return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }()
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        syncEngine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
        guard await enqueueOutbox() else {
            await publish(.attention, message: lastIssue)
            return
        }
        await publish(.syncing)

        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            lastIssue = nil
            await refreshStatus(markSuccessful: true)
        } catch {
            // Automatic sync keeps retrying transient account/network failures.
            Self.logger.info("Initial iCloud sync deferred: \(error.localizedDescription)")
            lastIssue = Self.userMessage(for: error)
            await publish(.attention, message: lastIssue)
        }
    }

    /// Drops the running engine so a later `start()` (the user flipping the Settings toggle
    /// back on) builds a fresh one instead of finding `hasStarted` permanently latched. The
    /// engine's own serialized state in `UserDefaults` is left alone, so resuming continues
    /// from where it left off rather than re-uploading everything.
    public func stop() async {
        syncEngine = nil
        hasStarted = false
        lastIssue = nil
        clearFailedChanges()
        await publish(.disabled, pendingCount: 0)
    }

    /// A user-initiated health check. Unlike automatic scheduling this performs both directions
    /// now and returns Settings to a truthful pending/synced/error state when it completes.
    public func retry() async {
        guard Self.isEnabled else {
            await publish(.disabled, pendingCount: 0)
            return
        }
        // "Check Again" means now. Whatever a record is waiting out, the reader asking for it
        // in person outranks the backoff.
        clearFailedChanges()
        if syncEngine == nil {
            hasStarted = false
            await start()
            return
        }

        await publish(.checking)
        do {
            let status = try await CKContainer(identifier: Self.containerIdentifier).accountStatus()
            guard status == .available else {
                lastIssue = Self.accountMessage(for: status)
                await publish(.attention, message: lastIssue)
                return
            }
            lastIssue = nil
            guard await enqueueOutbox() else {
                await publish(.attention, message: lastIssue)
                return
            }
            await publish(.syncing)
            guard let syncEngine else { return }
            try await syncEngine.fetchChanges()
            try await syncEngine.sendChanges()
            lastIssue = nil
            await refreshStatus(markSuccessful: true)
        } catch {
            lastIssue = Self.userMessage(for: error)
            await publish(.attention, message: lastIssue)
        }
    }

    public func refreshStatus() async {
        guard Self.isEnabled else {
            await publish(.disabled, pendingCount: 0)
            return
        }
        guard syncEngine != nil else {
            if let lastIssue {
                await publish(.attention, message: lastIssue)
            } else {
                await publish(.checking)
            }
            return
        }
        await refreshStatus(markSuccessful: false)
    }

    private func localChangesArrived() async {
        let didEnqueue = await enqueueOutbox()
        if let lastIssue {
            await publish(.attention, message: lastIssue)
        } else if !didEnqueue {
            await publish(.attention, message: "diple couldn’t queue the local changes for iCloud.")
        } else if syncEngine == nil {
            await publish(.checking)
        } else {
            await publish(.syncing)
        }
    }

    private static var recordZone: CKRecordZone {
        CKRecordZone(zoneID: CKRecordZone.ID(zoneName: zoneName))
    }

    private static var zoneID: CKRecordZone.ID { recordZone.zoneID }

    @discardableResult
    private func enqueueOutbox() async -> Bool {
        // The SQLite outbox already holds the edits when the engine has not started yet. There
        // is nothing to add to CKSyncEngine in that state, and it is not a failure.
        guard let syncEngine else { return true }
        do {
            let entries = try database.fetchSyncOutbox()
            let now = Date()
            // A record the outbox no longer carries — the book was deleted, the edit was
            // acknowledged — has nothing left to retry, so its failure history goes with it.
            let queued = Set(entries.compactMap { entry in
                entry.entity.map { Self.recordID(entity: $0, id: entry.entityID).recordName }
            })
            failedChanges = failedChanges.filter { queued.contains($0.key) }
            let pending = entries.compactMap { entry -> CKSyncEngine.PendingRecordZoneChange? in
                guard let entity = entry.entity, let operation = entry.pendingOperation else { return nil }
                let recordID = Self.recordID(entity: entity, id: entry.entityID)
                // The row stays in the durable outbox either way — this only decides whether it
                // is offered to CloudKit on this pass. A record still serving its backoff is
                // skipped here and nowhere else, so nothing is lost and nothing spins.
                if let failure = failedChanges[recordID.recordName], failure.readyAt > now { return nil }
                switch operation {
                case .save: return .saveRecord(recordID)
                case .delete: return .deleteRecord(recordID)
                }
            }
            syncEngine.state.add(pendingRecordZoneChanges: pending)
            scheduleDeferredRetry()
            return true
        } catch {
            Self.logger.error("Unable to read sync outbox: \(error.localizedDescription)")
            lastIssue = "diple couldn’t read the local changes waiting for iCloud."
            return false
        }
    }

    // MARK: Retry backoff

    /// Records the refusal and returns how many times this record has been refused in a row.
    /// Every failure sets a deadline; a caller that wants to try again straight away simply
    /// re-queues the record itself, which leaves the deadline standing as the fallback for when
    /// that immediate attempt also fails.
    @discardableResult
    private func noteFailedChange(_ recordID: CKRecord.ID) -> Int {
        let key = recordID.recordName
        let attempts = (failedChanges[key]?.attempts ?? 0) + 1
        let delay = min(Self.retryDelay * pow(2, Double(attempts - 1)), Self.maxRetryDelay)
        failedChanges[key] = ChangeFailure(attempts: attempts, readyAt: Date().addingTimeInterval(delay))
        return attempts
    }

    /// Re-queues a record whose failure has a known repair, as long as it has not already used
    /// up its immediate attempts.
    private func retrySoon(_ recordID: CKRecord.ID, in syncEngine: CKSyncEngine) {
        guard noteFailedChange(recordID) <= Self.immediateRetryLimit else { return }
        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    private func clearFailedChange(_ recordID: CKRecord.ID) {
        failedChanges[recordID.recordName] = nil
    }

    private func clearFailedChanges() {
        failedChanges.removeAll()
        deferredRetryTask?.cancel()
        deferredRetryTask = nil
    }

    /// Wakes once, at the earliest deadline, and offers the outbox again. Nothing else polls:
    /// a quiet library with one rejected record costs one sleeping task, not a heartbeat.
    private func scheduleDeferredRetry() {
        guard let earliest = failedChanges.values.map(\.readyAt).filter({ $0 > Date() }).min() else {
            deferredRetryTask?.cancel()
            deferredRetryTask = nil
            return
        }
        deferredRetryTask?.cancel()
        let delay = max(earliest.timeIntervalSinceNow, 1)
        deferredRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.runDeferredRetry()
        }
    }

    private func runDeferredRetry() async {
        deferredRetryTask = nil
        guard Self.isEnabled, syncEngine != nil else { return }
        // `enqueueOutbox` re-arms the next deadline itself, so a record that fails again lands
        // back here one longer interval later instead of immediately.
        await enqueueOutbox()
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
        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges:
            await publish(.syncing)
        case .didFetchRecordZoneChanges:
            await refreshStatus(markSuccessful: false)
        case .didFetchChanges, .didSendChanges:
            await refreshStatus(markSuccessful: true)
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
                Self.populate(book: book, tags: try database.fetchTags(forBookId: key.id), record: record)
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

    private static func populate(book: Book, tags: [String], record: CKRecord) {
        record["title"] = book.title as CKRecordValue
        record["author"] = book.author as CKRecordValue?
        record["fileName"] = URL(fileURLWithPath: book.filePath).lastPathComponent as CKRecordValue
        record["coverFileName"] = book.coverPath.map { URL(fileURLWithPath: $0).lastPathComponent } as CKRecordValue?
        record["addedAt"] = book.addedAt as CKRecordValue
        record["lastOpenedAt"] = book.lastOpenedAt as CKRecordValue?
        record["progress"] = NSNumber(value: book.progress)
        record["furthestProgress"] = NSNumber(value: book.furthestProgress)
        record["locator"] = book.locator as CKRecordValue?
        record["sourceURL"] = book.sourceURL as CKRecordValue?
        record["sourceKind"] = book.sourceKind.rawValue as CKRecordValue
        record["location"] = book.location.rawValue as CKRecordValue
        // A string list on the record itself, exactly as `DipleNote` already carries a note's
        // tags — a source's tags are part of what the source *is*, not a second synced entity.
        Self.write(tags: tags, to: record)
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
        Self.write(tags: note.tags, to: record)
    }

    // MARK: Tags on a record

    /// CloudKit infers a new field's type from the first value it ever sees, and an empty list
    /// carries no element type. Saving `[]` into a `tags` field the schema has not met yet is
    /// refused outright — *"cannot use an empty list to initialize a new field"* — and since an
    /// untagged book is the normal case, that refusal is permanent: the field is never created,
    /// so the next untagged book fails the same way, forever. The list is therefore written only
    /// when it has something in it.
    ///
    /// `tagsCount` is what an omitted list can no longer say on its own. Absent tags have always
    /// meant "this record predates tagging, keep whatever this device knows" — see
    /// `applyRemoteBook` — so without a second field, clearing the last tag off a source would
    /// be indistinguishable from an old record and would never reach the other devices. An
    /// Int64 needs no element type, so it is safe to write at zero.
    nonisolated static func write(tags: [String], to record: CKRecord) {
        if tags.isEmpty {
            record["tags"] = nil
        } else {
            record["tags"] = tags as CKRecordValue
        }
        record["tagsCount"] = NSNumber(value: tags.count)
    }

    /// `nil` means the record says nothing about tags; `[]` means the sender really has none.
    nonisolated static func tags(from record: CKRecord) -> [String]? {
        if let tags = record["tags"] as? [String] { return tags }
        return (record["tagsCount"] as? NSNumber) == nil ? nil : []
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
                lastIssue = "Some iCloud changes couldn’t be applied: \(error.localizedDescription)"
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
                lastIssue = "Some iCloud deletions couldn’t be applied: \(error.localizedDescription)"
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
                // Absent on a record saved before this field existed; `Book.init` falls back to
                // `progress` itself in that case rather than a bare 0, so an old record cannot
                // erase a synced reader's history.
                furthestProgress: (record["furthestProgress"] as? NSNumber)?.doubleValue,
                locator: record["locator"] as? String,
                sourceURL: record["sourceURL"] as? String,
                sourceKind: (record["sourceKind"] as? String).flatMap(PublicationKind.init(rawValue:)),
                // Absent on a record saved before the queue existed. `Book.init` defaults to
                // `.inbox`, which is right for a fresh save and wrong here — this is a book
                // from a library that predates the concept, so it gets the same rule the v15
                // backfill applies rather than being dumped into someone's inbox by sync.
                location: (record["location"] as? String).flatMap(BookLocation.init(rawValue:))
                    ?? .inferred(progress: (record["progress"] as? NSNumber)?.doubleValue ?? 0)
            )
            return try database.applyRemoteBook(
                book,
                // Absent means "saved before sources could be tagged", which is not the same as
                // "this source has no tags" — passing `[]` there would let one un-upgraded
                // device strip the tags off the whole library. `tags(from:)` is what still tells
                // the two apart now that an empty list is never written; see `write(tags:to:)`.
                tags: Self.tags(from: record),
                modifiedAt: modifiedAt,
                systemFields: systemFields
            )
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
                // A note carries its tags outright: a record without them is a note with none,
                // which is why the book's "absent means unknown" distinction does not apply.
                tags: Self.tags(from: record) ?? []
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
            clearFailedChange(record.recordID)
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
            clearFailedChange(recordID)
            guard let key = Self.parse(recordID: recordID) else { continue }
            try? database.acknowledgeDeletedRecord(entity: key.entity, id: key.id)
        }

        for failure in event.failedRecordSaves {
            guard let key = Self.parse(recordID: failure.record.recordID) else { continue }
            lastIssue = Self.userMessage(for: failure.error)
            switch failure.error.code {
            case .serverRecordChanged:
                if let serverRecord = failure.error.serverRecord {
                    // Whose *data* wins is decided inside, by modifiedAt. Which *version* of
                    // the record the next attempt is built from is not a choice: the server's
                    // change tag is the truth either way. Adopting it unconditionally is what
                    // stops a newer local edit from being retried forever against a stale tag
                    // and rejected every time — see `updateServerSystemFields`.
                    _ = try? await applyRemoteRecord(serverRecord)
                    if let systemFields = try? Self.archiveSystemFields(of: serverRecord) {
                        try? database.updateServerSystemFields(
                            entity: key.entity,
                            id: key.id,
                            systemFields: systemFields
                        )
                    }
                }
                retrySoon(failure.record.recordID, in: syncEngine)
            case .zoneNotFound:
                try? database.clearServerSystemFields(entity: key.entity, id: key.id)
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
                retrySoon(failure.record.recordID, in: syncEngine)
            case .unknownItem:
                try? database.clearServerSystemFields(entity: key.entity, id: key.id)
                retrySoon(failure.record.recordID, in: syncEngine)
            default:
                // Nothing here has a repair to apply, so nothing about the next second is
                // different from this one. The record waits out its backoff instead of being
                // re-offered by the `enqueueOutbox()` below.
                let attempts = noteFailedChange(failure.record.recordID)
                Self.logger.error(
                    """
                    iCloud refused \(failure.record.recordID.recordName, privacy: .public) \
                    (attempt \(attempts)): \(failure.error.localizedDescription, privacy: .public)
                    """
                )
            }
        }

        for (recordID, error) in event.failedRecordDeletes {
            guard let key = Self.parse(recordID: recordID) else { continue }
            if error.code == .unknownItem {
                clearFailedChange(recordID)
                try? database.acknowledgeDeletedRecord(entity: key.entity, id: key.id)
            } else if error.code == .zoneNotFound {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.recordZone)])
                // Same budget as a failed save: a delete that keeps missing its zone waits with
                // the rest rather than being re-offered on every callback.
                if noteFailedChange(recordID) <= Self.immediateRetryLimit {
                    syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
                }
            } else {
                lastIssue = Self.userMessage(for: error)
                noteFailedChange(recordID)
            }
        }
        await enqueueOutbox()
        await refreshStatus(markSuccessful: event.failedRecordSaves.isEmpty && event.failedRecordDeletes.isEmpty)
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
            lastIssue = nil
            await publish(.syncing)
        case .signOut:
            lastIssue = "Sign in to iCloud to continue syncing."
            await publish(.attention, message: lastIssue)
        @unknown default:
            break
        }
    }

    // MARK: Observable Status

    private func refreshStatus(markSuccessful: Bool) async {
        let pendingCount: Int
        do {
            pendingCount = try database.fetchSyncOutbox().count
        } catch {
            lastIssue = "diple couldn’t read the local changes waiting for iCloud."
            await publish(.attention, pendingCount: 0, message: lastIssue)
            return
        }
        // A completed CloudKit callback is not a successful health check if applying or
        // acknowledging that same cycle left an issue behind.
        let successfulAt = markSuccessful && lastIssue == nil ? Date() : nil

        if let lastIssue {
            await publish(
                .attention,
                pendingCount: pendingCount,
                message: lastIssue,
                successfulAt: successfulAt
            )
        } else if pendingCount > 0 {
            await publish(.syncing, pendingCount: pendingCount, successfulAt: successfulAt)
        } else {
            await publish(.synced, pendingCount: 0, successfulAt: successfulAt)
        }
    }

    private func publish(
        _ phase: CloudSyncSnapshot.Phase,
        pendingCount: Int? = nil,
        message: String? = nil,
        successfulAt: Date? = nil
    ) async {
        let count = pendingCount ?? ((try? database.fetchSyncOutbox().count) ?? 0)
        await CloudSyncStatusStore.shared.update(
            phase: phase,
            pendingCount: count,
            message: message,
            successfulAt: successfulAt
        )
    }

    private static func accountMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "iCloud is available."
        case .noAccount:
            return "Sign in to iCloud in System Settings to sync this library."
        case .restricted:
            return "iCloud access is restricted on this device."
        case .couldNotDetermine:
            return "diple couldn’t determine the current iCloud account status."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Your local changes are safe and will wait."
        @unknown default:
            return "iCloud isn’t available right now. Your local changes are safe and will wait."
        }
    }

    private static func userMessage(for error: Error) -> String {
        if let cloudError = error as? CKError {
            switch cloudError.code {
            case .notAuthenticated:
                return "Sign in to iCloud in System Settings to continue syncing."
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud is temporarily unavailable. Your local changes are safe and will retry."
            case .quotaExceeded:
                return "Your iCloud storage is full. Free some space, then check again."
            default:
                break
            }
        }
        // Everything left is a CloudKit diagnostic: a record ID, a zone, a field name. That text
        // belongs in the log, not in a settings row — printed there it filled half the screen
        // with an address the reader cannot act on and did not ask about.
        logger.error("Unhandled iCloud error: \(error.localizedDescription, privacy: .public)")
        return "Sync couldn’t finish. Your changes are safe on this device and diple will try again shortly."
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

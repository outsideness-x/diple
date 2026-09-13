import Foundation

/// Turns words left by the share sheet into notes in the Inbox, on the app's next activation.
///
/// Unlike an article, a note needs nothing from the network, so there is no retry schedule and no
/// banner: the words become a note in the same pass they are read, and the Inbox count is the
/// news. An entry is forgotten only after its note is written, and it is written under the entry's
/// own id, so an interrupted pass can neither lose a thought nor keep one twice.
enum SharedNoteDrain {
    private static var isListening = false

    /// Drains whenever the share sheet announces a write, for as long as the app runs — see
    /// `SharedNoteInbox.didEnqueueNotification`. Idempotent.
    static func listen() {
        guard !isListening else { return }
        isListening = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { SharedNoteDrain.run() }
                }
            },
            SharedNoteInbox.didEnqueueNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Drains the live App Group queue into the library. Quiet when there is nothing to do, which
    /// is almost every activation.
    static func run() {
        guard AppDatabase.startupFailure == nil, let inbox = try? SharedNoteInbox.live() else { return }
        let added = drain(inbox, into: .shared)
        if added > 0 {
            // Every screen that lists notes rereads on this — the same news it takes from iCloud.
            NotificationCenter.default.post(name: .dipleRemoteDataDidChange, object: nil)
        }
    }

    /// Returns how many notes were written. An entry that fails stays queued for the next pass.
    @discardableResult
    static func drain(_ inbox: SharedNoteInbox, into database: AppDatabase) -> Int {
        guard let pending = try? inbox.pending(), !pending.isEmpty else { return 0 }
        var added = 0
        for entry in pending {
            do {
                try NoteCapture.addToInbox(entry.text, id: entry.id.uuidString, in: database, now: entry.createdAt)
                try inbox.remove(id: entry.id)
                added += 1
            } catch NoteCapture.CaptureError.nothingToAdd {
                // Blank words can never become a note; keeping them would ask again forever.
                try? inbox.remove(id: entry.id)
            } catch {
                continue
            }
        }
        return added
    }
}

import AppIntents
import Foundation

/// New Note, from Shortcuts, Siri, Spotlight and the Action button: diple opens on a blank page
/// in the Inbox.
///
/// It opens the app because a new note is a page to write on, and a page needs the app. What can
/// be said in one breath goes to Today instead, without opening anything — `AddToTodayIntent`.
nonisolated struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note"
    static let description = IntentDescription("Opens a blank page in diple’s Inbox.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DipleShortcut.receive(.newNote)
        return .result()
    }
}

/// Add to Today: a line on today's page, written without the app coming up.
///
/// The capture a notes tool is judged by — a thought said to Siri at a crossing, or typed into a
/// Shortcut, lands on the day's page and the phone goes back in the pocket. The page is the one
/// already begun today, or a new one that begins with this line, exactly as the Desk's Today row
/// would make it. The reply names the day, so the writer hears where it went.
struct AddToTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Today"
    static let description = IntentDescription("Adds a line to today’s page in diple without opening the app.")

    @Parameter(title: "Text", requestValueDialog: "What should go on today’s page?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Today")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let day = try NoteCapture.addToToday(text, in: .shared)
        // Every screen that shows notes rereads on this, the same news it already takes from
        // iCloud: rows changed under it that it did not change itself.
        NotificationCenter.default.post(name: .dipleRemoteDataDidChange, object: nil)
        return .result(dialog: "Added to \(day).")
    }
}

/// The phrases Siri and Spotlight know without the reader building a Shortcut first. Each has to
/// name the app — the system requires it, and "new note" alone belongs to Apple Notes.
nonisolated struct DipleAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewNoteIntent(),
            phrases: [
                "New note in \(.applicationName)",
                "Write in \(.applicationName)"
            ],
            shortTitle: "New Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AddToTodayIntent(),
            phrases: [
                "Add to Today in \(.applicationName)",
                "Add to my \(.applicationName) day"
            ],
            shortTitle: "Add to Today",
            systemImageName: "sun.max"
        )
    }
}

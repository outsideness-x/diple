import AppIntents
import SwiftUI
import WidgetKit

#if !targetEnvironment(macCatalyst)
/// New Note in Control Center, on the Lock Screen and on the Action button's control list.
///
/// The control opens the app on the same address the widget's New note uses, so it lands where
/// every other way in lands: a blank page in the Inbox, opened from the Desk.
struct NewNoteControl: ControlWidget {
    static let kind = "diple.NewNoteControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenNewNotePageIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Note")
        .description("Opens a blank page in diple’s Inbox.")
    }
}

/// What the control runs: it asks the system to open `diple://new-note`.
///
/// Its own intent rather than the app's `NewNoteIntent`, because a control's action has to live in
/// this extension, and the app's intent calls into code the extension does not have. Hidden from
/// Shortcuts and Spotlight (`isDiscoverable`), where the app's New Note already stands — two
/// commands of one name would be a riddle.
struct OpenNewNotePageIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note"
    static let isDiscoverable = false

    enum Failure: Error {
        case noAddress
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let address = NotesAddress.newNote else { throw Failure.noAddress }
        return .result(opensIntent: OpenURLIntent(address))
    }
}
#endif

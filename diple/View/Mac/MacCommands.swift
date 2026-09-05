import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit
#endif

/// Every desktop action that can be asked for from outside the view that performs it — the
/// menu bar, a hardware key, or one screen handing off to another.
///
/// A desktop app is expected to be operable without the pointer, and the menu bar is where a
/// Mac user goes to *find out* that it is. But `commands` are attached to the `Scene`, above
/// the window's content, so a menu item cannot reach `MacRootView`'s state directly. One
/// notification carrying one enum keeps that hand-off to a single hop, instead of a dozen
/// separately named notifications that would each have to be remembered when a command is
/// added. The enum is the contract; the notification is only the wire.
enum MacCommand: String, Sendable, CaseIterable {
    // File
    case newNote
    case importFile
    case importLink
    // View
    case toggleSidebar
    case toggleInspector
    case refresh
    // Go
    case goLibrary
    case goUnread
    case goReading
    case goArticles
    case goHighlights
    case goNotes
    case goSearch
    // Reader — only ever answered while a book is open over the shell.
    case closeReader
    case findInBook
    case nextPage
    case previousPage
    case toggleReaderChrome
}

extension Notification.Name {
    /// A desktop command was invoked. Read it with `MacCommand.init(_:)`.
    static let dipleMacCommand = Notification.Name("diple.macCommand")
}

extension MacCommand {
    private static let payloadKey = "command"

    func post() {
        NotificationCenter.default.post(
            name: .dipleMacCommand,
            object: nil,
            userInfo: [Self.payloadKey: rawValue]
        )
    }

    /// The command a `.dipleMacCommand` notification carries, or `nil` if it carries something
    /// this build does not know about.
    init?(_ notification: Notification) {
        guard let raw = notification.userInfo?[Self.payloadKey] as? String,
              let command = MacCommand(rawValue: raw)
        else { return nil }
        self = command
    }
}

#if targetEnvironment(macCatalyst)

/// The menu bar.
///
/// Everything here is a *duplicate* of something reachable with the pointer: the menu bar is
/// how a Mac app teaches its own shortcuts, not a second set of features. The one exception is
/// New Window, which has no on-screen control because a window is not a thing inside a window.
struct DipleMacCommands: Commands {
    var body: some Commands {
        // Replaces SwiftUI's own "New Window ⌘N", which collided with the note the toolbar's
        // plus menu has always created on the same key.
        CommandGroup(replacing: .newItem) {
            Button("New Note") { MacCommand.newNote.post() }
                .keyboardShortcut("n", modifiers: .command)

            Button("New Window") { DipleMacWindows.openAnother() }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Import Publication…") { MacCommand.importFile.post() }
                .keyboardShortcut("o", modifiers: .command)

            Button("Save Link…") { MacCommand.importLink.post() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        // The app menu's Settings item. Without this, ⌘, exists only as a toolbar button and
        // the menu bar — the first place a Mac user looks — does not list it at all.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NotificationCenter.default.post(name: .dipleOpenSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // Nothing in this app prints or saves a document, and leaving the placeholders in
        // leaves a menu of permanently dimmed verbs.
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .saveItem) {}

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") { MacCommand.toggleSidebar.post() }
                .keyboardShortcut("s", modifiers: [.command, .control])

            Button("Toggle Inspector") { MacCommand.toggleInspector.post() }
                .keyboardShortcut("i", modifiers: [.command, .control])

            Divider()

            Button("Refresh") { MacCommand.refresh.post() }
                .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("Go") {
            Button("Library") { MacCommand.goLibrary.post() }
                .keyboardShortcut("1", modifiers: .command)
            Button("Unread") { MacCommand.goUnread.post() }
                .keyboardShortcut("2", modifiers: .command)
            Button("Reading") { MacCommand.goReading.post() }
                .keyboardShortcut("3", modifiers: .command)
            Button("Articles") { MacCommand.goArticles.post() }
                .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Highlights") { MacCommand.goHighlights.post() }
                .keyboardShortcut("5", modifiers: .command)
            Button("Notes") { MacCommand.goNotes.post() }
                .keyboardShortcut("6", modifiers: .command)

            Divider()

            Button("Search Everything") { MacCommand.goSearch.post() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find in Book") { MacCommand.findInBook.post() }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .help) {
            Link("diple. on the Web", destination: DipleLinks.website)
            Link("Privacy Policy", destination: DipleLinks.privacy)
        }
    }
}

/// Opening a second window on the same library.
///
/// SwiftUI's `openWindow` addresses a `WindowGroup` by id and this app has exactly one
/// unnamed group, so the UIKit request — which is what Catalyst turns that call into anyway —
/// is the shorter path and the one that cannot silently address nothing.
enum DipleMacWindows {
    @MainActor
    static func openAnother() {
        let request = UISceneSessionActivationRequest(role: .windowApplication)
        UIApplication.shared.activateSceneSession(for: request)
    }
}

/// Prunes the menus UIKit builds for every Catalyst app whether or not the app has the
/// feature behind them.
///
/// Format is not cosmetic housekeeping: it binds ⌘B and ⌘I to `UITextView`'s attributed-string
/// bold and italic, which is the *same pair of keys* the note editor's own formatting bar uses
/// for Markdown emphasis — two owners of one shortcut, and the text view wins because it is the
/// first responder. Removing the menu leaves the app's own binding as the only one.
final class DipleMenuBuilder: UIResponder, UIApplicationDelegate {
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        builder.remove(menu: .format)
        // Nothing in the window is a customisable toolbar, so "Customize Toolbar…" opens an
        // empty sheet.
        builder.remove(menu: .toolbar)
    }
}

#endif

/// The two addresses the Help menu and Settings both point at, spelled once.
enum DipleLinks {
    static let website = URL(string: "https://diple-reader.vercel.app")!
    static let privacy = URL(string: "https://diple-reader.vercel.app/privacy")!
}

extension Scene {
    /// The desktop menu bar, and nothing at all anywhere else.
    func dipleMacCommands() -> some Scene {
        #if targetEnvironment(macCatalyst)
        commands { DipleMacCommands() }
        #else
        self
        #endif
    }
}

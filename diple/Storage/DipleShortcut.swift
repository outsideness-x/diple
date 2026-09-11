import UIKit

/// The Home Screen quick actions: the two ways into the notes workshop that do not go through
/// the app first.
///
/// A notes tool is judged by how fast a thought gets down, and a long press on the icon is the
/// fastest route iOS offers without a widget. Both actions land in Notes; "New note" also opens
/// a blank page there, exactly as the bar's `+` does.
///
/// Installed from code rather than declared in `Info.plist`. The plist is shared with the Mac
/// build, where a Home Screen does not exist, and items set here can be localised like any
/// other string in the app.
@MainActor
enum DipleShortcut: String {
    case newNote = "com.chemical-pink.diple.newNote"
    case notes = "com.chemical-pink.diple.notes"

    /// A shortcut that arrived before anything could act on it. On a cold launch the scene
    /// connects — and hands over the item — before `RootTabView` exists to hear a notification,
    /// so the shell collects it on appear, the same arrangement the daily reminder already uses.
    private static var pending: DipleShortcut?

    static func install() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: newNote.rawValue,
                localizedTitle: String(localized: "New note"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "square.and.pencil")
            ),
            UIApplicationShortcutItem(
                type: notes.rawValue,
                localizedTitle: String(localized: "Notes"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "note.text")
            )
        ]
    }

    /// Records the shortcut and tells a shell that is already running. Returns whether the item
    /// was one of ours.
    @discardableResult
    static func receive(_ item: UIApplicationShortcutItem) -> Bool {
        guard let shortcut = DipleShortcut(rawValue: item.type) else { return false }
        pending = shortcut
        NotificationCenter.default.post(name: .dipleShortcut, object: nil)
        return true
    }

    /// The shortcut waiting to be acted on, handed out once.
    static func consume() -> DipleShortcut? {
        defer { pending = nil }
        return pending
    }
}

extension Notification.Name {
    /// A Home Screen quick action arrived; read it with `DipleShortcut.consume()`.
    static let dipleShortcut = Notification.Name("diple.shortcut")
}

#if !targetEnvironment(macCatalyst)
/// The app delegate on the phone, installed for one reason: a quick action is delivered to the
/// *scene* delegate, and a SwiftUI app only gets a scene delegate of its own by naming its class
/// here. SwiftUI keeps building and owning the window; this class only listens.
final class DipleAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        DipleShortcut.install()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = DipleSceneDelegate.self
        return configuration
    }
}

final class DipleSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// A cold launch from the icon: the item rides in on the connection options, and no
    /// `performActionFor` follows it.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            MainActor.assumeIsolated { _ = DipleShortcut.receive(item) }
        }
    }

    /// The app was already running.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = MainActor.assumeIsolated { DipleShortcut.receive(shortcutItem) }
        completionHandler(handled)
    }
}
#endif

import SwiftUI
import UIKit

/// The accent colours a reader can choose in Settings.
///
/// Raw values are the persisted representation — written into `AppSettings`, which travels
/// through the CloudKit settings payload — so a case must never be renamed once shipped.
public enum DipleAccent: String, CaseIterable, Codable, Sendable, Hashable {
    case lilac
    case mint
    case clay
    case periwinkle
    case brass

    /// What the picker shows. Kept apart from `rawValue` for the same reason as `ReaderFont`:
    /// the label can change without invalidating what is already stored on readers' devices.
    public var title: String {
        switch self {
        case .lilac: return "Lilac"
        case .mint: return "Mint"
        case .clay: return "Clay"
        case .periwinkle: return "Periwinkle"
        case .brass: return "Brass"
        }
    }

    /// Single source of truth for the colour: `color`/`uiColor` derive from it rather than
    /// duplicating the literal a second time.
    public var hex: String {
        switch self {
        case .lilac: return "#DF9BE1"
        case .mint: return "#6FD6B4"
        case .clay: return "#D97757"
        case .periwinkle: return "#8FA4F2"
        case .brass: return "#C8A45C"
        }
    }

    public var color: Color { Color(hex: hex) }

    /// Bridged from `color` rather than parsed a second time — it is a plain sRGB value, not a
    /// dynamic one, so the bridge needs no environment/trait context to resolve correctly.
    public var uiColor: UIColor { UIColor(color) }

    /// Name of the matching `.appiconset` in `Assets.xcassets`, or `nil` for the accent whose
    /// artwork ships as the primary set — brass, since it became the default. `nil` means "the
    /// primary" to `setAlternateIconName` whatever that set is called, so renaming it does not
    /// reach here.
    ///
    /// **The names carry the artwork, not just the colour, and that is deliberate.** iOS does
    /// not re-read an icon whose name is already the one in force: `AppIconManager` correctly
    /// skips the call when nothing changed, so a reader still on the old artwork under the same
    /// name keeps seeing it forever. Redrawing an icon therefore means renaming its set — which
    /// is what `Colophon` records here, and in `ASSETCATALOG_COMPILER_APPICON_NAME` for the
    /// primary. The next redesign renames them again.
    public var alternateIconName: String? {
        switch self {
        case .lilac: return "AppIconLilacColophon"
        case .mint: return "AppIconMintColophon"
        case .clay: return "AppIconClayColophon"
        case .periwinkle: return "AppIconPeriwinkleColophon"
        case .brass: return nil
        }
    }

    /// The one live value `DipleColor.accent`, `Color.dipleAccent` and `UIColor.dipleAccent`
    /// all read. `AppSettingsManager` is the sole writer — once on load, then again on every
    /// `settings.accent` change — which is what lets those three long-standing `static let`
    /// tokens become selectable without touching any of their ~94 call sites. Marked
    /// `@MainActor` explicitly (the project's default isolation already implies it) because
    /// this is the one piece of shared mutable state in the whole token system, and every
    /// reader — SwiftUI `body`, the UIKit reader layers — already runs there, so the actor
    /// itself is the synchronization; no separate lock is needed.
    @MainActor
    public static var current: DipleAccent = .brass
}

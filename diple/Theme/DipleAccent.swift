import SwiftUI
import UIKit

/// The accent colours a reader can choose in Settings.
///
/// Raw values are the persisted representation — written into `AppSettings`, which travels
/// through the CloudKit settings payload — so a raw value must never change once shipped. A
/// *case* can be renamed around its raw value, and `ink` is exactly that; see its note.
public enum DipleAccent: String, CaseIterable, Codable, Sendable, Hashable {
    /// The default since 2026-09-14, and first in the picker because of it: the colour of the
    /// icon Alex chose, a warm cream `>d.` in Mynerve on the dark plate.
    ///
    /// **Stored as `"brass"`, on purpose, exactly as Ink took `"periwinkle"`.** Vellum replaced
    /// Brass in the picker rather than joining it — two warm yellows a shade apart offer one
    /// colour twice — and it took Brass's stored value instead of adding a new one, because an
    /// older build that receives an unknown raw value through iCloud fails to decode the
    /// reader's settings wholesale (see `ink`). A reader who had chosen Brass gets Vellum.
    ///
    /// It sits in the yellow hue family that made Brass step down as the default, but far
    /// lighter and quieter than Brass: beside the `#FFD60A` highlight it reads as paper rather
    /// than as a faded copy of the mark.
    case vellum = "brass"
    /// The default from 2026-09-11 to 2026-09-14, and still a choice.
    ///
    /// **Stored as `"periwinkle"`, on purpose.** Ink replaced Periwinkle — the two swatches were
    /// a shade apart, and a picker offering both offers one colour twice — and it took over
    /// Periwinkle's stored value instead of adding a new one. A new raw value is not a safe
    /// change here: `AppSettings` decodes the accent with `decodeIfPresent`, which *throws* on
    /// a value it does not recognise rather than falling back, so an older build receiving
    /// `"ink"` through iCloud would fail to decode the reader's settings wholesale. Every build
    /// that has shipped already knows `"periwinkle"`; it simply paints it a little differently.
    ///
    /// Blue because it is the one hue none of the four highlight colours occupy — blue was
    /// withdrawn from the marks — so the accent can never be mistaken for a passage somebody
    /// marked. And ink because the accent in diple is always the reader's own act, and blue ink
    /// is what a reader's pen leaves in a margin.
    case ink = "periwinkle"
    case lilac
    case mint
    case clay

    /// What the picker shows. Kept apart from `rawValue` for the same reason as `ReaderFont`:
    /// the label can change without invalidating what is already stored on readers' devices.
    public var title: String {
        switch self {
        case .vellum: return "Vellum"
        case .ink: return "Ink"
        case .lilac: return "Lilac"
        case .mint: return "Mint"
        case .clay: return "Clay"
        }
    }

    /// Single source of truth for the colour: `color`/`uiColor` derive from it rather than
    /// duplicating the literal a second time.
    public var hex: String {
        switch self {
        case .vellum: return "#E6D4B5"
        case .ink: return "#86A8FF"
        case .lilac: return "#DF9BE1"
        case .mint: return "#6FD6B4"
        case .clay: return "#D97757"
        }
    }

    public var color: Color { Color(hex: hex) }

    /// The same colour, darkened until it is legible as *text* on light paper.
    ///
    /// Every accent in the picker is a mid-to-light tint — that is what makes `textOnAccent`
    /// work as dark ink on a filled chip — and the same property makes all five fail WCAG
    /// contrast the moment one is used as a foreground colour on the light canvas: mint
    /// measures 1.76:1 against white, Vellum 1.32:1 against the light canvas, and the floor for
    /// text is 4.5:1. On the dark canvas Vellum gives 13.5:1, so this is a light-appearance value
    /// only, which is why `DipleColor.accentInk` resolves to `hex` in dark and to this in light.
    ///
    /// Hue is kept and only lightness is taken out, so a reader who chose mint still gets a
    /// green sentence rather than a different colour's.
    ///
    /// Ink's is Periwinkle's old ink moved onto Ink's hue — the same lightness and saturation,
    /// 5.9:1 on white — rather than Ink darkened at its own saturation, which came out as an
    /// electric `#2360FF` far louder than the other four and read as a link from another app.
    ///
    /// Vellum's is its own hue (38°) at 35% saturation, darkened to 5.97:1 on white — the band
    /// Ink and Clay sit in. At Vellum's own 50% saturation the same contrast came out as the
    /// ochre Brass's ink already was, which is the colour Vellum replaced.
    public var inkHex: String {
        switch self {
        case .vellum: return "#776039"
        case .ink: return "#4261B2"
        case .lilac: return "#8E4E90"
        case .mint: return "#1F7A5C"
        case .clay: return "#A34A2A"
        }
    }

    /// Bridged from `color` rather than parsed a second time — it is a plain sRGB value, not a
    /// dynamic one, so the bridge needs no environment/trait context to resolve correctly.
    public var uiColor: UIColor { UIColor(color) }

    /// Name of the matching `.appiconset` in `Assets.xcassets`, or `nil` for the accent whose
    /// artwork ships as the primary set — Vellum, since it became the default. `nil` means "the
    /// primary" to `setAlternateIconName` whatever that set is called, so renaming it does not
    /// reach here.
    ///
    /// **The names carry the artwork, not just the colour, and that is deliberate.** iOS does
    /// not re-read an icon whose name is already the one in force: `AppIconManager` correctly
    /// skips the call when nothing changed, so a reader still on the old artwork under the same
    /// name keeps seeing it forever. Redrawing an icon therefore means renaming its set — which
    /// is what `Scripts/generate_icons.py` records as `SUFFIX`, and what
    /// `ASSETCATALOG_COMPILER_APPICON_NAME` names for the primary. The next redesign renames
    /// them again.
    public var alternateIconName: String? {
        switch self {
        case .vellum: return nil
        case .ink: return "AppIconInkMynerve"
        case .lilac: return "AppIconLilacMynerve"
        case .mint: return "AppIconMintMynerve"
        case .clay: return "AppIconClayMynerve"
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
    public static var current: DipleAccent = .vellum
}

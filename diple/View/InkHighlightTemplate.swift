import ReadiumNavigator
import UIKit

/// Binds `InkHighlightCSS` to Readium's decoration machinery.
///
/// The stroke plays **once, at the moment of marking**. Readium re-lays out decorations on every
/// reflow — a page turn, a font-size tick, a rotation — and an animation living on the element
/// alone would replay on every one of them, which is a page whose highlights redraw themselves
/// each time you come back to it. Freshness therefore travels as data on the decoration
/// (`Decoration.userInfo`, which Readium explicitly leaves to the app), the reader's view model
/// holds it for exactly as long as the ink is wet, and the decorations are applied a second time
/// without it. The second write is not a workaround: the passage genuinely stopped being new,
/// and that is a change to what is being drawn.
enum InkHighlight {
    /// Carried on the one decoration the reader has just created.
    static let freshKey: AnyHashable = "diple.ink.fresh"

    static var duration: Int { InkHighlightCSS.duration }

    static func template(defaultTint: UIColor) -> HTMLDecorationTemplate {
        HTMLDecorationTemplate(
            layout: .boxes,
            element: { decoration in
                let config = decoration.style.config as? Decoration.Style.HighlightConfig
                let tint = config?.tint ?? defaultTint
                let isFresh = (decoration.userInfo[freshKey] as? Bool) == true
                return InkHighlightCSS.element(ink: rgba(tint), isFresh: isFresh)
            },
            stylesheet: InkHighlightCSS.stylesheet
        )
    }

    /// A mark's pigment at the strength it lies on the page with.
    ///
    /// 0.42, not the 0.3 Readium's own template uses (and diple used until 2026-09-30). The
    /// system colours the marks used to be were neon, and a third of neon was a clearly visible
    /// highlighter. The pigments that replaced them (`MarkPigment`) are quieter by design, and at
    /// 0.3 the sage and the lavender measured barely a shade off the paper: a mark has to be
    /// seen at a glance, or it has stopped being a mark. The same strength over a night page
    /// keeps the text on it above 4.4:1, because the box lies over the words, not under them.
    private static func rgba(_ color: UIColor, alpha: Double = 0.42) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var opacity: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &opacity) else {
            return "rgba(255, 214, 10, \(alpha))"
        }
        return "rgba(\(Int(red * 255)), \(Int(green * 255)), \(Int(blue * 255)), \(alpha))"
    }
}

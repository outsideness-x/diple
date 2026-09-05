import Foundation

/// The mark is *made*, not switched on.
///
/// Picking a colour is the single most frequent act in this app, and until now its result
/// appeared — the passage was one colour in one frame and another in the next. A reader marking
/// a page draws; the colour arrives across the words at the speed of a pen, line after line,
/// with the leading edge soft where the ink is still spreading. Nothing about the passage is
/// different afterwards. What changed is that the app stopped skipping the part the reader did.
///
/// It plays **once, at the moment of marking**. Readium re-lays out decorations on every reflow
/// — a page turn, a font-size tick, a rotation — and an animation living on the element alone
/// would replay on every one of them, which is a page whose highlights redraw themselves each
/// time you come back to it. Freshness therefore travels as data on the decoration
/// (`Decoration.userInfo`, which Readium explicitly leaves to the app), the reader's view model
/// holds it for exactly as long as the ink is wet, and the decorations are applied a second time
/// without it. The second write is not a workaround: the passage genuinely stopped being new,
/// and that is a change to what is being drawn.
enum InkHighlightCSS {
    /// The class every highlight box carries.
    static let className = "diple-ink-highlight"
    /// The attribute that marks the one passage whose ink is still wet.
    static let freshAttribute = "data-diple-ink"
    static let freshValue = "fresh"

    /// How long the stroke takes to cross one line, and how far behind the previous line the
    /// next one starts. A pen crosses a phone-width line in about a quarter of a second; the
    /// stagger is what makes four lines read as one continuous hand rather than four boxes
    /// filling at once.
    static let lineDuration = 260
    static let lineStagger = 70
    /// Lines after this share the last delay. A passage twelve lines long is a page, not a
    /// sentence, and stretching the stagger over it would make the last line arrive a second
    /// and a half after the tap.
    static let staggeredLines = 12

    /// Total time the ink is wet, which is what the view model holds the freshness flag for.
    static var duration: Int { lineDuration + lineStagger * (staggeredLines - 1) }

    /// **Fitted to a hand, not picked from the easing menu.** A highlighter moves at the speed
    /// of an arm and stops where the word stops; the standard ease-outs put two thirds of the
    /// stroke in the first quarter of the time, which reads as a snap, not a stroke. Measured in
    /// WebKit through `Scripts/ink-stroke-profile.swift`, this curve covers 28% of the line at a
    /// quarter of the duration, 55% at half and 80% at three quarters — near constant speed,
    /// with the small lag at the start that a nib takes to catch.
    static let easing = "cubic-bezier(0.45, 0.5, 0.7, 0.8)" 

    static func element(ink: String, isFresh: Bool) -> String {
        let fresh = isFresh ? " \(freshAttribute)=\"\(freshValue)\"" : ""
        return "<div class=\"\(className)\"\(fresh) style=\"--diple-ink: \(ink);\"></div>"
    }

    /// Readium's own geometry for a highlight box — the same negative margin, padding and corner
    /// radius — because the mark must sit on the words exactly where it always has. What is not
    /// carried over is the underline border: diple's highlights are a fill, the `isActive`
    /// variant is never used, and a rule whose colour comes from an unset custom property is a
    /// hairline waiting to appear in whatever the text colour happens to be.
    static var stylesheet: String {
        let delays = (0..<staggeredLines)
            .map { index in
                """
                .\(className)[\(freshAttribute)="\(freshValue)"]:nth-child(\(index + 1)) {
                    animation-delay: \(index * lineStagger)ms;
                }
                """
            }
            .joined(separator: "\n")

        return """
        .\(className) {
            margin: 0 -1px 0 0;
            padding: 0 2px 0 0;
            border-radius: 3px;
            box-sizing: border-box;
            background-color: var(--diple-ink);
            z-index: var(--decoration-z-index);
        }

        /* The stroke. The fill is a gradient rather than a plain colour so the leading edge can
           be soft: 14px of ink still spreading, which is what tells a drawn mark from a wipe.
           It is painted from the left in both writing directions on purpose — the mark follows
           the hand, and the hand is the reader's, not the text's. */
        .\(className)[\(freshAttribute)="\(freshValue)"] {
            background-color: transparent;
            background-image: linear-gradient(
                to right,
                var(--diple-ink) 0%,
                var(--diple-ink) calc(100% - 14px),
                rgba(0, 0, 0, 0) 100%
            );
            background-repeat: no-repeat;
            background-position: left center;
            background-size: 0% 100%;
            animation: diple-ink-stroke \(lineDuration)ms \(easing) both;
        }

        \(delays)

        .\(className)[\(freshAttribute)="\(freshValue)"]:nth-child(n + \(staggeredLines + 1)) {
            animation-delay: \((staggeredLines - 1) * lineStagger)ms;
        }

        /* Overshoot, so the soft edge finishes past the end of the box and the mark settles as
           flat colour. Ending at 100% would leave every line fading out at its right edge. */
        @keyframes diple-ink-stroke {
            from { background-size: 0% 100%; }
            to { background-size: 130% 100%; }
        }

        /* The web view follows the system setting, so this needs no wiring on the Swift side.
           Reduce Motion gets the mark, immediately — the point was never the movement. */
        @media (prefers-reduced-motion: reduce) {
            .\(className)[\(freshAttribute)="\(freshValue)"] {
                animation: none;
                background-image: none;
                background-color: var(--diple-ink);
            }
        }
        """
    }
}

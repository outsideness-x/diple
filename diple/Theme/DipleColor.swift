import SwiftUI
import UIKit

/// Semantic colour tokens.
///
/// Every colour in the app resolves to one of these. Literal `Color(red:green:blue:)` at a
/// call site is a bug: it puts a value outside the ramp and the ramp is what makes the
/// surfaces read as one material instead of twenty near-identical greys.
///
/// Two rules the ramp encodes:
///
/// - **No pure black.** `canvas` is `#0B0B0F`, not `#000000`. A true black has no depth —
///   anything laid on it looks pasted rather than lit, and OLED smearing during scroll is
///   worse. Every surface carries a cold blue undertone (blue channel above red and green),
///   which is what makes a dark UI feel deep rather than muddy.
/// - **Text is translucent, surfaces are opaque.** Foreground tokens are the theme's ink at an
///   opacity, so they composite correctly over any surface in the ramp *and* over the blurred
///   materials used by the reader bars and sheets — a solid grey that reads right on
///   `surface` goes muddy the moment it lands on a material.
///
/// Every token is a **dynamic colour**: one value for each appearance, resolved against the
/// trait collection rather than read from a setting. That is what lets the app carry a light
/// theme without touching any of the several hundred call sites, and it means the UIKit layers
/// of the reader repaint on the same signal as the SwiftUI ones.
///
/// The two ramps are not inversions of each other. On dark, higher means lighter, and the
/// canvas is the darkest thing on screen. On light, the canvas is a soft grey and cards are
/// **white** — paper laid on a desk, not a grey card on a white wall. Inverting the dark ramp
/// literally would put white behind everything and grey cards on top, which is the arrangement
/// that makes a light interface look like an unstyled form.
public enum DipleColor {

    /// One token, two values. `UIColor`'s dynamic provider is the only mechanism that resolves
    /// per trait collection, so SwiftUI, UIKit and the reader's navigator all read the same
    /// answer without a parallel lookup.
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func ink(_ opacity: CGFloat) -> Color {
        adaptive(
            light: UIColor(white: 0.05, alpha: opacity),
            dark: UIColor(white: 1, alpha: opacity)
        )
    }

    // MARK: - Surfaces

    /// The floor of the app. Window and scroll-view backgrounds.
    public static let canvas = adaptive(
        light: UIColor(red: 0.957, green: 0.957, blue: 0.969, alpha: 1),
        dark: UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
    )

    /// Cards and rows sitting directly on the canvas.
    public static let surface = adaptive(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.075, blue: 0.094, alpha: 1)
    )

    /// Sheets, popovers and anything stacked above a card.
    public static let surfaceRaised = adaptive(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.102, green: 0.102, blue: 0.129, alpha: 1)
    )

    /// Controls inside a raised surface: segment backgrounds, chips, progress tracks.
    /// On light this goes *down* from the card rather than up: a control set into paper.
    public static let surfaceOverlay = adaptive(
        light: UIColor(red: 0.925, green: 0.925, blue: 0.945, alpha: 1),
        dark: UIColor(red: 0.137, green: 0.137, blue: 0.173, alpha: 1)
    )

    // MARK: - Lines and edges

    /// The default one-off border that separates a surface from what is behind it.
    public static let hairline = ink(0.10)

    /// For edges that must survive over a light or sepia reader page.
    public static let hairlineStrong = ink(0.16)

    /// Top edge of the double-contour treatment. On dark it is the light a bevel would catch;
    /// on light a white bevel on a white card is invisible, so the gradient runs the other way
    /// — a soft top edge deepening towards the bottom, which is the same carved read.
    public static let insetHighlight = adaptive(
        light: UIColor(white: 0.05, alpha: 0.04),
        dark: UIColor(white: 1, alpha: 0.06)
    )

    /// Dividers inside a list, which sit lower than a border between two surfaces.
    public static let separator = ink(0.08)

    // MARK: - Foreground

    /// Titles and body copy.
    public static let textPrimary = ink(0.93)

    /// Supporting copy and active icons.
    public static let textSecondary = ink(0.70)

    /// Metadata: authors, dates, counts, section headers.
    public static let textTertiary = ink(0.52)

    /// The quietest readable level: chevrons, disabled controls, timestamps on a card.
    public static let textQuaternary = ink(0.38)

    /// Text and glyphs printed on a filled accent surface. Stays dark in both themes: every
    /// accent is a mid-to-light tint, so dark ink is the legible pairing on all five in either
    /// appearance, and flipping it to white on light would fail contrast on mint and lilac.
    public static let textOnAccent = Color(red: 0.043, green: 0.043, blue: 0.059)

    // MARK: - Accent

    /// Selected accent. Mirrors `Color.dipleAccent`, which predates this ramp and stays for
    /// the UIKit layers of the reader. Computed, not `let`: a `static let` would capture
    /// whichever accent was current at first access and never see a later change.
    public static var accent: Color { Color.dipleAccent }

    /// Accent as a background: chips, selected states, icon wells.
    public static var accentSoft: Color { Color.dipleAccent.opacity(0.14) }

    /// Accent as light rather than paint — the radial falloff behind an interactive element.
    /// Colour is directed with glow, not with saturated fills.
    public static var accentGlow: Color { Color.dipleAccent.opacity(0.30) }

    /// Accent as **text**. The only accent token allowed in a `foregroundStyle`.
    ///
    /// `accent` is a fill colour: it is read through `textOnAccent`, which is dark ink, and it
    /// is chosen to be light enough for that to work. Printing it *as* ink on the light canvas
    /// inverts the arrangement and drops every accent below 3:1 — see `DipleAccent.inkHex`. So
    /// foreground and fill are two tokens, and the split is by appearance: light takes the
    /// darkened value, dark takes the accent unchanged, where it already measures 8:1.
    ///
    /// Computed rather than `static let` for the same reason as `accent` above: a stored value
    /// would capture whichever accent was current at first access and never see a later change.
    public static var accentInk: Color {
        adaptive(
            light: UIColor(Color(hex: DipleAccent.current.inkHex)),
            dark: UIColor(DipleAccent.current.color)
        )
    }

    // MARK: - Status

    /// Both are darkened for light: the dark-theme values are tuned to glow against #0B0B0F
    /// and drop under 3:1 against white, which is below the floor for a control's own colour.
    public static let destructive = adaptive(
        light: UIColor(red: 0.84, green: 0.09, blue: 0.24, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.22, blue: 0.37, alpha: 1)
    )
    public static let success = adaptive(
        light: UIColor(red: 0.10, green: 0.58, blue: 0.26, alpha: 1),
        dark: UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)
    )

    // MARK: - Highlight palette

    /// The colours a reader can mark a passage with. Hex is the stored value — `Highlight`
    /// persists `colorHex`, so these must stay in sync with what is already in the database.
    public enum Highlight {
        public static let lilac = "#DF9BE1"
        public static let yellow = "#FFD60A"
        public static let green = "#30D158"
        public static let pink = "#FF375F"

        /// Withdrawn from the picker, kept for the data.
        ///
        /// Passages already marked blue are in the database, in the CloudKit record, in the
        /// export and on the page, so the constant stays: retiring a colour must not reach
        /// backwards into quotes that were saved in good faith. What changed is only that
        /// nothing offers it for a *new* mark — it is absent from `selectable`, and that is
        /// the whole of it.
        ///
        /// Nothing anywhere matches a stored colour against the palette, which is what makes
        /// that split safe. The reader (`ReadiumNavigator.Color(hex:)`), the quote list and
        /// the hub (`Color(hex:)`) and the portable export (the raw string) all resolve
        /// `Highlight.colorHex` as six bytes with no notion of membership, and there is
        /// deliberately no `switch` over the palette in the app — one would need a case for
        /// every colour ever retired, and would trap on the first old row it met.
        public static let blue = "#64D2FF"

        /// What a passage may be marked *with*, in bar order.
        ///
        /// Four, not five. The bar has to carry the palette, translate, note, copy and delete
        /// in a single row at 375 pt with 44 pt hit targets, and that budget is 8 controls
        /// wide; blue was also the swatch that read closest to the accent it sat beside.
        public static let selectable: [(name: String, hex: String)] = [
            ("Lilac", lilac),
            ("Yellow", yellow),
            ("Green", green),
            ("Pink", pink)
        ]

        public static func color(forHex hex: String) -> Color { Color(hex: hex) }
    }

    // MARK: - Reader page themes

    /// Page colours for the reader's own four named themes (Paper / Sepia / Carbon / Ink).
    /// These describe a sheet of paper, not the app chrome, so they sit outside the cold ramp
    /// above by design.
    ///
    /// These are no longer Readium's own per-appearance defaults. `ReaderSettings
    /// .epubPreferences(for:)` sets `EPUBPreferences.backgroundColor`/`.textColor` explicitly
    /// for every theme — Readium's own `Theme` only selects which of its three built-in
    /// behaviours (image filter, night-mode link colour) applies, not the colour itself — which
    /// is what lets Paper be warmer than Readium's plain white and lets Carbon and Ink share
    /// `.dark` while differing in exactly one byte pair. `ReaderPageTheme` in
    /// `Model/ReaderSettings.swift` hands Readium the hex strings defined here, so this file is
    /// the one place each byte is written down. Since the page no longer covers the whole
    /// display — it stops at the safe area, so the status bar and the resting progress line have
    /// a band of their own — anything short of an exact match to what `EPUBPreferences` actually
    /// sets would draw a seam across the top and bottom of every page. See "Вёрстка страницы
    /// читалки" in CLAUDE.md.
    public enum Page {
        public static let paperBackgroundHex = "#FBF8F1"
        public static let paperTextHex = "#1A1714"
        public static let sepiaBackgroundHex = "#FAF4E8"
        public static let sepiaTextHex = "#33261A"
        public static let carbonBackgroundHex = "#121214"
        public static let carbonTextHex = "#E8E4DC"
        public static let inkBackgroundHex = "#000000"
        public static let inkTextHex = "#D6D2CA"

        public static let paperBackground = Color(hex: paperBackgroundHex)
        public static let paperText = Color(hex: paperTextHex)
        public static let sepiaBackground = Color(hex: sepiaBackgroundHex)
        public static let sepiaText = Color(hex: sepiaTextHex)
        public static let carbonBackground = Color(hex: carbonBackgroundHex)
        public static let carbonText = Color(hex: carbonTextHex)
        public static let inkBackground = Color(hex: inkBackgroundHex)
        public static let inkText = Color(hex: inkTextHex)
    }
}

/// Mirrors of the tokens the UIKit side of the reader needs. Readium's navigator is
/// configured with `UIColor`, and duplicating the literals there would put the ramp out of
/// sync the first time a value is tuned.
public extension UIColor {
    private static func dipleAdaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    static let dipleCanvas = dipleAdaptive(
        light: UIColor(red: 0.957, green: 0.957, blue: 0.969, alpha: 1),
        dark: UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
    )
    static let dipleSurface = dipleAdaptive(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.075, blue: 0.094, alpha: 1)
    )
    static let dipleSurfaceRaised = dipleAdaptive(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.102, green: 0.102, blue: 0.129, alpha: 1)
    )
}

#Preview("Colour ramp") {
    ScrollView {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            swatchRow("Surfaces", [
                ("canvas", DipleColor.canvas),
                ("surface", DipleColor.surface),
                ("surfaceRaised", DipleColor.surfaceRaised),
                ("surfaceOverlay", DipleColor.surfaceOverlay)
            ])

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text("FOREGROUND").dipleType(.nano).foregroundStyle(DipleColor.textTertiary)
                Text("textPrimary").dipleType(.body).foregroundStyle(DipleColor.textPrimary)
                Text("textSecondary").dipleType(.body).foregroundStyle(DipleColor.textSecondary)
                Text("textTertiary").dipleType(.body).foregroundStyle(DipleColor.textTertiary)
                Text("textQuaternary").dipleType(.body).foregroundStyle(DipleColor.textQuaternary)
            }

            swatchRow("Accent", [
                ("accent", DipleColor.accent),
                ("accentSoft", DipleColor.accentSoft),
                ("accentGlow", DipleColor.accentGlow),
                ("destructive", DipleColor.destructive)
            ])
        }
        .padding(DipleSpace.l)
    }
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}

@ViewBuilder
private func swatchRow(_ title: String, _ items: [(String, Color)]) -> some View {
    VStack(alignment: .leading, spacing: DipleSpace.s) {
        Text(title.uppercased()).dipleType(.nano).foregroundStyle(DipleColor.textTertiary)
        HStack(spacing: DipleSpace.s) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: DipleSpace.xs) {
                    RoundedRectangle(cornerRadius: DipleRadius.s)
                        .fill(item.1)
                        .frame(height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: DipleRadius.s)
                                .stroke(DipleColor.hairline, lineWidth: 0.5)
                        )
                    Text(item.0).dipleType(.nano).foregroundStyle(DipleColor.textTertiary)
                }
            }
        }
    }
}

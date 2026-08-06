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
/// - **Text is translucent, surfaces are opaque.** Foreground tokens are white at an opacity,
///   so they composite correctly over any surface in the ramp *and* over the blurred
///   materials used by the reader bars and sheets — a solid grey that reads right on
///   `surface` goes muddy the moment it lands on a material.
public enum DipleColor {

    // MARK: - Surfaces

    /// The floor of the app. Window and scroll-view backgrounds.
    public static let canvas = Color(red: 0.043, green: 0.043, blue: 0.059)

    /// Cards and rows sitting directly on the canvas.
    public static let surface = Color(red: 0.075, green: 0.075, blue: 0.094)

    /// Sheets, popovers and anything stacked above a card.
    public static let surfaceRaised = Color(red: 0.102, green: 0.102, blue: 0.129)

    /// Controls inside a raised surface: segment backgrounds, chips, progress tracks.
    public static let surfaceOverlay = Color(red: 0.137, green: 0.137, blue: 0.173)

    // MARK: - Lines and edges

    /// The default one-off border that separates a surface from what is behind it.
    public static let hairline = Color.white.opacity(0.08)

    /// For edges that must survive over a light or sepia reader page.
    public static let hairlineStrong = Color.white.opacity(0.14)

    /// Top-edge highlight of the double-contour treatment: the light that would catch the
    /// bevel if the card were a physical object. Paired with `hairline`, never used alone.
    public static let insetHighlight = Color.white.opacity(0.06)

    /// Dividers inside a list, which sit lower than a border between two surfaces.
    public static let separator = Color.white.opacity(0.06)

    // MARK: - Foreground

    /// Titles and body copy.
    public static let textPrimary = Color.white.opacity(0.93)

    /// Supporting copy and active icons.
    public static let textSecondary = Color.white.opacity(0.72)

    /// Metadata: authors, dates, counts, section headers.
    public static let textTertiary = Color.white.opacity(0.52)

    /// The quietest readable level: chevrons, disabled controls, timestamps on a card.
    public static let textQuaternary = Color.white.opacity(0.36)

    /// Text and glyphs printed on a filled accent surface.
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

    // MARK: - Status

    public static let destructive = Color(red: 1.0, green: 0.22, blue: 0.37)
    public static let success = Color(red: 0.19, green: 0.82, blue: 0.35)

    // MARK: - Highlight palette

    /// The colours a reader can mark a passage with. Hex is the stored value — `Highlight`
    /// persists `colorHex`, so these must stay in sync with what is already in the database.
    public enum Highlight {
        public static let lilac = "#DF9BE1"
        public static let yellow = "#FFD60A"
        public static let green = "#30D158"
        public static let pink = "#FF375F"
        public static let blue = "#64D2FF"

        public static let all: [(name: String, hex: String)] = [
            ("Lilac", lilac),
            ("Yellow", yellow),
            ("Green", green),
            ("Pink", pink),
            ("Blue", blue)
        ]

        public static func color(forHex hex: String) -> Color { Color(hex: hex) }
    }

    // MARK: - Reader page themes

    /// Page colours for the reader's own themes. These describe a sheet of paper, not the
    /// app chrome, so they sit outside the cold ramp above by design.
    public enum Page {
        public static let sepiaBackground = Color(red: 0.98, green: 0.95, blue: 0.90)
        public static let sepiaText = Color(red: 0.2, green: 0.15, blue: 0.1)
    }
}

/// Mirrors of the tokens the UIKit side of the reader needs. Readium's navigator is
/// configured with `UIColor`, and duplicating the literals there would put the ramp out of
/// sync the first time a value is tuned.
public extension UIColor {
    static let dipleCanvas = UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
    static let dipleSurface = UIColor(red: 0.075, green: 0.075, blue: 0.094, alpha: 1)
    static let dipleSurfaceRaised = UIColor(red: 0.102, green: 0.102, blue: 0.129, alpha: 1)
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

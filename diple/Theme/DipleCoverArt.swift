import SwiftUI
import UIKit

/// Artwork for a publication that shipped without any.
///
/// Most EPUBs imported by hand have no cover image, so the placeholder is not an edge case —
/// it is what the library mostly looks like. It used to be a gradient between two ramp
/// surfaces with a single initial in the corner, which on the dark theme read as a dim card
/// and on light was literally a white rectangle, because `surface` and `surfaceRaised` are
/// both white there. A wall of blank rectangles is the opposite of a shelf: nothing to
/// recognise, nothing to aim at, and every book looks like every other book.
///
/// So the cover is generated instead of merely absent. Colour is derived from the title, which
/// makes it **stable** — the same book is the same colour on every launch and on every device,
/// with nothing stored and no migration — and makes the grid scannable by shape and hue the
/// way a real shelf is.
///
/// These values are deliberately outside `DipleColor`'s ramp, for the same reason the
/// highlight palette and the reader's page themes are: this is content, not chrome. The ramp
/// exists so interface surfaces read as one material; artwork's job is to differ.
public enum DipleCoverArt {

    /// A hue in 0..<1, stable for a given title.
    ///
    /// djb2 rather than `hashValue`: Swift's hashing is seeded per process, so the same book
    /// would change colour every time the app launched.
    static func hue(for seed: String) -> CGFloat {
        var hash: UInt64 = 5381
        for byte in seed.unicodeScalars.map(\.value) {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        // 24 steps rather than a continuous hue: neighbouring books land in visibly different
        // families instead of two greens a reader cannot tell apart.
        return CGFloat(hash % 24) / 24
    }

    /// The two stops of the cover's field.
    ///
    /// Light keeps the tint pale enough to carry dark ink; dark keeps it deep enough not to
    /// glow on an OLED page of otherwise near-black surfaces. Saturation stays low in both:
    /// this is a bookcloth, not a highlighter.
    public static func gradient(for seed: String) -> LinearGradient {
        let hue = hue(for: seed)
        return LinearGradient(
            colors: [
                DipleColor.adaptive(
                    light: UIColor(hue: hue, saturation: 0.18, brightness: 0.97, alpha: 1),
                    dark: UIColor(hue: hue, saturation: 0.40, brightness: 0.26, alpha: 1)
                ),
                DipleColor.adaptive(
                    light: UIColor(hue: hue, saturation: 0.34, brightness: 0.87, alpha: 1),
                    dark: UIColor(hue: hue, saturation: 0.52, brightness: 0.15, alpha: 1)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Ink for the initial, taken from the same hue so the letter belongs to its field rather
    /// than being printed on top of it.
    public static func ink(for seed: String) -> Color {
        let hue = hue(for: seed)
        return DipleColor.adaptive(
            light: UIColor(hue: hue, saturation: 0.55, brightness: 0.36, alpha: 1),
            dark: UIColor(hue: hue, saturation: 0.22, brightness: 0.95, alpha: 1)
        )
    }

    /// The letter a cover carries. Digits and punctuation are skipped so a title like
    /// "1984" or "«Пиранези»" still gets a letter rather than a quote mark.
    public static func initial(for title: String) -> String {
        let letter = title.first { $0.isLetter || $0.isNumber }
        return String(letter ?? "?").uppercased()
    }
}

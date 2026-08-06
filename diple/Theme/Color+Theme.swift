import SwiftUI
import UIKit

public extension UIColor {
    /// Selected accent colour, for the UIKit layers of the reader. Computed rather than a
    /// stored literal so a change in Settings reaches `ChapterPullTransition` and friends —
    /// mirrors `DipleAccent.current`, the single writer.
    static var dipleAccent: UIColor { DipleAccent.current.uiColor }
}

public extension Color {
    /// Selected accent colour. Mirrors `DipleAccent.current`, the single writer.
    static var dipleAccent: Color { DipleAccent.current.color }

    init(hex: String) {
        let hexCleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexCleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexCleaned.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 223, 155, 225)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

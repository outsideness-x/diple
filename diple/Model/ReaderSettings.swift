import Foundation
import ReadiumNavigator

public enum ReaderFont: String, CaseIterable, Identifiable, Codable {
    case serif = "Serif"
    case sanFrancisco = "San Francisco"

    public var id: String { rawValue }

    public var fontFamily: FontFamily {
        switch self {
        case .serif:
            return .serif
        case .sanFrancisco:
            return .sansSerif
        }
    }
}

public struct ReaderSettings: Equatable {
    public var fontSizeStep: Int = 2 // 0: 0.8, 1: 0.9, 2: 1.0, 3: 1.15, 4: 1.3
    public var font: ReaderFont = .sanFrancisco
    public var theme: Theme = .dark

    public static let fontSizes: [Double] = [0.8, 0.9, 1.0, 1.15, 1.3]

    public init(fontSizeStep: Int = 2, font: ReaderFont = .sanFrancisco, theme: Theme = .dark) {
        self.fontSizeStep = fontSizeStep
        self.font = font
        self.theme = theme
    }

    public var currentFontSize: Double {
        Self.fontSizes[max(0, min(fontSizeStep, Self.fontSizes.count - 1))]
    }

    public var epubPreferences: EPUBPreferences {
        var prefs = EPUBPreferences()
        prefs.fontSize = currentFontSize
        prefs.fontFamily = font.fontFamily
        prefs.theme = theme
        return prefs
    }
}

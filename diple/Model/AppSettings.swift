import Foundation

public enum HapticIntensity: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case medium = "Medium"
    case heavy = "Heavy"

    public var id: String { rawValue }
}

public struct AppSettings: Codable, Equatable {
    public var isHapticsEnabled: Bool
    public var hapticIntensity: HapticIntensity
    public var chapterHapticsEnabled: Bool
    public var defaultScrollReadingMode: Bool

    public init(
        isHapticsEnabled: Bool = true,
        hapticIntensity: HapticIntensity = .medium,
        chapterHapticsEnabled: Bool = true,
        defaultScrollReadingMode: Bool = false
    ) {
        self.isHapticsEnabled = isHapticsEnabled
        self.hapticIntensity = hapticIntensity
        self.chapterHapticsEnabled = chapterHapticsEnabled
        self.defaultScrollReadingMode = defaultScrollReadingMode
    }
}

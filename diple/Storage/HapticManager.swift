import UIKit

@MainActor
public final class HapticManager {
    public static let shared = HapticManager()

    private init() {}

    public enum ImpactLevel {
        case light
        case medium
        case heavy
    }

    public func impact(_ level: ImpactLevel = .medium) {
        let settings = AppSettingsManager.shared.settings
        guard settings.isHapticsEnabled else { return }

        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch settings.hapticIntensity {
        case .light:
            switch level {
            case .light, .medium: style = .light
            case .heavy: style = .medium
            }
        case .medium:
            switch level {
            case .light: style = .light
            case .medium: style = .medium
            case .heavy: style = .heavy
            }
        case .heavy:
            switch level {
            case .light: style = .medium
            case .medium: style = .heavy
            case .heavy: style = .rigid
            }
        }

        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    public func selection() {
        let settings = AppSettingsManager.shared.settings
        guard settings.isHapticsEnabled else { return }

        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    public func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let settings = AppSettingsManager.shared.settings
        guard settings.isHapticsEnabled else { return }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    public func chapterChanged() {
        let settings = AppSettingsManager.shared.settings
        guard settings.isHapticsEnabled && settings.chapterHapticsEnabled else { return }

        let style: UIImpactFeedbackGenerator.FeedbackStyle = (settings.hapticIntensity == .heavy) ? .heavy : .medium
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

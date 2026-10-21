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

    /// The system's own strengths, one for one (2026-10-01). There used to be a Light / Medium /
    /// Heavy choice in Settings that shifted every level up or down a step; a reading app that
    /// asks how hard it should tap is asking the reader to tune it, and the levels UIKit ships
    /// are already the ones every other app on the device answers with.
    public func impact(_ level: ImpactLevel = .medium) {
        let settings = AppSettingsManager.shared.settings
        guard settings.isHapticsEnabled else { return }

        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch level {
        case .light: style = .light
        case .medium: style = .medium
        case .heavy: style = .heavy
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

    /// A soft tick as the reader crosses into a new chapter — the feel of a page edge, not an
    /// alert. It follows the one haptics switch; it had a switch of its own until 2026-10-01,
    /// and a medium impact on every chapter of a long novel was the reason anyone needed it.
    public func chapterChanged() {
        let settings = AppSettingsManager.shared.settings
        guard settings.isHapticsEnabled else { return }

        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
    }
}

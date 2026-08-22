import UIKit
import os

/// Applies the alternate app icon that matches the selected accent.
@MainActor
public enum AppIconManager {
    private static let log = Logger(subsystem: "com.chemical-pink.diple", category: "AppIcon")

    /// One reconciliation at a time. A later accent supersedes an earlier one that is still
    /// retrying, rather than racing it to the same setting.
    private static var reconciliation: Task<Void, Never>?

    /// How long to wait before each attempt after the first.
    ///
    /// The system refuses this call for a short while around activation — see `reconcile` — and
    /// the delays are the whole reason a launch-time reconciliation works at all. Four attempts
    /// spanning under two seconds: long enough to outlast a busy launch, short enough that a
    /// reader who chose an accent in Settings never sees the icon lag behind their tap.
    private static let retryDelays: [Duration] = [.milliseconds(250), .milliseconds(600), .seconds(1)]

    /// Reconciles the Home Screen icon with `accent`. Called from Settings on a direct tap and
    /// every time the app becomes active, so an accent that arrived over iCloud while the app
    /// was closed also moves the icon on this device.
    public static func apply(_ accent: DipleAccent) {
        #if !targetEnvironment(macCatalyst)
        // Mac Catalyst has no alternate-icon mechanism; the accent still repaints every
        // SwiftUI/UIKit surface through `DipleAccent.current`, just not the Dock icon.
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let wanted = accent.alternateIconName
        reconciliation?.cancel()
        reconciliation = Task { await reconcile(to: wanted) }
        #endif
    }

    #if !targetEnvironment(macCatalyst)
    /// Sets the icon, retrying while the system says it cannot right now.
    ///
    /// **The retry is load-bearing, not defensive.** A single attempt made the moment the scene
    /// goes active fails with `Resource temporarily unavailable` — LaunchServices is still busy
    /// with the launch — and because the old call passed no completion handler, that failure was
    /// invisible: the accent had been applied everywhere except the one surface a reader looks at
    /// from the Home Screen. Any reconciliation that did not come from a direct tap in Settings
    /// had simply never worked.
    ///
    /// The "already correct" check is re-made before every attempt, and it is what keeps the
    /// system confirmation alert from appearing for nothing: iOS shows it on every accepted call,
    /// whether or not the icon actually changes.
    private static func reconcile(to wanted: String?) async {
        for attempt in 0...retryDelays.count {
            if attempt > 0 {
                try? await Task.sleep(for: retryDelays[attempt - 1])
                guard !Task.isCancelled else { return }
            }
            guard UIApplication.shared.alternateIconName != wanted else { return }
            do {
                try await UIApplication.shared.setAlternateIconName(wanted)
                return
            } catch {
                log.debug("Icon \(wanted ?? "primary", privacy: .public) refused on attempt \(attempt + 1): \(error.localizedDescription, privacy: .public)")
            }
        }
        // Out of attempts. The interface is still the right colour and nothing is broken; the
        // next activation reconciles again, so this is a note for a bug report, not an alert.
        log.error("Gave up setting icon \(wanted ?? "primary", privacy: .public)")
    }
    #endif
}

import UIKit

/// Applies the alternate app icon that matches the selected accent.
@MainActor
public enum AppIconManager {
    /// Reconciles the Home Screen icon with `accent`. Called from Settings on a direct tap and
    /// once at launch, so an accent that arrived over iCloud while the app was closed also
    /// moves the icon.
    public static func apply(_ accent: DipleAccent) {
        #if !targetEnvironment(macCatalyst)
        // Mac Catalyst has no alternate-icon mechanism; the accent still repaints every
        // SwiftUI/UIKit surface through `DipleAccent.current`, just not the Dock icon.
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let wanted = accent.alternateIconName
        // `setAlternateIconName` shows a system confirmation alert even when the requested
        // name already matches — calling it unconditionally on every reconciliation would pop
        // that alert for nothing.
        guard UIApplication.shared.alternateIconName != wanted else { return }
        UIApplication.shared.setAlternateIconName(wanted)
        #endif
    }
}

import SwiftUI
import UIKit

/// Light, dark, or whatever the phone is doing.
///
/// Raw values are the persisted representation — written into `AppSettings`, which travels
/// through the CloudKit settings payload — so a case must never be renamed once shipped.
///
/// Unlike `DipleAccent`, this needs no live static holder and no `.id()` rebuild of the view
/// tree. The tokens in `DipleColor` are dynamic `UIColor`s that resolve against the trait
/// collection, so setting the scheme once at the root repaints the whole app — including the
/// UIKit layers of the reader — through the machinery the system already runs for appearance
/// changes.
public enum DipleAppearance: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// What the picker shows. Kept apart from `rawValue` so the label can change without
    /// invalidating what is already stored on readers' devices.
    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` means "do not override", which is how SwiftUI spells "follow the device".
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Applies the choice to the window itself, not just to the SwiftUI tree.
    ///
    /// `preferredColorScheme` at the root covers the app's own views, but a sheet is presented
    /// by UIKit and keeps the window's style — so the Settings sheet, which is where the
    /// control lives, went on rendering dark while the screen behind it turned light. Setting
    /// `overrideUserInterfaceStyle` on the window covers everything presented in it, including
    /// system sheets, alerts and the keyboard.
    @MainActor
    public static func apply(_ appearance: DipleAppearance) {
        let style = appearance.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

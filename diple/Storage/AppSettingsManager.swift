import Foundation
import Combine

@MainActor
public final class AppSettingsManager: ObservableObject {
    public static let shared = AppSettingsManager()

    private let userDefaultsKey = "diple_app_settings"
    private var isApplyingRemoteSettings = false

    /// Set while `didSet` is writing the stamps back, so stamping does not restamp itself.
    private var isStamping = false

    @Published public var settings: AppSettings {
        didSet {
            // Stamp before anything else looks at the value: whoever changed a setting did so
            // now, and the stamp is what lets a merge keep it against a device that changed a
            // different setting. Guarded because this assignment re-enters `didSet`.
            if !isStamping && !isApplyingRemoteSettings {
                var stamped = settings
                stamped.stampChanges(against: oldValue)
                if stamped.fieldStamps != settings.fieldStamps {
                    isStamping = true
                    settings = stamped
                    isStamping = false
                    return
                }
            }
            // `DipleAccent.current` backs ~94 call sites' worth of computed colour tokens, so
            // every path that can change `settings` — local edit or an incoming CloudKit
            // payload — has to keep it in lockstep, not just the Settings screen's own setter.
            DipleAccent.current = settings.accent
            // Same reasoning as the accent: every path that can change `settings` — the
            // Settings screen or an incoming CloudKit payload — has to reach the window,
            // not only the one that happens to be on screen when the user taps.
            DipleAppearance.apply(settings.appearance)
            // And again for the measured reading pace, which every printed estimate reads
            // through `ReadingSpeed.current` rather than through this object — a shelf of rows
            // has no other business with the settings and should not rebuild when the accent
            // changes. A device that has just synced someone's pace from their iPad must start
            // estimating with it here, not after the next launch.
            ReadingSpeed.current = settings.readingSpeed
            save()
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
        // `didSet` does not fire for a property's own initial assignment inside `init`, so the
        // holder needs this explicit sync for the very first launch. The appearance is not
        // applied here: no window exists yet. `preferredColorScheme` at the root covers the
        // first frame, and `dipleApp` reaches the window once the scene is up.
        DipleAccent.current = settings.accent
        ReadingSpeed.current = settings.readingSpeed
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            if !isApplyingRemoteSettings {
                try? AppDatabase.shared.markSettingsChanged()
            }
        }
    }

    public func encodedSettings() throws -> Data {
        try JSONEncoder().encode(settings)
    }

    /// Merges an incoming payload field by field rather than replacing wholesale.
    ///
    /// Wholesale replacement meant changing *different* settings on two devices lost one of
    /// them — pick an accent on the phone and a theme on the Mac, and whichever synced first
    /// was reverted. Each field now goes to whichever device changed *it* last.
    public func applySyncedSettings(_ data: Data) throws {
        let remote = try JSONDecoder().decode(AppSettings.self, from: data)
        let merged = settings.merging(remote: remote)
        guard merged != settings else {
            // Nothing of theirs is newer. If ours is newer in some field, they are behind and
            // need it — `!=` on the whole value is what says so, stamps included.
            if remote != settings { try? AppDatabase.shared.markSettingsChanged() }
            return
        }

        // The merge result is authoritative, and it is not simply what arrived: suppress the
        // outbox write that `didSet` would otherwise make, then queue one deliberately if the
        // merge kept anything of ours the other device has not seen.
        isApplyingRemoteSettings = true
        settings = merged
        isApplyingRemoteSettings = false

        if merged != remote {
            try? AppDatabase.shared.markSettingsChanged()
        }
    }
}

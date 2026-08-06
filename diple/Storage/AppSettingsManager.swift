import Foundation
import Combine

@MainActor
public final class AppSettingsManager: ObservableObject {
    public static let shared = AppSettingsManager()

    private let userDefaultsKey = "diple_app_settings"
    private var isApplyingRemoteSettings = false

    @Published public var settings: AppSettings {
        didSet {
            // `DipleAccent.current` backs ~94 call sites' worth of computed colour tokens, so
            // every path that can change `settings` — local edit or an incoming CloudKit
            // payload — has to keep it in lockstep, not just the Settings screen's own setter.
            DipleAccent.current = settings.accent
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
        // holder needs this explicit sync for the very first launch.
        DipleAccent.current = settings.accent
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

    public func applySyncedSettings(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        guard decoded != settings else { return }
        isApplyingRemoteSettings = true
        settings = decoded
        isApplyingRemoteSettings = false
    }
}

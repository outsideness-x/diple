import Foundation
import Combine

@MainActor
public final class AppSettingsManager: ObservableObject {
    public static let shared = AppSettingsManager()

    private let userDefaultsKey = "diple_app_settings"

    @Published public var settings: AppSettings {
        didSet {
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
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
}

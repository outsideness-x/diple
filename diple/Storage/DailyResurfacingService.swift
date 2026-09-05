import Foundation
import UserNotifications
import WidgetKit

/// Device-local daily quote selection and notification scheduling. Notification permission is
/// specific to one device, so unlike the reader's visual preferences these values must not go
/// through the iCloud-synchronised `AppSettings` payload.
@MainActor
public final class DailyResurfacingService {
    public static let shared = DailyResurfacingService()

    public static let notificationIdentifier = "diple.daily-resurfacing"

    private enum Key {
        static let enabled = "diple_daily_resurfacing_enabled"
        static let hour = "diple_daily_resurfacing_hour"
        static let minute = "diple_daily_resurfacing_minute"
        static let day = "diple_daily_resurfacing_day"
        static let quoteID = "diple_daily_resurfacing_quote_id"
        static let openOnLaunch = "diple_daily_resurfacing_open_on_launch"
    }

    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter

    private init(
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    public var isNotificationEnabled: Bool {
        defaults.bool(forKey: Key.enabled)
    }

    /// Stored as components rather than a date so the user keeps "9:00" when travelling.
    public var notificationTime: Date {
        let calendar = Calendar.current
        let hour = defaults.object(forKey: Key.hour) as? Int ?? 9
        let minute = defaults.object(forKey: Key.minute) as? Int ?? 0
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    public func setNotificationsEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            defaults.set(false, forKey: Key.enabled)
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
            return false
        }

        let settings = await notificationCenter.notificationSettings()
        let allowed: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            allowed = true
        case .notDetermined:
            allowed = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            allowed = false
        @unknown default:
            allowed = false
        }

        defaults.set(allowed, forKey: Key.enabled)
        guard allowed else { return false }
        await scheduleNotification()
        return true
    }

    public func setNotificationTime(_ time: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        defaults.set(components.hour ?? 9, forKey: Key.hour)
        defaults.set(components.minute ?? 0, forKey: Key.minute)
        guard isNotificationEnabled else { return }
        await scheduleNotification()
    }

    /// Revalidates an already-enabled reminder on launch. A revoked system permission quietly
    /// returns the toggle to off instead of leaving Settings promising a reminder that cannot
    /// arrive.
    public func reconcileNotifications() async {
        guard isNotificationEnabled else { return }
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
            defaults.set(false, forKey: Key.enabled)
            return
        }
        await scheduleNotification()
    }

    public func quoteForToday(now: Date = Date()) throws -> Highlight? {
        let quotes = try AppDatabase.shared.fetchAllHighlights()
        guard !quotes.isEmpty else { return nil }

        let day = Self.dayKey(for: now)
        if defaults.string(forKey: Key.day) == day,
           let quoteID = defaults.string(forKey: Key.quoteID),
           let quote = quotes.first(where: { $0.id == quoteID }) {
            return quote
        }

        let quote = Self.candidate(for: now, from: quotes)
        if let quote {
            defaults.set(day, forKey: Key.day)
            defaults.set(quote.id, forKey: Key.quoteID)
        }
        return quote
    }

    public func showAnotherQuote(now: Date = Date()) throws -> Highlight? {
        let quotes = try AppDatabase.shared.fetchAllHighlights()
        guard let current = try quoteForToday(now: now) else { return nil }

        let eligible = Self.eligibleQuotes(from: quotes, on: now)
        guard eligible.count > 1,
              let currentIndex = eligible.firstIndex(where: { $0.id == current.id }) else {
            return current
        }
        let next = eligible[(currentIndex + 1) % eligible.count]
        defaults.set(Self.dayKey(for: now), forKey: Key.day)
        defaults.set(next.id, forKey: Key.quoteID)
        return next
    }

    public func hasAnotherQuote(now: Date = Date()) throws -> Bool {
        Self.eligibleQuotes(from: try AppDatabase.shared.fetchAllHighlights(), on: now).count > 1
    }

    // MARK: - The widget's copy

    /// Leaves the next fortnight of passages where the widget can read them.
    ///
    /// The widget cannot open the library — it is another process with another container — so
    /// the app resolves the days ahead here and writes them to the App Group. Today's entry is
    /// the *pinned* one, the same passage Home is showing, including one the reader swapped with
    /// Another; the days after it come from the same pure `candidate(for:from:)` the app will
    /// use when it reaches them. That is what keeps the Lock Screen and Home from disagreeing.
    ///
    /// Fire-and-forget: a widget that is one activation out of date is a widget, and blocking
    /// the app's activation on a library read to avoid that would be the worse trade.
    public func refreshWidgetSnapshot(now: Date = Date()) {
        // Read on the main actor, where these defaults belong, and hand the answer down.
        let pinnedID = defaults.string(forKey: Key.day) == Self.dayKey(for: now)
            ? defaults.string(forKey: Key.quoteID)
            : nil
        Task.detached(priority: .utility) {
            Self.writeWidgetSnapshot(now: now, pinnedQuoteID: pinnedID)
        }
    }

    nonisolated static func writeWidgetSnapshot(now: Date, pinnedQuoteID: String?) {
        guard let store = try? DailyQuoteSnapshotStore.shared() else { return }
        guard let quotes = try? AppDatabase.shared.fetchAllHighlights(), !quotes.isEmpty else {
            // Nothing saved: the file goes, and the widget's own empty state — which is a
            // sentence about an empty library, not an error — takes over.
            store.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let snapshot = DailyQuoteSnapshot(
            generatedAt: now,
            entries: entries(from: quotes, startingAt: now, pinnedQuoteID: pinnedQuoteID),
            totalQuoteCount: quotes.count
        )
        try? store.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Pure, so the agreement between what the widget shows and what Home will show is a thing
    /// tests can hold rather than a claim.
    nonisolated static func entries(
        from quotes: [Highlight],
        startingAt now: Date,
        pinnedQuoteID: String?,
        horizon: Int = DailyQuoteSnapshotStore.horizonInDays
    ) -> [DailyQuoteSnapshot.Entry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: now)
        let pinned = pinnedQuoteID.flatMap { id in quotes.first { $0.id == id } }

        return (0..<max(1, horizon)).compactMap { offset in
            // Day zero is asked about with the *instant*, not with midnight, because that is
            // what `quoteForToday(now:)` is given and the two answers have to be the same one.
            // Later days have no instant to speak of and take the start of theirs.
            guard let midnight = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let date = offset == 0 ? now : midnight
            let quote = offset == 0 ? (pinned ?? candidate(for: date, from: quotes)) : candidate(for: date, from: quotes)
            guard let quote else { return nil }
            return DailyQuoteSnapshot.Entry(
                day: dayKey(for: date),
                quoteID: quote.id,
                text: quote.text,
                bookTitle: quote.bookTitle,
                bookAuthor: quote.bookAuthor,
                colorHex: quote.colorHex
            )
        }
    }

    public func requestOpenFromNotification() {
        defaults.set(true, forKey: Key.openOnLaunch)
        NotificationCenter.default.post(name: .dipleOpenDailyResurfacing, object: nil)
    }

    public func consumeOpenRequest() -> Bool {
        guard defaults.bool(forKey: Key.openOnLaunch) else { return false }
        defaults.set(false, forKey: Key.openOnLaunch)
        return true
    }

    /// Stable within a day, older quotes first. It is intentionally pure so the selection rule
    /// is testable without a notification centre or the application's database singleton.
    public nonisolated static func candidate(for date: Date, from quotes: [Highlight]) -> Highlight? {
        let eligible = eligibleQuotes(from: quotes, on: date)
        guard !eligible.isEmpty else { return nil }
        let ordinal = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return eligible[ordinal % eligible.count]
    }

    private nonisolated static func eligibleQuotes(from quotes: [Highlight], on date: Date) -> [Highlight] {
        let startOfToday = Calendar.current.startOfDay(for: date)
        let oldQuotes = quotes.filter { $0.createdAt < startOfToday }
        return (oldQuotes.isEmpty ? quotes : oldQuotes)
            .sorted { lhs, rhs in
                lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
            }
    }

    /// The widget has to name the same day this does, so the key lives in `Shared` where both
    /// processes can reach it rather than being written out twice and agreeing by luck.
    nonisolated static func dayKey(for date: Date) -> String {
        DailyQuoteDay.key(for: date)
    }

    private func scheduleNotification() async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "A thought worth returning to"
        content.body = "Your daily resurface is ready in diple."
        content.sound = .default
        content.userInfo = ["dipleDailyResurfacing": true]

        let components = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        try? await notificationCenter.add(request)
    }
}

public final class DailyResurfacingNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = DailyResurfacingNotificationDelegate()

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == DailyResurfacingService.notificationIdentifier {
            Task { @MainActor in
                DailyResurfacingService.shared.requestOpenFromNotification()
            }
        }
        completionHandler()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

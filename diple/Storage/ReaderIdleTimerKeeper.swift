import UIKit

/// Owns `UIApplication.shared.isIdleTimerDisabled` while a book is open.
///
/// The idle timer flag is UIApplication-wide, so exactly one type may drive it, and it must
/// never be left `true` once nothing is reading: `ReaderContainerView` releases it on
/// disappear, on `scenePhase` leaving `.active`, and when the setting is switched off mid-session.
@MainActor
public final class ReaderIdleTimerKeeper {
    public static let shared = ReaderIdleTimerKeeper()

    /// What "10 minutes" in the Settings caption actually means: after this much time without a
    /// `poke()`, the idle timer goes back on and the screen dims normally.
    private static let holdDuration: TimeInterval = 10 * 60

    /// `poke()` is called on every navigator location update, which fires per scrolled pixel.
    /// Cancelling and rebuilding the countdown `Task` that often would be wasteful, so a poke
    /// only touches the timer when at least this long has passed since the last one — still far
    /// inside the hold window, so nothing is lost by coalescing.
    private static let minRearmInterval: TimeInterval = 5

    private var isSessionActive = false
    private var lastArmedAt: Date?
    private var countdownTask: Task<Void, Never>?

    private init() {}

    /// Disables the idle timer and arms the countdown. Idempotent — safe to call from appear,
    /// from `scenePhase` becoming active, and from the setting being switched on, without
    /// worrying about double-arming.
    public func begin() {
        isSessionActive = true
        arm()
    }

    /// Call on real reading activity (location change, overlay toggle, selection) — never on a
    /// repeating timer of its own. A no-op before `begin()` or after `end()`.
    public func poke() {
        guard isSessionActive else { return }
        if let lastArmedAt, Date().timeIntervalSince(lastArmedAt) < Self.minRearmInterval {
            return
        }
        arm()
    }

    /// Re-enables the idle timer immediately and drops the countdown.
    public func end() {
        isSessionActive = false
        countdownTask?.cancel()
        countdownTask = nil
        lastArmedAt = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func arm() {
        lastArmedAt = Date()
        UIApplication.shared.isIdleTimerDisabled = true
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.holdDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expire()
        }
    }

    /// The countdown ran out with no activity: hand the idle timer back so the screen dims on
    /// its own again. `lastArmedAt` resets to `nil` so a later `poke()` (reading resumed on a
    /// book left open) re-arms instead of being coalesced away.
    private func expire() {
        countdownTask = nil
        lastArmedAt = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

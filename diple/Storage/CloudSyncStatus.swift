import Foundation
import Combine

public nonisolated struct CloudSyncSnapshot: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case disabled
        case checking
        case syncing
        case synced
        case attention
    }

    public let phase: Phase
    public let pendingCount: Int
    public let lastSuccessfulAt: Date?
    public let message: String?

    public init(
        phase: Phase,
        pendingCount: Int = 0,
        lastSuccessfulAt: Date? = nil,
        message: String? = nil
    ) {
        self.phase = phase
        self.pendingCount = pendingCount
        self.lastSuccessfulAt = lastSuccessfulAt
        self.message = message
    }
}

/// A main-actor projection of the CloudKit actor's real state. Settings observes this object;
/// no view guesses that an enabled toggle means data reached the server.
@MainActor
public final class CloudSyncStatusStore: ObservableObject {
    public static let shared = CloudSyncStatusStore()
    private static let lastSuccessfulKey = "diple_icloud_last_successful_sync"

    @Published public private(set) var snapshot: CloudSyncSnapshot

    private init() {
        let lastSuccessfulAt = UserDefaults.standard.object(forKey: Self.lastSuccessfulKey) as? Date
        snapshot = CloudSyncSnapshot(
            phase: CloudSyncService.isEnabled ? .checking : .disabled,
            lastSuccessfulAt: lastSuccessfulAt
        )
    }

    public func update(
        phase: CloudSyncSnapshot.Phase,
        pendingCount: Int,
        message: String? = nil,
        successfulAt: Date? = nil
    ) {
        let lastSuccessfulAt: Date?
        if let successfulAt {
            UserDefaults.standard.set(successfulAt, forKey: Self.lastSuccessfulKey)
            lastSuccessfulAt = successfulAt
        } else {
            lastSuccessfulAt = snapshot.lastSuccessfulAt
        }
        snapshot = CloudSyncSnapshot(
            phase: phase,
            pendingCount: pendingCount,
            lastSuccessfulAt: lastSuccessfulAt,
            message: message
        )
    }
}

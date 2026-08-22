import Foundation
import Combine
import SwiftUI

/// Drains URLs accepted by the Share Extension through the same importer used by Home.
/// Entries are acknowledged only after `ArticleImporter` has committed its EPUB and database
/// row. A failed request therefore stays visible and retryable instead of disappearing into a
/// best-effort inter-process notification.
@MainActor
public final class SharedLinkImportCoordinator: ObservableObject {
    public static let shared = SharedLinkImportCoordinator()

    public enum State: Equatable {
        case idle
        case importing(id: UUID, host: String)
        case saved(title: String)
        case failed(id: UUID, host: String, message: String)
    }

    @Published public private(set) var state: State = .idle

    private var processingTask: Task<Void, Never>?

    private init() {}

    public func processPending(force id: UUID? = nil) {
        guard processingTask == nil, AppDatabase.startupFailure == nil else { return }
        processingTask = Task { [weak self] in
            await self?.drain(force: id)
            self?.processingTask = nil
        }
    }

    public func retry(id: UUID) {
        do {
            let inbox = try SharedLinkInbox.live()
            try inbox.clearFailure(id: id)
            processPending(force: id)
        } catch {
            state = .failed(id: id, host: "shared link", message: error.localizedDescription)
        }
    }

    public func discard(id: UUID) {
        do {
            try SharedLinkInbox.live().remove(id: id)
            withAnimation(DipleMotion.standard) { state = .idle }
            processPending()
        } catch {
            state = .failed(id: id, host: "shared link", message: error.localizedDescription)
        }
    }

    private func drain(force forcedID: UUID?) async {
        do {
            let inbox = try SharedLinkInbox.live()

            while !Task.isCancelled {
                let pending = try inbox.pending()
                guard !pending.isEmpty else {
                    withAnimation(DipleMotion.standard) { state = .idle }
                    return
                }

                let entry: SharedLinkInbox.Entry?
                if let forcedID {
                    entry = pending.first { $0.id == forcedID }
                } else {
                    entry = pending.first { SharedLinkInbox.isReady($0) }
                }

                guard let entry else {
                    if let failed = pending.first(where: { $0.lastError != nil }) {
                        state = .failed(
                            id: failed.id,
                            host: failed.url?.host ?? "shared link",
                            message: failed.lastError ?? "The article is still waiting to be imported."
                        )
                    }
                    return
                }

                guard let url = entry.url,
                      let normalizedURL = SharedLinkInbox.normalized(url) else {
                    try inbox.remove(id: entry.id)
                    continue
                }

                let host = normalizedURL.host ?? "article"
                state = .importing(id: entry.id, host: host)

                // Selecting the same URL from the share sheet twice should never create two
                // shelf entries. This fast path also handles a crash after the article commit
                // but before the cross-process queue acknowledgement.
                let existing = try AppDatabase.shared.fetchBook(id: entry.id.uuidString)
                    ?? AppDatabase.shared.fetchAllBooks().first { book in
                        guard let sourceString = book.sourceURL,
                              let source = URL(string: sourceString),
                              let normalizedSource = SharedLinkInbox.normalized(source)
                        else { return false }
                        return normalizedSource.absoluteString == normalizedURL.absoluteString
                    }
                if let existing {
                    try inbox.remove(id: entry.id)
                    state = .saved(title: existing.title)
                    try? await Task.sleep(for: .seconds(1.4))
                    continue
                }

                do {
                    let book = try await ArticleImporter.shared.importArticle(
                        from: normalizedURL,
                        bookID: entry.id.uuidString
                    ) { _ in }
                    try inbox.remove(id: entry.id)
                    state = .saved(title: book.title)
                    try? await Task.sleep(for: .seconds(1.8))
                } catch {
                    try? inbox.markFailed(id: entry.id, message: error.localizedDescription)
                    state = .failed(
                        id: entry.id,
                        host: host,
                        message: error.localizedDescription
                    )
                    return
                }
            }
        } catch {
            state = .failed(id: UUID(), host: "shared link", message: error.localizedDescription)
        }
    }
}

@MainActor
public struct SharedLinkImportBanner: View {
    @ObservedObject private var coordinator: SharedLinkImportCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {
        self.coordinator = .shared
    }

    public init(coordinator: SharedLinkImportCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Group {
            switch coordinator.state {
            case .idle:
                EmptyView()

            case .importing(_, let host):
                banner(icon: "arrow.down.doc", title: "Saving shared link", detail: host) {
                    ProgressView()
                        .tint(DipleColor.accent)
                }

            case .saved(let title):
                banner(icon: "checkmark", title: "Saved to Inbox", detail: title) {
                    EmptyView()
                }

            case .failed(let id, let host, let message):
                banner(icon: "exclamationmark", title: "Couldn’t save \(host)", detail: message) {
                    HStack(spacing: DipleSpace.xs) {
                        Button("Discard") { coordinator.discard(id: id) }
                            .foregroundStyle(DipleColor.textTertiary)
                        Button("Retry") { coordinator.retry(id: id) }
                            .foregroundStyle(DipleColor.accent)
                    }
                    .dipleType(.footnote, weight: .semibold)
                }
            }
        }
        .animation(reduceMotion ? nil : DipleMotion.standard, value: coordinator.state)
    }

    private func banner<Trailing: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: DipleSpace.m) {
            Image(systemName: icon)
                .dipleIcon(13, weight: .bold)
                .foregroundStyle(DipleColor.textOnAccent)
                .frame(width: 30, height: 30)
                .background(DipleColor.accent, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, DipleSpace.m)
        .padding(.vertical, DipleSpace.s)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        .padding(.horizontal, DipleSpace.l)
        .padding(.top, DipleSpace.s)
        .transition(.move(edge: .top).combined(with: .opacity))
        // Retry and Discard must remain independently reachable to VoiceOver on a failed
        // import; combining the whole banner would flatten both buttons into static text.
        .accessibilityElement(children: .contain)
    }
}

import Foundation
import Combine

/// Keeps one corpus for the whole app to ask questions of.
///
/// Building it reads every saved passage and tokenises it, which is work worth doing once and
/// not once per card. It is rebuilt when the number of passages changes — cheaper than a
/// notification for every local save, and it catches the two cases a notification would miss:
/// a quote saved in the reader a moment ago, and one deleted from a list.
@MainActor
public final class PassageEchoService {
    public static let shared = PassageEchoService()

    private var corpus: PassageEchoCorpus?
    private var corpusSize = -1
    private var build: Task<PassageEchoCorpus, Never>?
    private var observers: Set<AnyCancellable> = []

    private init() {
        Publishers.Merge(
            NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange),
            NotificationCenter.default.publisher(for: .dipleDataDidRestore)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.invalidate() }
        .store(in: &observers)
    }

    /// The passages that answer this one. Empty is a perfectly good answer and the common one:
    /// most passages do not resemble anything else the reader has saved.
    public func echoes(
        for passage: Highlight,
        limit: Int = 3,
        excludingSameSource: Bool = false
    ) async -> [PassageEcho] {
        let corpus = await resolvedCorpus()
        return corpus.echoes(for: passage, limit: limit, excludingSameSource: excludingSameSource)
    }

    public func invalidate() {
        corpus = nil
        corpusSize = -1
        build?.cancel()
        build = nil
    }

    private func resolvedCorpus() async -> PassageEchoCorpus {
        let count = (try? AppDatabase.shared.highlightCount()) ?? 0
        if let corpus, corpusSize == count { return corpus }

        // One build at a time: two cards appearing together must not tokenise the library twice.
        if let build, corpusSize == count { return await build.value }

        let task = Task.detached(priority: .utility) { () -> PassageEchoCorpus in
            PassageEchoCorpus((try? AppDatabase.shared.fetchAllHighlights()) ?? [])
        }
        build = task
        corpusSize = count
        let built = await task.value
        corpus = built
        build = nil
        return built
    }
}

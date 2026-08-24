import Combine
import Foundation
import SwiftUI

@MainActor
public final class SecondReadViewModel: ObservableObject {
    public enum ContextState: Equatable {
        case idle
        case loading
        case available(SecondReadContext)
        case unavailable
    }

    @Published public private(set) var items: [SecondReadItem] = []
    @Published public private(set) var expandedIDs: Set<String> = []
    @Published public private(set) var contextStates: [String: ContextState] = [:]
    @Published public var errorMessage: String?

    public let book: Book

    private let service: SecondReadService
    private let resolver: SecondReadContextResolver
    private var contextTasks: [String: Task<Void, Never>] = [:]
    private var observers: Set<AnyCancellable> = []

    public init(book: Book, database: AppDatabase = .shared) {
        self.book = book
        service = SecondReadService(database: database)
        resolver = SecondReadContextResolver(book: book)
        reload()

        NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: .dipleDataDidRestore)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &observers)
    }

    nonisolated deinit {}

    public func reload() {
        do {
            let newItems = try service.items(for: book)
            let previousItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            let validIDs = Set(newItems.map(\.id))
            let changedIDs = Set(newItems.compactMap { item -> String? in
                guard let previous = previousItems[item.id],
                      previous.locatorJSON != item.locatorJSON
                        || previous.highlightedText != item.highlightedText
                        || previous.isSourceAvailable != item.isSourceAvailable
                else { return nil }
                return item.id
            })
            let cancelledIDs = contextTasks.keys.filter {
                !validIDs.contains($0) || changedIDs.contains($0)
            }
            for id in cancelledIDs {
                contextTasks[id]?.cancel()
                contextTasks.removeValue(forKey: id)
            }
            items = newItems
            expandedIDs.formIntersection(validIDs)
            contextStates = contextStates.filter { validIDs.contains($0.key) }
            for id in changedIDs {
                contextStates[id] = .idle
            }
            errorMessage = nil

            for item in newItems where changedIDs.contains(item.id) && expandedIDs.contains(item.id) {
                requestContext(for: item, reduceMotion: true)
            }
        } catch {
            errorMessage = String(
                localized: "Your Second Read could not be loaded.",
                comment: "Non-technical Second Read database error"
            )
        }
    }

    public func contextState(for id: String) -> ContextState {
        contextStates[id] ?? .idle
    }

    public var isSourceAvailable: Bool {
        service.isSourceAvailable(for: book)
    }

    public func toggleContext(for item: SecondReadItem, reduceMotion: Bool) {
        if expandedIDs.contains(item.id) {
            contextTasks[item.id]?.cancel()
            contextTasks.removeValue(forKey: item.id)
            animate(reduceMotion: reduceMotion) {
                self.expandedIDs.remove(item.id)
                if self.contextStates[item.id] == .loading {
                    self.contextStates[item.id] = .idle
                }
            }
            return
        }

        animate(reduceMotion: reduceMotion) {
            self.expandedIDs.insert(item.id)
        }

        requestContext(for: item, reduceMotion: reduceMotion)
    }

    private func requestContext(for item: SecondReadItem, reduceMotion: Bool) {
        guard contextStates[item.id] == nil || contextStates[item.id] == .idle else { return }
        contextStates[item.id] = .loading
        let resolver = resolver
        contextTasks[item.id] = Task { [weak self] in
            let context = await resolver.context(for: item)
            guard !Task.isCancelled, let self else { return }
            self.contextTasks.removeValue(forKey: item.id)
            self.animate(reduceMotion: reduceMotion) {
                self.contextStates[item.id] = context.map(ContextState.available) ?? .unavailable
            }
        }
    }

    private func animate(reduceMotion: Bool, changes: @escaping () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(DipleMotion.standard, changes)
        }
    }
}

import Foundation

/// A small JSON array in the App Group that two processes take turns to change.
///
/// The share sheet writes it and the app drains it, and neither can know when the other is in
/// the middle: every read-change-write runs inside one `NSFileCoordinator` pass over the
/// directory, and the write is atomic. Kept as one type because the shared-link queue and the
/// shared-note queue need exactly this and nothing else, and two copies of file coordination are
/// two places for a lost write to hide.
public nonisolated struct AppGroupJSONFile<Element: Codable & Sendable>: Sendable {
    public let directoryURL: URL
    public let fileURL: URL

    public init(directoryURL: URL, fileName: String) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent(fileName)
    }

    public func read() throws -> [Element] {
        try coordinate { try load() }
    }

    public func mutate<Output>(_ change: (inout [Element]) throws -> Output) throws -> Output {
        try coordinate {
            var elements = try load()
            let result = try change(&elements)
            try save(elements)
            return result
        }
    }

    private func coordinate<Output>(_ work: () throws -> Output) throws -> Output {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<Output, Error>?
        coordinator.coordinate(
            writingItemAt: directoryURL,
            options: .forMerging,
            error: &coordinationError
        ) { _ in
            outcome = Result { try work() }
        }

        if let coordinationError { throw coordinationError }
        guard let outcome else { throw SharedLinkInbox.InboxError.queueUnavailable }
        return try outcome.get()
    }

    private func load() throws -> [Element] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Element].self, from: data)
    }

    private func save(_ elements: [Element]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(elements).write(to: fileURL, options: .atomic)
    }
}

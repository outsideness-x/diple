import Foundation
import PDFKit
import ReadiumShared
import SwiftSoup

/// Builds the lightweight, immediately-renderable edition from live annotation rows. Context
/// is intentionally a separate resolver below: opening the screen never opens or parses the
/// publication file.
public nonisolated final class SecondReadService: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase = .shared) {
        self.database = database
    }

    public func items(for book: Book) throws -> [SecondReadItem] {
        let highlights = try database.fetchHighlights(forBookId: book.id)
        let sections = (try? database.fetchSecondReadSections(bookID: book.id)) ?? []
        return SecondReadBuilder.build(
            book: book,
            highlights: highlights,
            sections: sections,
            isSourceAvailable: isSourceAvailable(for: book)
        )
    }

    public func isSourceAvailable(for book: Book) -> Bool {
        let sourceURL = BookStorageService.shared.absoluteURL(for: book.filePath)
        return FileManager.default.fileExists(atPath: sourceURL.path)
    }
}

/// The pure transformation behind `SecondReadService`, public to the test target and free of
/// database or filesystem state.
public nonisolated enum SecondReadBuilder {
    public static func build(
        book: Book,
        highlights: [Highlight],
        sections: [SecondReadSection] = [],
        isSourceAvailable: Bool = true
    ) -> [SecondReadItem] {
        let sectionsByHREF = Dictionary(
            sections.map { (normalizedHREF($0.href), $0) },
            uniquingKeysWith: { lhs, rhs in lhs.ordinal <= rhs.ordinal ? lhs : rhs }
        )

        let unsorted = highlights.compactMap { highlight -> SecondReadItem? in
            let text = highlight.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let locator = highlight.parsedLocator
            let href = normalizedHREF(locator?.href.string ?? highlight.locator)
            let section = sectionsByHREF[href]
            let locatorChapter = nonBlank(locator?.title)
            let chapter = locatorChapter ?? nonBlank(section?.title)
            let note = highlight.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
            let selector = locator.map(startSelector) ?? ""

            return SecondReadItem(
                id: highlight.id,
                bookID: book.id,
                locatorJSON: highlight.locator,
                locator: locator,
                chapterTitle: chapter,
                highlightedText: text,
                noteText: (note?.isEmpty ?? true) ? nil : note,
                position: SecondReadPosition(
                    sectionOrdinal: section?.ordinal,
                    totalProgression: locator?.locations.totalProgression,
                    position: locator?.locations.position,
                    progression: locator?.locations.progression,
                    href: href,
                    selector: selector
                ),
                showsChapterMarker: false,
                isSourceAvailable: isSourceAvailable
            )
        }
        .sorted { lhs, rhs in
            lhs.position.isBefore(rhs.position, id: lhs.id, otherID: rhs.id)
        }

        var previousChapter: String?
        return unsorted.map { item in
            let showsMarker = item.chapterTitle != nil && item.chapterTitle != previousChapter
            if let chapter = item.chapterTitle {
                previousChapter = chapter
            }
            return SecondReadItem(
                id: item.id,
                bookID: item.bookID,
                locatorJSON: item.locatorJSON,
                locator: item.locator,
                chapterTitle: item.chapterTitle,
                highlightedText: item.highlightedText,
                noteText: item.noteText,
                position: item.position,
                showsChapterMarker: showsMarker,
                isSourceAvailable: item.isSourceAvailable
            )
        }
    }

    private static func normalizedHREF(_ raw: String) -> String {
        let noFragment = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? raw
        let noQuery = noFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? noFragment
        return noQuery.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Modern Readium selections store a DOM range; older element locators may store a plain
    /// selector. Both are stable fallbacks for ordering two annotations with equal progress.
    private static func startSelector(in locator: Locator) -> String {
        if let selector = locator.locations.cssSelector {
            return selector
        }
        let start = locator.locations["domRange"]?.object?["start"]?.object
        let selector = start?["cssSelector"]?.string ?? ""
        let offset = start?["charOffset"]?.integer ?? start?["offset"]?.integer
        return offset.map { "\(selector):\($0)" } ?? selector
    }
}

/// One resolver belongs to one open Second Read. It retains at most one publication and a
/// small number of expanded excerpts, then disappears with the screen; nothing here is a new
/// persistence or sync surface.
public actor SecondReadContextResolver {
    private enum CachedContext {
        case available(SecondReadContext)
        case unavailable
    }

    private let book: Book
    private var publication: Publication?
    private var cache: [String: CachedContext] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 16

    public init(book: Book) {
        self.book = book
    }

    public func context(for item: SecondReadItem) async -> SecondReadContext? {
        let cacheKey = "\(item.id)\u{0}\(item.locatorJSON)\u{0}\(item.highlightedText)"
        if let cached = cache[cacheKey] {
            switch cached {
            case .available(let context): return context
            case .unavailable: return nil
            }
        }

        guard let locator = item.locator else {
            store(nil, for: cacheKey)
            return nil
        }

        let fallback = SecondReadContextExtractor.locatorFallback(
            highlightedText: item.highlightedText,
            locatorText: locator.text
        )
        guard item.isSourceAvailable else {
            store(fallback, for: cacheKey)
            return fallback
        }

        do {
            try Task.checkCancellation()
            let resolved: SecondReadContext?
            if book.isPDF {
                resolved = try resolvePDF(locator: locator, highlightedText: item.highlightedText)
            } else {
                resolved = try await resolveEPUB(locator: locator, highlightedText: item.highlightedText)
            }
            try Task.checkCancellation()
            let context = resolved ?? fallback
            store(context, for: cacheKey)
            return context
        } catch is CancellationError {
            return nil
        } catch {
            store(fallback, for: cacheKey)
            return fallback
        }
    }

    private func resolveEPUB(locator: Locator, highlightedText: String) async throws -> SecondReadContext? {
        let publication = try await publicationForBook()
        let locator = publication.normalizeLocator(locator)
        guard let resource = publication.get(locator.href) else { return nil }
        let data = try await resource.read().get()
        try Task.checkCancellation()
        guard let markup = String(data: data, encoding: .utf8) else { return nil }
        let document = try SwiftSoup.parse(markup)
        let paragraphs = BookContentExtractor.extractParagraphs(from: document)
        let preferredParagraphIndex = paragraphIndex(
            for: locator,
            in: document,
            paragraphs: paragraphs
        )
        return SecondReadContextExtractor.makeContext(
            paragraphs: paragraphs,
            highlightedText: highlightedText,
            approximateProgression: locator.locations.progression,
            preferredParagraphIndex: preferredParagraphIndex
        )
    }

    private func paragraphIndex(
        for locator: Locator,
        in document: SwiftSoup.Document,
        paragraphs: [String]
    ) -> Int? {
        let domStart = locator.locations["domRange"]?.object?["start"]?.object
        let selector = locator.locations.cssSelector ?? domStart?["cssSelector"]?.string
        guard let selector,
              let element = try? document.select(selector).first(),
              let selectedText = try? element.text().trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty
        else { return nil }

        let candidates = paragraphs.indices.filter {
            paragraphs[$0] == selectedText || paragraphs[$0].contains(selectedText)
        }
        guard !candidates.isEmpty else { return nil }
        let approximateIndex = locator.locations.progression.map {
            min(max(Int($0 * Double(paragraphs.count)), 0), paragraphs.count - 1)
        } ?? candidates[0]
        return candidates.min { abs($0 - approximateIndex) < abs($1 - approximateIndex) }
    }

    private func resolvePDF(locator: Locator, highlightedText: String) throws -> SecondReadContext? {
        let fileURL = BookStorageService.shared.absoluteURL(for: book.filePath)
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else { return nil }

        let pageFromFragment = locator.locations.fragments.lazy.compactMap { fragment -> Int? in
            guard fragment.hasPrefix("page=") else { return nil }
            return Int(fragment.dropFirst("page=".count))
        }.first
        let pageIndex: Int
        if let page = pageFromFragment ?? locator.locations.position {
            pageIndex = min(max(page - 1, 0), document.pageCount - 1)
        } else if let progression = locator.locations.progression {
            pageIndex = min(max(Int(progression * Double(document.pageCount)), 0), document.pageCount - 1)
        } else {
            pageIndex = 0
        }

        guard let text = document.page(at: pageIndex)?.string else { return nil }
        var paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if paragraphs.isEmpty { paragraphs = [text] }
        return SecondReadContextExtractor.makeContext(
            paragraphs: paragraphs,
            highlightedText: highlightedText,
            approximateProgression: nil
        )
    }

    private func publicationForBook() async throws -> Publication {
        if let publication { return publication }
        let fileURL = BookStorageService.shared.absoluteURL(for: book.filePath)
        let opened = try await BookContentExtractor.openPublication(fileURL: fileURL)
        guard !opened.isRestricted else { throw BookContentExtractionError.restrictedPublication }
        publication = opened
        return opened
    }

    private func store(_ context: SecondReadContext?, for id: String) {
        if cache[id] == nil {
            cacheOrder.append(id)
        }
        if let context {
            cache[id] = .available(context)
        } else {
            cache[id] = .unavailable
        }

        while cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}

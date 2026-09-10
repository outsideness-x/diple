import Foundation

/// The narrowing itself, as a function rather than as a screen.
///
/// Scope, lenses, facets, query, order and grouping are the whole product of the board, and
/// leaving them inside a view model meant they could only be exercised by running the app
/// against a real database — which is exactly the arrangement CLAUDE.md rules out fixtures for.
/// Here they are a pure transform over values: the view model owns the state and the database,
/// this owns what the state *means*, and a test can ask what the counts should be without a
/// simulator.
public nonisolated enum MarginaliaBoard {

    /// Everything one pass over the catalogue produces.
    public struct Snapshot: Equatable {
        public var results: [MarginaliaEntry] = []
        public var groups: [MarginaliaGroup] = []
        /// The chips, in the order the row prints them.
        public var facetOptions: [MarginaliaFacetOption] = []
        /// Every source and every tag standing under the current narrowing, for the full
        /// filter sheet, where nothing is capped and everything is searchable.
        public var sourceOptions: [MarginaliaFacetOption] = []
        public var tagOptions: [MarginaliaFacetOption] = []
        /// The mark colours actually in use under the current narrowing. Never offered when
        /// only one is in play: a filter with one option filters nothing.
        public var colorOptions: [MarginaliaFacetOption] = []
        public var lensOptions: [LensOption] = []
        public var writtenCount = 0
        public var savedCount = 0

        public var totalCount: Int { writtenCount + savedCount }
    }

    /// One stretch of the filter row: every chip in it is the same kind of thing.
    ///
    /// The row is read in runs rather than as one list sorted by size — see the note where
    /// `facetOptions` is assembled. Both the phone, which scrolls the row sideways with a rule
    /// between the runs, and the desktop, which wraps each run onto its own line, ask for the
    /// same split, and both have to cap **per run**: one cap over the whole row means a library
    /// with nine books prints no words at all, and the word is what most readers came to press.
    public struct FacetRun: Equatable, Identifiable {
        public enum Kind: String, Hashable {
            case marks
            case sources
            case tags
        }

        public let kind: Kind
        public let options: [MarginaliaFacetOption]

        public var id: Kind { kind }
    }

    /// Splits the assembled chips back into their runs and caps each one.
    ///
    /// Marks are never capped: there are four of them, they are aimed at rather than read, and
    /// a swatch dropped for want of room is a filter the reader cannot reach at all — the sheet
    /// lists sources and tags by name, and a colour has no name to look up.
    public static func runs(of options: [MarginaliaFacetOption], limit: Int) -> [FacetRun] {
        var marks: [MarginaliaFacetOption] = []
        var sources: [MarginaliaFacetOption] = []
        var tags: [MarginaliaFacetOption] = []

        for option in options {
            switch option.kind {
            case .color: marks.append(option)
            case .source: sources.append(option)
            case .tag: tags.append(option)
            }
        }

        return [
            FacetRun(kind: .marks, options: marks),
            FacetRun(kind: .sources, options: Array(sources.prefix(limit))),
            FacetRun(kind: .tags, options: Array(tags.prefix(limit)))
        ].filter { !$0.options.isEmpty }
    }

    public struct LensOption: Equatable, Identifiable {
        public let lens: MarginaliaLens
        public let count: Int
        public let isSelected: Bool

        public var id: MarginaliaLens { lens }
    }

    public struct Controls: Equatable {
        public var scope: MarginaliaScope = .all
        public var lenses: Set<MarginaliaLens> = []
        public var facets = MarginaliaFacets()
        public var rawQuery: String = ""
        public var sort: MarginaliaSort = .recent
        public var grouping: MarginaliaGrouping = .none

        public init(
            scope: MarginaliaScope = .all,
            lenses: Set<MarginaliaLens> = [],
            facets: MarginaliaFacets = MarginaliaFacets(),
            rawQuery: String = "",
            sort: MarginaliaSort = .recent,
            grouping: MarginaliaGrouping = .none
        ) {
            self.scope = scope
            self.lenses = lenses
            self.facets = facets
            self.rawQuery = rawQuery
            self.sort = sort
            self.grouping = grouping
        }
    }

    static let noSourceKey = "diple.marginalia.noSource"

    public static func snapshot(
        entries: [MarginaliaEntry],
        books: [Book],
        controls: Controls,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Snapshot {
        var snapshot = Snapshot()
        let query = MarginaliaQuery.parse(controls.rawQuery)
        let facets = controls.facets

        // Everything except scope and facets: the widest set any control is measured against.
        let base = entries.filter { entry in
            controls.lenses.allSatisfy { $0.matches(entry, now: now, calendar: calendar) }
                && query.matches(entry)
        }

        // The number on a scope segment is taken with the facets applied, so it is the number
        // of rows switching to it would actually show — not a promise the board then breaks.
        let scoped = base.filter { facets.matches($0) }
        snapshot.writtenCount = scoped.filter { $0.kind == .written }.count
        snapshot.savedCount = scoped.filter { $0.kind == .saved }.count

        let inScope = base.filter { controls.scope.includes($0.kind) }
        let results = inScope.filter { facets.matches($0) }
        snapshot.results = sorted(results, by: controls.sort)
        snapshot.groups = grouped(snapshot.results, by: controls.grouping, sort: controls.sort, books: books, calendar: calendar)

        // Tags are AND-ed, so a candidate is tallied inside the current result set: the number
        // on the chip is exactly what pressing it leaves.
        var tagCounts: [String: Int] = [:]
        for entry in results {
            for tag in entry.tags { tagCounts[tag, default: 0] += 1 }
        }
        // Sources are OR-ed, so a candidate is tallied with the source filter lifted: the
        // number on the chip is what that source would bring.
        var sourceCounts: [String: Int] = [:]
        for entry in inScope where facets.matchesTags(entry) && facets.matchesColors(entry) {
            if let bookId = entry.bookId { sourceCounts[bookId, default: 0] += 1 }
        }
        // Colours the same way, with the colour filter lifted.
        var colorCounts: [String: Int] = [:]
        for entry in inScope where facets.matchesTags(entry) && facets.matchesSources(entry) {
            if case .passage(let passage) = entry {
                colorCounts[passage.highlight.colorHex, default: 0] += 1
            }
        }

        let booksById = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sourceNames: [String: String] = [:]
        // Carried alongside the title so the filter sheet can be searched by author. A book
        // still in the library is the only one that has one; a source known only from the
        // highlight it was saved with has a title and nothing else.
        var sourceAuthors: [String: String] = [:]
        for entry in entries {
            guard let bookId = entry.bookId, sourceNames[bookId] == nil else { continue }
            sourceNames[bookId] = booksById[bookId]?.title ?? entry.bookTitle ?? "Untitled"
            if let author = booksById[bookId]?.author, !author.isEmpty {
                sourceAuthors[bookId] = author
            }
        }

        snapshot.tagOptions = tagCounts
            .map { tag, count in
                MarginaliaFacetOption(
                    kind: .tag(tag),
                    label: tag,
                    count: count,
                    isSelected: facets.tags.contains(tag)
                )
            }
            .sorted(by: byCountThenName)

        // One colour in play is not a choice, so the row is not drawn at all. Sorted by count
        // like every other facet, and labelled with the stored hex: naming a colour means
        // reading the palette, and this transform is deliberately reachable without the theme —
        // the chip resolves the name where `DipleColor` actually lives.
        snapshot.colorOptions = colorCounts.count > 1
            ? colorCounts
                .map { hex, count in
                    MarginaliaFacetOption(
                        kind: .color(hex),
                        label: hex,
                        count: count,
                        isSelected: facets.colors.contains(hex)
                    )
                }
                .sorted(by: byCountThenName)
            : []

        snapshot.sourceOptions = sourceCounts
            .map { bookId, count in
                MarginaliaFacetOption(
                    kind: .source(bookId),
                    label: sourceNames[bookId] ?? "Untitled",
                    detail: sourceAuthors[bookId],
                    count: count,
                    isSelected: facets.bookIds.contains(bookId)
                )
            }
            .sorted(by: byCountThenName)

        // A chosen chip stays on screen even when its own tally has fallen to nothing: it is
        // the reason the board is empty, and hiding the cause leaves a blank page with no way
        // back. An unchosen chip at zero is a dead end and is dropped — the same rule the notes
        // board already applied to its filter row.
        let chosenTags = facets.tags.sorted().map { tag in
            snapshot.tagOptions.first { $0.kind == .tag(tag) }
                ?? MarginaliaFacetOption(kind: .tag(tag), label: tag, count: 0, isSelected: true)
        }
        let chosenSources = facets.bookIds.sorted { lhs, rhs in
            (sourceNames[lhs] ?? "").localizedStandardCompare(sourceNames[rhs] ?? "") == .orderedAscending
        }.map { bookId in
            snapshot.sourceOptions.first { $0.kind == .source(bookId) }
                ?? MarginaliaFacetOption(
                    kind: .source(bookId),
                    label: sourceNames[bookId] ?? "Untitled",
                    detail: sourceAuthors[bookId],
                    count: 0,
                    isSelected: true
                )
        }
        // The row is read in runs of one kind, not as one list sorted by size.
        //
        // Every facet used to be poured into a single ranking by count, so a shelf stood
        // between two words, a swatch stood after them, and the same tag sat in a different
        // place on the row every time the numbers moved. Nothing about that row could be
        // learned — the reader had to read all of it to find the one word they came for.
        // Marks, then shelves, then words: three fixed runs the row prints in the same order
        // every time, with what is already chosen at the head of its own run. The board only
        // has to keep the runs contiguous; the row draws the rule between them.
        let offeredSources = snapshot.sourceOptions.filter { !$0.isSelected && $0.count > 0 }
        let offeredTags = snapshot.tagOptions.filter { !$0.isSelected && $0.count > 0 }
        snapshot.facetOptions = snapshot.colorOptions.filter(\.isSelected)
            + snapshot.colorOptions.filter { !$0.isSelected }
            + chosenSources
            + offeredSources
            + chosenTags
            + offeredTags

        snapshot.lensOptions = MarginaliaLens.allCases.compactMap { lens in
            let others = controls.lenses.subtracting([lens])
            let count = entries.filter { entry in
                controls.scope.includes(entry.kind)
                    && facets.matches(entry)
                    && query.matches(entry)
                    && lens.matches(entry, now: now, calendar: calendar)
                    && others.allSatisfy { $0.matches(entry, now: now, calendar: calendar) }
            }.count
            let isSelected = controls.lenses.contains(lens)
            guard count > 0 || isSelected else { return nil }
            return LensOption(lens: lens, count: count, isSelected: isSelected)
        }

        return snapshot
    }

    // MARK: - Collecting

    /// What a handful of chosen rows becomes when they are gathered into one note.
    public struct Compilation: Equatable {
        public let title: String?
        public let body: String
        public let tags: [String]
        /// The source, when every chosen row came from the same one.
        public let bookId: String?
    }

    /// Gathers the chosen rows into one document.
    ///
    /// A passage's words travel and a note's do not. A passage has no page of its own — the
    /// only place its text exists is the row — so it is quoted in full; a note already is a
    /// page, and copying it here would fork it, so it goes in as a `[[Wiki link]]` that keeps
    /// pointing at the one copy. That is the same trade the link already makes everywhere else
    /// in this app.
    ///
    /// Headings appear only when the selection actually spans sources. Under one source the
    /// note carries the link to it and a heading would be the title printed twice; across
    /// several, the heading is what stops the quotations running together into one voice. For
    /// the same reason a quotation drops its `— Title` attribution when a heading above it has
    /// already said where it came from.
    public static func compile(
        _ entries: [MarginaliaEntry],
        narrowedBy facets: MarginaliaFacets,
        books: [Book],
        on date: Date = Date()
    ) -> Compilation {
        let booksById = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceIDs = Set(entries.map { $0.bookId ?? noSourceKey })
        let sharedBookID = sourceIDs.count == 1 ? entries.first?.bookId : nil
        let needsHeadings = sourceIDs.count > 1

        var lines: [String] = []
        var lastSource: String?

        for entry in entries {
            let source = entry.bookId ?? noSourceKey
            if needsHeadings, source != lastSource {
                let name = source == noSourceKey
                    ? "Without a source"
                    : (booksById[source]?.title ?? entry.bookTitle ?? "Untitled")
                if !lines.isEmpty { lines.append("") }
                lines.append("## \(name)")
                lines.append("")
                lastSource = source
            }

            switch entry {
            case .passage(let passage):
                lines.append(contentsOf: passage.quotation(attributed: !needsHeadings && sharedBookID == nil))
                if let comment = passage.comment {
                    lines.append("")
                    lines.append(comment)
                }
            case .note(let note):
                lines.append("[[\(note.displayTitle)]]")
            }
            lines.append("")
        }

        return Compilation(
            // The words the selection was made under. A compilation gathered while the board
            // was narrowed to `#objection` is about objections, and arriving without the word
            // would make the reader file by hand what they had just filed by pressing a chip.
            title: compiledTitle(facets: facets, books: booksById, sharedBookID: sharedBookID, on: date),
            body: lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n",
            tags: facets.tags.sorted(),
            bookId: sharedBookID
        )
    }

    /// What the gathered note is called. The narrowing names it when there was one, because
    /// that is what the reader was looking at when they chose; otherwise the date, which at
    /// least says when. Never "Untitled" — a document the reader asked to have made should not
    /// arrive without a name.
    private static func compiledTitle(
        facets: MarginaliaFacets,
        books: [String: Book],
        sharedBookID: String?,
        on date: Date
    ) -> String {
        if !facets.tags.isEmpty {
            return facets.tags.sorted().map { "#\($0)" }.joined(separator: " ")
        }
        if let sharedBookID, let book = books[sharedBookID] {
            return "From \(book.title)"
        }
        return "Collected \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private static func byCountThenName(
        _ lhs: MarginaliaFacetOption,
        _ rhs: MarginaliaFacetOption
    ) -> Bool {
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
    }

    static func sorted(_ entries: [MarginaliaEntry], by sort: MarginaliaSort) -> [MarginaliaEntry] {
        switch sort {
        case .recent:
            return entries.sorted { $0.touchedAt > $1.touchedAt }
        case .created:
            return entries.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return entries.sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        }
    }

    /// Sections in the order their first member already stands in.
    ///
    /// Not by size and not alphabetically: the list is already ordered by whatever the reader
    /// chose, and a grouping that re-orders it silently overrules that choice — sort by Title
    /// with sections ordered by date gives alphabetical rows inside newest-first headings,
    /// which is two orders at once and legible as neither.
    static func grouped(
        _ entries: [MarginaliaEntry],
        by grouping: MarginaliaGrouping,
        sort: MarginaliaSort,
        books: [Book],
        calendar: Calendar = .current
    ) -> [MarginaliaGroup] {
        switch grouping {
        case .none:
            return [MarginaliaGroup(id: "all", title: "", entries: entries)]

        case .source:
            let booksById = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return bucketed(entries, key: { $0.bookId ?? noSourceKey }) { key, members in
                MarginaliaGroup(
                    id: key,
                    title: key == noSourceKey
                        ? "No source"
                        : (booksById[key]?.title ?? members.first?.bookTitle ?? "Untitled"),
                    book: booksById[key],
                    entries: members
                )
            }

        case .month:
            let date: (MarginaliaEntry) -> Date = { sort == .created ? $0.createdAt : $0.touchedAt }
            return bucketed(entries, key: { entry in
                let parts = calendar.dateComponents([.year, .month], from: date(entry))
                return "\(parts.year ?? 0)-\(parts.month ?? 0)"
            }) { key, members in
                MarginaliaGroup(
                    id: key,
                    title: members.first.map { date($0).formatted(.dateTime.month(.wide).year()) } ?? "",
                    entries: members
                )
            }
        }
    }

    private static func bucketed(
        _ entries: [MarginaliaEntry],
        key: (MarginaliaEntry) -> String,
        build: (String, [MarginaliaEntry]) -> MarginaliaGroup
    ) -> [MarginaliaGroup] {
        var order: [String] = []
        var buckets: [String: [MarginaliaEntry]] = [:]
        for entry in entries {
            let bucket = key(entry)
            if buckets[bucket] == nil { order.append(bucket) }
            buckets[bucket, default: []].append(entry)
        }
        return order.map { build($0, buckets[$0] ?? []) }
    }
}

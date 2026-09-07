import Foundation

/// The narrowing itself, as a function rather than as a screen.
///
/// Scope, lenses, facets, query, order and grouping are the whole product of the board, and
/// leaving them inside a view model meant they could only be exercised by running the app
/// against a real database — which is exactly the arrangement CLAUDE.md rules out fixtures for.
/// Here they are a pure transform over values: the view model owns the state and the database,
/// this owns what the state *means*, and a test can ask what the counts should be without a
/// simulator.
public enum MarginaliaBoard {

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
        public var lensOptions: [LensOption] = []
        public var writtenCount = 0
        public var savedCount = 0

        public var totalCount: Int { writtenCount + savedCount }
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
        for entry in inScope where facets.matchesTags(entry) {
            if let bookId = entry.bookId { sourceCounts[bookId, default: 0] += 1 }
        }

        let booksById = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sourceNames: [String: String] = [:]
        for entry in entries {
            guard let bookId = entry.bookId, sourceNames[bookId] == nil else { continue }
            sourceNames[bookId] = booksById[bookId]?.title ?? entry.bookTitle ?? "Untitled"
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

        snapshot.sourceOptions = sourceCounts
            .map { bookId, count in
                MarginaliaFacetOption(
                    kind: .source(bookId),
                    label: sourceNames[bookId] ?? "Untitled",
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
                    count: 0,
                    isSelected: true
                )
        }
        let offered = (snapshot.sourceOptions + snapshot.tagOptions)
            .filter { !$0.isSelected && $0.count > 0 }
            .sorted(by: byCountThenName)
        snapshot.facetOptions = chosenSources + chosenTags + offered

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

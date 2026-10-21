import Foundation

/// A source the reader follows: a blog, a journal, a newsletter, or a few fields of arXiv.
///
/// Kept on this device only, in `FeedStore`'s file, not in SQLite and not in CloudKit — see
/// "Лента" in CLAUDE.md. A source is a subscription, not something the reader wrote, and what it
/// brings is by design gone in a few days.
public nonisolated struct FeedSource: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// Where the feed itself is read from. For arXiv this is a query of the arXiv API, built
    /// from `arxivFields`.
    public var feedURL: URL
    /// The site the feed belongs to, for "Open the site".
    public var siteURL: URL?
    public var title: String
    /// What the source says about itself, or the line diple recommends it with.
    public var summary: String?
    /// The character on its seal, when the source has one of its own — arXiv's χ. `nil` takes
    /// the first letter of the title, as a generated cover does.
    public var seal: String?
    /// The arXiv fields this source follows, by code (`cs.AI`). `nil` for an ordinary feed.
    public var arxivFields: [String]?
    public var addedAt: Date
    /// When the source last answered, with news or without.
    public var checkedAt: Date?
    /// The validators of the last answer. Sent back on the next check, so a feed that has not
    /// changed costs a status line rather than the whole document again.
    public var etag: String?
    public var lastModified: String?
    /// Why the last check did not get through, in a sentence. Cleared by the next one that does.
    public var failure: String?

    public init(
        id: String = UUID().uuidString,
        feedURL: URL,
        siteURL: URL? = nil,
        title: String,
        summary: String? = nil,
        seal: String? = nil,
        arxivFields: [String]? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.title = title
        self.summary = summary
        self.seal = seal
        self.arxivFields = arxivFields
        self.addedAt = addedAt
    }

    public var isArxiv: Bool { arxivFields != nil }

    /// `quantamagazine.org` — how the source is told apart from a namesake.
    public var host: String? {
        (siteURL ?? feedURL).host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }
}

/// One piece a source has published: an essay, an article, a paper.
///
/// What the feed says about it, and nothing fetched beyond that. The piece itself is read only
/// when the reader asks for it — then it is fetched and typeset like any saved link and becomes
/// a row of the library (`keptBookID`), which is the one way it outlives the feed.
public nonisolated struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    /// `<source id>|<the feed's own id for the piece>`, so two sources that carry the same
    /// address still keep separate entries.
    public let id: String
    public let sourceID: String
    public var title: String
    public var link: URL
    public var publishedAt: Date?
    public var authors: [String]
    /// The opening of the piece as plain paragraphs, separated by a blank line: what the feed
    /// itself carries. For an arXiv paper, its abstract.
    public var summary: String
    /// How long the piece is, when the feed carried all of it. `nil` prints nothing: a teaser
    /// counted as the whole would promise a two-minute read of a twenty-minute essay.
    public var characterCount: Int?
    public var categories: [String]
    /// `2610.28632v1`, for a paper.
    public var arxivID: String?
    public var pdfURL: URL?
    /// The first time this device saw the piece.
    public var firstSeenAt: Date
    /// Its place in its source's own order — what separates a day's arXiv papers, which share
    /// one date.
    public var rank: Int
    /// The library row it became once the reader read it or kept it.
    public var keptBookID: String?

    /// The date it is filed under: the one the feed gives, but never later than the moment it
    /// was first seen. A feed dated in the future (a time zone written wrong, a scheduled post
    /// published early) would otherwise sit at the head of the feed for days.
    public var filedAt: Date {
        min(publishedAt ?? firstSeenAt, firstSeenAt)
    }

    /// The arXiv number without its version: `2610.28632`.
    public var arxivNumber: String? {
        guard let arxivID else { return nil }
        if let v = arxivID.range(of: "v[0-9]+$", options: .regularExpression) {
            return String(arxivID[..<v.lowerBound])
        }
        return arxivID
    }

    /// `Hengqi Liu, Ziyuan Liu and 8 others` — a byline that stays one line however many people
    /// wrote the paper.
    public var byline: String? {
        switch authors.count {
        case 0: return nil
        case 1: return authors[0]
        case 2: return "\(authors[0]) and \(authors[1])"
        case 3: return "\(authors[0]), \(authors[1]) and \(authors[2])"
        default: return "\(authors[0]), \(authors[1]) and \(authors.count - 2) others"
        }
    }
}

/// The feed's one rule: **each source keeps its three newest pieces, and nothing else.**
///
/// No unread state, no count, no archive of what was missed. A piece that four newer ones have
/// pushed past simply leaves, unless the reader read it or kept it — and then it is in the
/// library, which is where kept things live. The rule is a pure function so it can be read and
/// tested apart from the network and the screen.
public nonisolated enum FeedRack {
    /// Three, not five. A source that writes daily turns over in three days; one that writes
    /// weekly stays a month. Enough to see what someone is thinking about lately, and short
    /// enough that the whole feed reads in a sitting.
    public static let keep = 3

    /// What a source shows after a fresh check.
    ///
    /// The newest pieces the feed carries, by its own dates, ties kept in the feed's order. What
    /// was already known about a piece survives the check — when this device first saw it, and
    /// the library row it became — so a reread feed does not reshuffle the page or forget what
    /// was read.
    public static func merge(
        sourceID: String,
        fetched: [ParsedFeedItem],
        existing: [FeedItem],
        now: Date = Date()
    ) -> [FeedItem] {
        let known = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()

        let candidates: [(index: Int, item: ParsedFeedItem, link: URL)] = fetched.enumerated().compactMap { index, item in
            guard let link = item.link,
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return (index, item, link)
        }

        let ordered = candidates.sorted { lhs, rhs in
            switch (lhs.item.publishedAt, rhs.item.publishedAt) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.index < rhs.index
            }
        }

        var kept: [FeedItem] = []
        for (rank, candidate) in ordered.enumerated() {
            let id = itemID(sourceID: sourceID, item: candidate.item, link: candidate.link)
            // A paper replaced by its next version, or a post listed twice: one entry.
            let identity = candidate.item.arxivID.map(Self.arxivNumber) ?? id
            guard seen.insert(identity).inserted else { continue }

            let previous = known[id]
            kept.append(FeedItem(
                id: id,
                sourceID: sourceID,
                title: candidate.item.title,
                link: candidate.link,
                publishedAt: candidate.item.publishedAt,
                authors: candidate.item.authors,
                summary: candidate.item.summary,
                characterCount: candidate.item.characterCount,
                categories: candidate.item.categories,
                arxivID: candidate.item.arxivID,
                pdfURL: candidate.item.pdfURL,
                firstSeenAt: previous?.firstSeenAt ?? now,
                rank: rank,
                keptBookID: previous?.keptBookID
            ))
            if kept.count == keep { break }
        }
        return kept
    }

    /// The whole feed, newest first. Pieces filed on the same day keep their sources' own
    /// order, so a day of arXiv reads in the order arXiv listed it.
    public static func ordered(_ items: [FeedItem], calendar: Calendar = .current) -> [FeedItem] {
        items.sorted { lhs, rhs in
            let l = lhs.filedAt, r = rhs.filedAt
            if !calendar.isDate(l, inSameDayAs: r) { return l > r }
            if lhs.sourceID == rhs.sourceID, lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if l != r { return l > r }
            return lhs.id < rhs.id
        }
    }

    /// The feed cut into days, for the headings between them.
    public static func days(_ items: [FeedItem], calendar: Calendar = .current) -> [FeedDay] {
        var days: [FeedDay] = []
        for item in ordered(items, calendar: calendar) {
            let day = calendar.startOfDay(for: item.filedAt)
            if let last = days.last, last.day == day {
                days[days.count - 1].items.append(item)
            } else {
                days.append(FeedDay(day: day, items: [item]))
            }
        }
        return days
    }

    static func itemID(sourceID: String, item: ParsedFeedItem, link: URL) -> String {
        let own = item.arxivID.map(arxivNumber) ?? item.guid ?? link.absoluteString
        return "\(sourceID)|\(own)"
    }

    static func arxivNumber(_ id: String) -> String {
        guard let v = id.range(of: "v[0-9]+$", options: .regularExpression) else { return id }
        return String(id[..<v.lowerBound])
    }
}

/// One day of the feed.
public nonisolated struct FeedDay: Identifiable, Hashable, Sendable {
    public let day: Date
    public var items: [FeedItem]
    public var id: Date { day }

    /// `Today`, `Yesterday`, a weekday inside the week, a date beyond it.
    @MainActor
    public func title(now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day,
           days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return DipleDate.day(day, now: now, calendar: calendar)
    }
}

/// A source diple suggests following, before the reader has any — and after, for the ones not
/// followed yet.
///
/// Chosen for two things: nothing behind a paywall, and writing that leaves the reader knowing
/// or thinking better. Six, because a list of recommendations long enough to need scrolling is
/// a directory, and a directory is a chore.
public nonisolated struct FeedRecommendation: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let pitch: String
    public let feedURL: URL
    public let siteURL: URL
    public let seal: String?

    /// arXiv is offered as a set of fields to choose rather than one address.
    public var isArxiv: Bool { id == Self.arxivID }

    static let arxivID = "arxiv"

    public func source() -> FeedSource {
        FeedSource(feedURL: feedURL, siteURL: siteURL, title: title, summary: pitch, seal: seal)
    }

    public static let all: [FeedRecommendation] = [
        FeedRecommendation(
            id: "quanta",
            title: "Quanta Magazine",
            pitch: "Mathematics, physics, biology and computer science at the frontier, explained without talking down.",
            feedURL: url("https://www.quantamagazine.org/feed/"),
            siteURL: url("https://www.quantamagazine.org"),
            seal: nil
        ),
        FeedRecommendation(
            id: "lesswrong",
            title: "LessWrong",
            pitch: "Curated essays on reasoning, decisions and AI — a few a week, chosen by the editors.",
            feedURL: url("https://www.lesswrong.com/feed.xml?view=curated-rss"),
            siteURL: url("https://www.lesswrong.com"),
            seal: nil
        ),
        FeedRecommendation(
            id: arxivID,
            title: "arXiv",
            pitch: "The newest papers in the fields you choose, abstract first and the paper a tap away.",
            feedURL: ArxivField.feedURL(for: ArxivField.suggested),
            siteURL: url("https://arxiv.org"),
            seal: "χ"
        ),
        FeedRecommendation(
            id: "aeon",
            title: "Aeon",
            pitch: "Long essays on philosophy, science and the history of ideas, from the people who work on them.",
            feedURL: url("https://aeon.co/essays/feed.rss"),
            siteURL: url("https://aeon.co"),
            seal: nil
        ),
        FeedRecommendation(
            id: "knowable",
            title: "Knowable Magazine",
            pitch: "Science journalism from the editors of Annual Reviews: what a field has learned, and how it knows.",
            feedURL: url("https://knowablemagazine.org/rss"),
            siteURL: url("https://knowablemagazine.org"),
            seal: nil
        ),
        FeedRecommendation(
            id: "owid",
            title: "Our World in Data",
            pitch: "The world’s large problems — health, poverty, climate — measured, charted and explained.",
            feedURL: url("https://ourworldindata.org/atom.xml"),
            siteURL: url("https://ourworldindata.org"),
            seal: nil
        )
    ]

    private static func url(_ string: String) -> URL {
        // Literals written above; a typo in one is a crash in development, which is when it
        // should be found.
        guard let url = URL(string: string) else { preconditionFailure("Bad recommendation URL \(string)") }
        return url
    }
}

/// A field of arXiv, named the way a reader would name it.
public nonisolated struct ArxivField: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }

    /// The fields offered when arXiv is followed. A short list on purpose: arXiv has a hundred
    /// and fifty, and the ones here are those a curious reader most often wants a window on.
    public static let offered: [ArxivField] = [
        ArxivField(code: "cs.AI", name: "AI"),
        ArxivField(code: "cs.LG", name: "Machine learning"),
        ArxivField(code: "cs.CL", name: "Language"),
        ArxivField(code: "q-bio.NC", name: "Neuroscience"),
        ArxivField(code: "quant-ph", name: "Quantum physics"),
        ArxivField(code: "astro-ph.CO", name: "Cosmology"),
        ArxivField(code: "q-bio.PE", name: "Evolution"),
        ArxivField(code: "econ.GN", name: "Economics")
    ]

    /// Chosen before the reader chooses.
    public static let suggested = ["cs.AI", "cs.LG"]

    /// How many papers are asked for. More than the feed keeps, because the newest few can be
    /// one paper listed under two of the chosen fields.
    static let requested = 12

    /// The arXiv API, newest submissions first, in any of the fields. The API rather than the
    /// fields' RSS: a field's daily RSS is a megabyte listing every new, cross-listed and
    /// replaced paper, of which the feed keeps three; the API answers the same question in
    /// fifteen kilobytes, with each paper's authors, categories and PDF already named.
    public static func feedURL(for codes: [String]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "export.arxiv.org"
        components.path = "/api/query"
        let query = codes.map { "cat:\($0)" }.joined(separator: " OR ")
        components.queryItems = [
            URLQueryItem(name: "search_query", value: query),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
            URLQueryItem(name: "max_results", value: "\(requested)")
        ]
        // The query's spaces are `+` in the API's own examples; URLComponents writes `%20`,
        // which the API reads the same way.
        guard let url = components.url else { preconditionFailure("arXiv query did not form a URL") }
        return url
    }

    /// `arXiv · AI, Machine learning`.
    public static func title(for codes: [String]) -> String {
        let names = codes.map(name(for:))
        return names.isEmpty ? "arXiv" : "arXiv · " + names.joined(separator: ", ")
    }

    /// A category as words: `cs.CV` is Computer vision. A code not in the taxonomy below falls
    /// back to the name of its archive — `cond-mat.xyz` is still Condensed matter — and only a
    /// code with no known archive is printed as it is.
    public static func name(for code: String) -> String {
        if let offered = offered.first(where: { $0.code == code }) { return offered.name }
        if let name = named[code] { return name }
        let archive = code.split(separator: ".").first.map(String.init) ?? code
        return archives[archive] ?? code
    }

    private static let archives: [String: String] = [
        "cs": "Computer science", "math": "Mathematics", "physics": "Physics",
        "cond-mat": "Condensed matter", "astro-ph": "Astrophysics", "q-bio": "Biology",
        "q-fin": "Finance", "stat": "Statistics", "econ": "Economics",
        "eess": "Electrical engineering", "nlin": "Nonlinear science", "quant-ph": "Quantum physics",
        "gr-qc": "Gravitation", "hep-th": "High-energy theory", "hep-ph": "Particle phenomenology",
        "hep-ex": "Particle experiment", "hep-lat": "Lattice field theory", "nucl-th": "Nuclear theory",
        "nucl-ex": "Nuclear experiment", "math-ph": "Mathematical physics"
    ]

    /// arXiv's taxonomy, by the names its fields go by in conversation rather than in the
    /// catalogue: `cs.CL` is Language, not "Computation and Language".
    private static let named: [String: String] = [
        // Computer science
        "cs.AR": "Hardware architecture", "cs.CC": "Computational complexity",
        "cs.CE": "Computational engineering", "cs.CG": "Computational geometry",
        "cs.CR": "Security", "cs.CV": "Computer vision", "cs.CY": "Computers and society",
        "cs.DB": "Databases", "cs.DC": "Distributed computing", "cs.DL": "Digital libraries",
        "cs.DM": "Discrete mathematics", "cs.DS": "Algorithms", "cs.ET": "Emerging technologies",
        "cs.FL": "Formal languages", "cs.GL": "General literature", "cs.GR": "Graphics",
        "cs.GT": "Game theory", "cs.HC": "Human–computer interaction",
        "cs.IR": "Information retrieval", "cs.IT": "Information theory", "cs.LO": "Logic",
        "cs.MA": "Multi-agent systems", "cs.MM": "Multimedia", "cs.MS": "Mathematical software",
        "cs.NA": "Numerical analysis", "cs.NE": "Neural computing", "cs.NI": "Networking",
        "cs.OH": "Computer science", "cs.OS": "Operating systems", "cs.PF": "Performance",
        "cs.PL": "Programming languages", "cs.RO": "Robotics", "cs.SC": "Symbolic computation",
        "cs.SD": "Sound", "cs.SE": "Software engineering", "cs.SI": "Social networks",
        "cs.SY": "Systems and control",
        // Statistics and electrical engineering
        "stat.AP": "Applied statistics", "stat.CO": "Statistical computing",
        "stat.ME": "Statistical methods", "stat.ML": "Statistical learning",
        "stat.OT": "Statistics", "stat.TH": "Statistics theory",
        "eess.AS": "Audio and speech", "eess.IV": "Image and video",
        "eess.SP": "Signal processing", "eess.SY": "Systems and control",
        // Mathematics
        "math.AC": "Commutative algebra", "math.AG": "Algebraic geometry", "math.AP": "Analysis of PDEs",
        "math.AT": "Algebraic topology", "math.CA": "Classical analysis", "math.CO": "Combinatorics",
        "math.CT": "Category theory", "math.CV": "Complex variables", "math.DG": "Differential geometry",
        "math.DS": "Dynamical systems", "math.FA": "Functional analysis", "math.GM": "Mathematics",
        "math.GN": "General topology", "math.GR": "Group theory", "math.GT": "Geometric topology",
        "math.HO": "History of mathematics", "math.IT": "Information theory", "math.KT": "K-theory",
        "math.LO": "Logic", "math.MG": "Metric geometry", "math.MP": "Mathematical physics",
        "math.NA": "Numerical analysis", "math.NT": "Number theory", "math.OA": "Operator algebras",
        "math.OC": "Optimisation", "math.PR": "Probability", "math.QA": "Quantum algebra",
        "math.RA": "Rings and algebras", "math.RT": "Representation theory",
        "math.SG": "Symplectic geometry", "math.SP": "Spectral theory", "math.ST": "Statistics theory",
        // Physics
        "astro-ph.CO": "Cosmology", "astro-ph.EP": "Planets", "astro-ph.GA": "Galaxies",
        "astro-ph.HE": "High-energy astrophysics", "astro-ph.IM": "Astronomical instruments",
        "astro-ph.SR": "Stars",
        "cond-mat.dis-nn": "Disordered systems", "cond-mat.mes-hall": "Mesoscale physics",
        "cond-mat.mtrl-sci": "Materials science", "cond-mat.other": "Condensed matter",
        "cond-mat.quant-gas": "Quantum gases", "cond-mat.soft": "Soft matter",
        "cond-mat.stat-mech": "Statistical mechanics", "cond-mat.str-el": "Strongly correlated electrons",
        "cond-mat.supr-con": "Superconductivity",
        "physics.acc-ph": "Accelerator physics", "physics.ao-ph": "Atmospheric physics",
        "physics.app-ph": "Applied physics", "physics.atm-clus": "Atomic clusters",
        "physics.atom-ph": "Atomic physics", "physics.bio-ph": "Biological physics",
        "physics.chem-ph": "Chemical physics", "physics.class-ph": "Classical physics",
        "physics.comp-ph": "Computational physics", "physics.data-an": "Data analysis",
        "physics.ed-ph": "Physics education", "physics.flu-dyn": "Fluid dynamics",
        "physics.gen-ph": "Physics", "physics.geo-ph": "Geophysics",
        "physics.hist-ph": "History of physics", "physics.ins-det": "Instruments and detectors",
        "physics.med-ph": "Medical physics", "physics.optics": "Optics",
        "physics.plasm-ph": "Plasma physics", "physics.pop-ph": "Popular physics",
        "physics.soc-ph": "Physics and society", "physics.space-ph": "Space physics",
        "nlin.AO": "Self-organising systems", "nlin.CD": "Chaos", "nlin.PS": "Pattern formation",
        // Biology, finance, economics
        "q-bio.BM": "Biomolecules", "q-bio.CB": "Cell behaviour", "q-bio.GN": "Genomics",
        "q-bio.MN": "Molecular networks", "q-bio.OT": "Biology", "q-bio.QM": "Quantitative methods",
        "q-bio.SC": "Subcellular processes", "q-bio.TO": "Tissues and organs",
        "q-fin.CP": "Computational finance", "q-fin.EC": "Economics", "q-fin.GN": "Finance",
        "q-fin.MF": "Mathematical finance", "q-fin.PM": "Portfolio management",
        "q-fin.PR": "Pricing of securities", "q-fin.RM": "Risk management",
        "q-fin.ST": "Statistical finance", "q-fin.TR": "Trading",
        "econ.EM": "Econometrics", "econ.TH": "Economic theory"
    ]
}

import SwiftUI

/// A year of reading, set as a page of an almanac.
///
/// The year is the masthead, its hours are the headline, and everything under them is drawn
/// rather than tabulated where a shape says it better: a field of days, a shelf of the books
/// finished, a rule under each source as long as its share of the year. The accent is spent on
/// one thing only, measured amounts — the role the progress line already gives it — and every
/// other mark is ink.
///
/// **Facts, not a scoreboard.** No streak, goal, badge or comparison with last year, for the
/// reason `ReadingLogView` records: rating a reader is not what a reading app is for. Every
/// figure comes out of `ReadingStatistics.make`, which is where they are tested.
struct ReadingStatisticsView: View {
    @State private var sessions: [ReadingSession] = []
    @State private var books: [Book] = []
    @State private var remembered: [ReadingLogSource] = []
    @State private var stats = ReadingStatistics.make(sessions: [], books: [], remembered: [])
    @State private var year: Int?
    @State private var chosenDay: Date?
    @State private var hasLoaded = false
    /// Drives the one entrance the page makes: rules and bars drawn on to their length.
    @State private var isDrawn = false

    @ScaledMetric(relativeTo: .subheadline) private var rowCoverWidth: CGFloat = 30

    /// The gap between sections — a step wider than the page's widest token, because each
    /// section here is a figure with its own heading and the page reads as a run of plates.
    private let sectionSpacing = DipleSpace.xxxl + DipleSpace.m

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head

                if hasLoaded {
                    if stats.isEmpty {
                        empty
                    } else {
                        VStack(alignment: .leading, spacing: sectionSpacing) {
                            figure
                            if !stats.days.isEmpty { almanac }
                            if !stats.finished.isEmpty { shelf }
                            if !stats.sources.isEmpty { timeBySource }
                            if stats.sittingCount > 0 {
                                rhythm
                                figures
                            }
                            journal
                        }
                        .padding(.top, DipleSpace.xxl)
                    }
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.bottom, DipleSpace.scrollBottom)
            // A page's measure on a desktop window, not the window's width: an almanac stretched
            // to a thousand points is a chart, and its dots drift apart until they stop being a
            // field.
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // The tab bar floats over the page; scrolling down puts it away, as on the roots, so
        // the journal at the foot is never left under glass.
        .tracksTabBarCollapse()
        .background(DipleColor.canvas.ignoresSafeArea())
        .navigationTitle("Reading")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .task { load() }
        .onChange(of: year) { _, _ in
            chosenDay = nil
            withAnimation(DipleMotion.standard) { recompute() }
        }
    }

    // MARK: - Loading

    /// One read of each table, grouped in memory — the log's own rule. The limit is generous
    /// rather than the ledger's default: the statistics need every year, and years of sittings
    /// are still only thousands of rows of six columns.
    private func load() {
        sessions = (try? AppDatabase.shared.fetchReadingSessions(limit: 100_000)) ?? []
        books = (try? AppDatabase.shared.fetchAllBooks()) ?? []
        remembered = (try? AppDatabase.shared.fetchReadingLogSources()) ?? []
        recompute()
        hasLoaded = true
        guard !isDrawn else { return }
        withAnimation(DipleMotion.gentle.delay(0.15)) { isDrawn = true }
    }

    private func recompute() {
        stats = ReadingStatistics.make(sessions: sessions, books: books, remembered: remembered, year: year)
    }

    // MARK: - Head

    /// The year is the page's name. Arrows only when there is another year to go to.
    private var head: some View {
        DipleMasthead(title: String(stats.year), strapline: strapline) {
            if stats.years.count > 1 {
                yearArrow(older: true)
                yearArrow(older: false)
            }
        }
        .contentTransition(.numericText(value: Double(stats.year)))
    }

    private func yearArrow(older: Bool) -> some View {
        let index = stats.years.firstIndex(of: stats.year) ?? 0
        // `years` runs newest first, so an older year is further down the list.
        let target = older ? index + 1 : index - 1
        let isAvailable = stats.years.indices.contains(target)
        return MastheadButton(
            systemImage: older ? "chevron.left" : "chevron.right",
            label: older ? "Previous year" : "Next year"
        ) {
            guard isAvailable else { return }
            year = stats.years[target]
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.3)
    }

    /// The log begins the day it begins, and a page that did not say so would read a short
    /// first year as an idle one.
    private var strapline: String? {
        guard let since = stats.recordedSince,
              Calendar.current.component(.year, from: since) == stats.year
        else { return nil }
        return "Recorded since \(since.formatted(.dateTime.day().month(.wide)))"
    }

    // MARK: - The figure

    private var figure: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xxl) {
            if stats.sittingCount > 0 {
                hoursFigure
            }

            HStack(alignment: .firstTextBaseline, spacing: DipleSpace.l) {
                if stats.sittingCount > 0 {
                    count(stats.readingDayCount, one: "day", many: "days")
                    count(stats.sources.count, one: "source", many: "sources")
                }
                count(stats.finished.count, one: "finished", many: "finished")
            }
        }
    }

    /// The year's hours, the figure in Literata and its units in the interface face a size
    /// down — "41 h 20 min" set as a number with labels, not as a string.
    private var hoursFigure: some View {
        let minutes = stats.totalMinutes
        let hours = minutes / 60
        let rest = minutes % 60

        return HStack(alignment: .firstTextBaseline, spacing: DipleSpace.xs) {
            if hours > 0 {
                figureNumber(hours)
                figureUnit("h")
            }
            if rest > 0 || hours == 0 {
                figureNumber(rest)
                    .padding(.leading, hours > 0 ? DipleSpace.s : 0)
                figureUnit("min")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ReadingEstimate.format(minutes: minutes)) read in \(String(stats.year))")
    }

    private func figureNumber(_ value: Int) -> some View {
        Text("\(value)")
            .dipleType(.editorialFigure)
            .foregroundStyle(DipleColor.textPrimary)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
    }

    private func figureUnit(_ unit: String) -> some View {
        Text(unit)
            .dipleType(.headline, weight: .regular)
            .foregroundStyle(DipleColor.textTertiary)
    }

    private func count(_ value: Int, one: String, many: String) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.hair) {
            Text("\(value)")
                .dipleType(.editorialCount)
                .foregroundStyle(DipleColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(value == 1 ? one : many)
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Days

    /// Every day of the year as a point, a month to a row, sized by how long it was read.
    private var almanac: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            sectionHeading("Days")

            ReadingAlmanac(stats: stats, chosenDay: $chosenDay)

            dayCaption
                .animation(nil, value: chosenDay)
        }
    }

    /// What the field cannot say by itself: which day a dot is. With nothing chosen it names
    /// the fullest day, which is the one the eye goes to first.
    ///
    /// Always two lines, so choosing a day never moves the page under the finger.
    private var dayCaption: some View {
        let date = chosenDay ?? stats.fullestDay?.date
        let day = date.flatMap { stats.day(on: $0) }
        let titles = day?.sources.map(\.source.title).joined(separator: " · ")

        return VStack(alignment: .leading, spacing: DipleSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if let date {
                        Text(chosenDay == nil ? "Fullest day · \(dayTitle(date))" : dayTitle(date))
                    } else {
                        Text(" ")
                    }
                }
                .dipleType(.footnote)
                .foregroundStyle(DipleColor.textPrimary)
                .lineLimit(1)

                Spacer(minLength: DipleSpace.m)

                if let day {
                    Text(ReadingEstimate.format(minutes: max(day.minutes, 1)))
                        .dipleType(.footnote, weight: .regular)
                        .foregroundStyle(DipleColor.textSecondary)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
            }

            Text(titles ?? (date == nil ? " " : "Nothing read"))
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: - Finished

    /// The year's finished books, as a shelf — covers, in the order they were finished. A book
    /// deleted since keeps its place and its artwork; that is what `ReadingLogSource` is for.
    private var shelf: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            sectionHeading("Finished")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: DipleSpace.l, alignment: .top)],
                alignment: .leading,
                spacing: DipleSpace.xxl
            ) {
                ForEach(stats.finished) { source in
                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        BookCoverView(
                            coverPath: source.coverPath,
                            title: source.title,
                            author: source.author
                        )

                        VStack(alignment: .leading, spacing: DipleSpace.hair) {
                            // A size under the shelf's own `editorialItem`, at its weight: the
                            // library sets two covers to a row and this shelf three, and at 17
                            // pt a single long word ("Middlemarch") no longer fit a column and
                            // broke in the middle.
                            Text(source.title)
                                .dipleType(.editorialExcerpt, weight: .medium)
                                .foregroundStyle(DipleColor.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .multilineTextAlignment(.leading)

                            if let finishedAt = source.finishedAt {
                                Text(finishedAt.formatted(.dateTime.day().month(.abbreviated)))
                                    .dipleType(.caption)
                                    .foregroundStyle(DipleColor.textTertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Where the time went

    /// The sources the year was spent on, longest first. The rule under each row is as long as
    /// its share of the year — the library's catalogue rule doing the same two jobs here: it
    /// closes the row and it measures it.
    private var timeBySource: some View {
        let shown = Array(stats.sources.prefix(5))
        let rest = stats.sources.dropFirst(5)
        let restSeconds = rest.reduce(0) { $0 + $1.seconds }

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeading("Where the time went")
                .padding(.bottom, DipleSpace.s)

            ForEach(shown) { item in
                sourceRow(item)
            }

            if !rest.isEmpty {
                let count = rest.count == 1 ? "1 more source" : "\(rest.count) more sources"
                Text("\(count) · \(ReadingEstimate.format(minutes: Int((restSeconds / 60).rounded())))")
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .monospacedDigit()
                    .padding(.top, DipleSpace.m)
            }
        }
    }

    private func sourceRow(_ item: ReadingStatistics.SourceTime) -> some View {
        let share = stats.totalSeconds > 0 ? item.seconds / stats.totalSeconds : 0

        return HStack(alignment: .center, spacing: DipleSpace.m) {
            BookCoverView(
                coverPath: item.source.coverPath,
                title: item.source.title,
                author: item.source.author,
                isCompact: true
            )
            .frame(width: rowCoverWidth, height: rowCoverWidth * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.hair) {
                Text(item.source.title)
                    .dipleType(.editorialItem)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(1)

                if let author = item.source.author {
                    Text(author)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ReadingEstimate.format(minutes: max(item.minutes, 1)))
                .dipleType(.footnote, weight: .regular)
                .foregroundStyle(DipleColor.textSecondary)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DipleColor.hairline)
                    Rectangle()
                        .fill(DipleColor.accentInk)
                        .frame(width: geo.size.width * (isDrawn ? share : 0))
                }
            }
            .frame(height: DipleStroke.regular)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int((share * 100).rounded())) percent of the year")
    }

    // MARK: - When

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            sectionHeading("When you read")

            hoursOfDay

            if let settled = stats.settledHour {
                Text("Most often around \(hourLabel(settled)).")
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
            }

            week
                .padding(.top, DipleSpace.l)
        }
    }

    /// Twenty-four bars, drawn rather than written — a shape read in one glance, where a table
    /// of hours would never be read at all.
    private var hoursOfDay: some View {
        let peak = stats.hoursOfDay.max() ?? 0

        return VStack(spacing: DipleSpace.s) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0 ..< 24, id: \.self) { hour in
                    let share = peak > 0 ? stats.hoursOfDay[hour] / peak : 0
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(share > 0 ? DipleColor.accentInk : DipleColor.separator)
                        .frame(height: share > 0 ? max(3, 56 * share * (isDrawn ? 1 : 0.04)) : 2)
                }
            }
            .frame(height: 56, alignment: .bottom)

            HStack {
                hourTick("00")
                Spacer()
                hourTick("06")
                Spacer()
                hourTick("12")
                Spacer()
                hourTick("18")
                Spacer()
                hourTick("24")
            }
        }
        .accessibilityElement()
        .accessibilityLabel(stats.settledHour.map { "Hours of the day. Most often around \(hourLabel($0))." } ?? "Hours of the day")
    }

    /// The days of the week as points, the same mark as the field of days above. The busiest
    /// day's letter is set in full ink; the dots already say the rest.
    private var week: some View {
        let peak = stats.weekdays.max() ?? 0
        let settled = stats.settledWeekdayIndex
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols

        return HStack(spacing: 0) {
            ForEach(0 ..< 7, id: \.self) { index in
                let share = peak > 0 ? stats.weekdays[index] / peak : 0
                let symbolIndex = (stats.firstWeekday - 1 + index) % 7
                VStack(spacing: DipleSpace.s) {
                    Circle()
                        .fill(share > 0 ? DipleColor.accentInk : DipleColor.hairlineStrong)
                        .frame(
                            width: share > 0 ? 4 + 12 * share.squareRoot() : 3,
                            height: share > 0 ? 4 + 12 * share.squareRoot() : 3
                        )
                        .scaleEffect(isDrawn ? 1 : 0.2)
                        .frame(height: 16)

                    Text(symbols.indices.contains(symbolIndex) ? symbols[symbolIndex] : "")
                        .dipleType(.nano)
                        .foregroundStyle(settled == index ? DipleColor.textPrimary : DipleColor.textQuaternary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(weekAccessibilityLabel)
    }

    private var weekAccessibilityLabel: String {
        guard let settled = stats.settledWeekdayIndex else { return "Days of the week" }
        let symbols = Calendar.current.standaloneWeekdaySymbols
        let symbolIndex = (stats.firstWeekday - 1 + settled) % 7
        guard symbols.indices.contains(symbolIndex) else { return "Days of the week" }
        return "Days of the week. Most of all on \(symbols[symbolIndex])."
    }

    private func hourTick(_ text: String) -> some View {
        Text(text)
            .dipleType(.nano)
            .foregroundStyle(DipleColor.textQuaternary)
            .monospacedDigit()
    }

    private func hourLabel(_ hour: Int) -> String {
        guard let date = Calendar.current.date(from: DateComponents(hour: hour)) else { return "\(hour)" }
        return date.formatted(.dateTime.hour())
    }

    // MARK: - Figures

    /// The rest of the year in numbers, set as a colophon: a label and a figure to a line.
    private var figures: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("In figures")
                .padding(.bottom, DipleSpace.s)

            figureRow("Sittings", value: stats.sittingCount.formatted())

            if let average = stats.averageSittingMinutes {
                figureRow("Average sitting", value: ReadingEstimate.format(minutes: max(average, 1)))
            }

            if let longest = stats.longestSitting {
                figureRow(
                    "Longest sitting",
                    value: ReadingEstimate.format(minutes: max(longest.minutes, 1)),
                    detail: "\(longest.title), \(longest.date.formatted(.dateTime.day().month(.abbreviated)))"
                )
            }

            if stats.pages > 0 {
                figureRow("Pages", value: "≈ \(stats.pages.formatted())")
            }

            if let pace = stats.pagesPerHour, pace > 0 {
                figureRow("Pace", value: "≈ \(pace) pages an hour")
            }

            if stats.pages > 0 {
                Text("A page is 1,800 characters of text, the standard typescript page.")
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DipleSpace.m)
            }
        }
    }

    private func figureRow(_ label: String, value: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DipleSpace.m) {
            VStack(alignment: .leading, spacing: DipleSpace.hair) {
                Text(label)
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textSecondary)

                if let detail {
                    Text(detail)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .dipleType(.body, weight: .medium)
                .foregroundStyle(DipleColor.textPrimary)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Journal

    /// The day-by-day ledger, one page further in. The statistics are the year at a glance;
    /// the journal is where the glance came from.
    private var journal: some View {
        NavigationLink {
            ReadingLogView()
        } label: {
            HStack(spacing: DipleSpace.m) {
                VStack(alignment: .leading, spacing: DipleSpace.hair) {
                    Text("Journal")
                        .dipleType(.body, weight: .medium)
                        .foregroundStyle(DipleColor.textPrimary)
                    Text("Every sitting, day by day")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .dipleIcon(12, weight: .semibold)
                    .foregroundStyle(DipleColor.textQuaternary)
            }
            .padding(.vertical, DipleSpace.m)
            .overlay(alignment: .top) {
                Rectangle().fill(DipleColor.separator).frame(height: DipleStroke.hairline)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(DipleColor.separator).frame(height: DipleStroke.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("statistics.journal")
    }

    // MARK: - Pieces

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .dipleSectionHeading()
            .accessibilityAddTraits(.isHeader)
    }

    /// Nothing measured and nothing finished: the log begins the day it begins.
    private var empty: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("Nothing written down yet")
                .dipleType(.editorialTitle)
                .foregroundStyle(DipleColor.textPrimary)

            Text("Sittings are recorded as you read. A page or two is enough for one to count; a book left open on the table is not reading and is not written down.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DipleSpace.xxxl)
    }
}

// MARK: - The field of days

/// The year a month to a row and a day to a column, each day a point sized by how long it was
/// read — by area rather than diameter, so a two-hour day looks twice an hour's and not four
/// times it.
///
/// Three kinds of day, told apart by mark rather than by colour: a day read on is an accent
/// point; a day the log was keeping and nothing was read is a faint point; a day still to come
/// is fainter still. Days before the log began are not drawn at all, and neither are their
/// months — the log does not know them, and a row of empty points would claim it did.
///
/// Drawn in one `Canvas`: a year is 365 marks, which as views would be 365 hit-tested,
/// diffed and laid-out children for a picture.
private struct ReadingAlmanac: View {
    let stats: ReadingStatistics
    @Binding var chosenDay: Date?

    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 34

    private let calendar = Calendar.current

    var body: some View {
        let months = self.months
        let secondsByDay = Dictionary(stats.days.map { ($0.date, $0.seconds) }, uniquingKeysWith: +)
        let peak = stats.days.map(\.seconds).max() ?? 0

        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(months, id: \.self) { month in
                    Text(month.formatted(.dateTime.month(.abbreviated)))
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textQuaternary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                }
            }

            GeometryReader { geo in
                field(months: months, secondsByDay: secondsByDay, peak: peak, size: geo.size)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        choose(at: location, in: geo.size, months: months)
                    }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            choose(at: location, in: geo.size, months: months, isHover: true)
                        case .ended:
                            chosenDay = nil
                        }
                    }
            }
            .frame(height: rowHeight * CGFloat(months.count))
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private func field(months: [Date], secondsByDay: [Date: Double], peak: Double, size: CGSize) -> some View {
        let today = calendar.startOfDay(for: Date())
        let firstDay = self.firstDay
        let chosen = chosenDay.map { calendar.startOfDay(for: $0) }
        let ink = DipleColor.accentInk
        let empty = DipleColor.hairlineStrong
        let future = DipleColor.separator
        let ring = DipleColor.textPrimary
        let todayRing = DipleColor.textQuaternary

        return Canvas { context, canvasSize in
            let pitch = canvasSize.width / 31
            let largest = max(4, min(pitch, rowHeight) - 3)
            let smallest = min(3.5, largest)

            func circle(_ center: CGPoint, _ diameter: CGFloat) -> Path {
                Path(ellipseIn: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                ))
            }

            for (row, month) in months.enumerated() {
                let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
                for offset in 0 ..< dayCount {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: month) else { continue }
                    guard date >= firstDay else { continue }

                    let center = CGPoint(
                        x: (CGFloat(offset) + 0.5) * pitch,
                        y: (CGFloat(row) + 0.5) * rowHeight
                    )

                    if date > today {
                        context.fill(circle(center, 2), with: .color(future))
                        continue
                    }

                    let seconds = secondsByDay[date] ?? 0
                    if seconds > 0, peak > 0 {
                        let share = (seconds / peak).squareRoot()
                        // Size carries the amount; a lighter ink on the small points lets the
                        // long days stand forward, the way a heavier stroke does on a page.
                        context.fill(
                            circle(center, smallest + (largest - smallest) * share),
                            with: .color(ink.opacity(0.45 + 0.55 * share))
                        )
                    } else if date == today {
                        context.stroke(circle(center, largest - 1), with: .color(todayRing), lineWidth: DipleStroke.regular)
                    } else {
                        context.fill(circle(center, 2.5), with: .color(empty))
                    }

                    if date == chosen {
                        context.stroke(circle(center, largest + 4), with: .color(ring), lineWidth: DipleStroke.regular)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The first day the field draws: January the 1st, or the day the log began if that was
    /// later in this year.
    private var firstDay: Date {
        let start = calendar.date(from: DateComponents(year: stats.year, month: 1, day: 1)) ?? Date.distantPast
        guard let since = stats.recordedSince else { return start }
        return max(start, calendar.startOfDay(for: since))
    }

    /// From the month the log began (or January) to December. The year to come is drawn, faint:
    /// a page of the whole year, filled as far as the year has gone.
    private var months: [Date] {
        let firstMonth = calendar.component(.year, from: firstDay) == stats.year
            ? calendar.component(.month, from: firstDay)
            : 1
        return (firstMonth ... 12).compactMap {
            calendar.date(from: DateComponents(year: stats.year, month: $0, day: 1))
        }
    }

    private func choose(at location: CGPoint, in size: CGSize, months: [Date], isHover: Bool = false) {
        let pitch = size.width / 31
        guard pitch > 0, rowHeight > 0 else { return }
        let row = Int(location.y / rowHeight)
        let column = Int(location.x / pitch)
        guard months.indices.contains(row), (0 ..< 31).contains(column) else { return }

        let month = months[row]
        guard let date = calendar.date(byAdding: .day, value: column, to: month),
              calendar.isDate(date, equalTo: month, toGranularity: .month),
              date >= firstDay,
              date <= calendar.startOfDay(for: Date())
        else {
            if !isHover { chosenDay = nil }
            return
        }

        if !isHover, let chosenDay, calendar.isDate(chosenDay, inSameDayAs: date) {
            // A second touch on the chosen day puts it down again.
            self.chosenDay = nil
            return
        }
        guard chosenDay.map({ !calendar.isDate($0, inSameDayAs: date) }) ?? true else { return }
        if !isHover { HapticManager.shared.selection() }
        chosenDay = date
    }

    private var accessibilityLabel: String {
        let days = stats.readingDayCount == 1 ? "1 day" : "\(stats.readingDayCount) days"
        guard let fullest = stats.fullestDay else { return "Days read: \(days)" }
        return "Days read: \(days). The fullest was \(fullest.date.formatted(.dateTime.day().month(.wide))), \(ReadingEstimate.format(minutes: max(fullest.minutes, 1)))."
    }
}

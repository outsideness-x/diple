import Foundation

/// A date as the catalogue prints it: the day and the month, and the year only when it is not
/// this one.
///
/// `Sep 28, 2026` on every card of a passage saved this week spent a third of the dateline on a
/// fact nobody needed — of course it is this year. A date from another year still prints it,
/// because there the year is the news. Through `Date.FormatStyle`, so the order and the month's
/// name are the reader's own: `Sep 28`, `28 Sep`, `28 сент.`.
///
/// For dates shown as metadata. A date that becomes part of something the reader keeps — a
/// note's default title, a compilation's name, an exported file — keeps its year, because it
/// will still be read next year.
public enum DipleDate {
    public static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(style)
            : date.formatted(style.year())
    }

    /// The same, with the time of day — for an edit or an export, where the hour is part of what
    /// the reader is checking.
    public static func dayAndTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute()
        return calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(style)
            : date.formatted(style.year())
    }
}

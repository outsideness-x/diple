import Foundation
import ReadiumShared

/// The reader-authored thought which can be drawn in a page margin.
///
/// This is deliberately a projection of `Highlight`, not another stored annotation. Its anchor
/// is the original Readium locator, so changing type size or rotating the device asks Readium to
/// lay the same semantic range out again instead of trying to repair a saved screen coordinate.
public nonisolated struct LivingMarginAnnotation: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let note: String
    public let locator: Locator

    public init(id: String, note: String, locator: Locator) {
        self.id = id
        self.note = note
        self.locator = locator
    }
}

/// Pure mapping and navigation for Living Margins.
///
/// Keeping this outside the navigator makes the data rule explicit and testable: only a valid
/// highlight locator with non-blank personal writing becomes a marker. Bookmarks and ordinary
/// notes never enter this path, and a highlight without a thought is filtered out here once.
public nonisolated enum LivingMarginAnnotations {
    public static func make(from highlights: [Highlight]) -> [LivingMarginAnnotation] {
        highlights.compactMap { highlight in
            guard let locator = highlight.parsedLocator,
                  let note = normalizedNote(highlight.comment)
            else { return nil }
            return LivingMarginAnnotation(id: highlight.id, note: note, locator: locator)
        }
        .sorted(by: isBefore)
    }

    /// The thought nearest the reader's current semantic location. Global publication
    /// progression is the strongest comparable coordinate; old locators fall back to a
    /// resource-local progression, then to the deterministic book order used by the marker list.
    public static func nearest(
        to current: Locator?,
        in annotations: [LivingMarginAnnotation]
    ) -> LivingMarginAnnotation? {
        guard !annotations.isEmpty else { return nil }
        guard let current else { return annotations.first }

        if let progression = current.locations.totalProgression {
            let comparable = annotations.filter { $0.locator.locations.totalProgression != nil }
            if let nearest = comparable.min(by: {
                distance($0.locator.locations.totalProgression, from: progression)
                    < distance($1.locator.locations.totalProgression, from: progression)
            }) {
                return nearest
            }
        }

        if let position = current.locations.position {
            let comparable = annotations.filter { $0.locator.locations.position != nil }
            if let nearest = comparable.min(by: {
                abs(($0.locator.locations.position ?? position) - position)
                    < abs(($1.locator.locations.position ?? position) - position)
            }) {
                return nearest
            }
        }

        let inResource = annotations.filter { $0.locator.href.isEquivalentTo(current.href) }
        if let progression = current.locations.progression,
           let nearest = inResource.min(by: {
               distance($0.locator.locations.progression, from: progression)
                   < distance($1.locator.locations.progression, from: progression)
           }) {
            return nearest
        }

        return inResource.first ?? annotations.first
    }

    private static func normalizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func distance(_ value: Double?, from target: Double) -> Double {
        value.map { abs($0 - target) } ?? .greatestFiniteMagnitude
    }

    private static func isBefore(
        _ lhs: LivingMarginAnnotation,
        _ rhs: LivingMarginAnnotation
    ) -> Bool {
        let left = Position(locator: lhs.locator)
        let right = Position(locator: rhs.locator)
        return left.isBefore(right, id: lhs.id, otherID: rhs.id)
    }

    /// A strict total order for the stable fields already present in a locator. Known values
    /// sort before missing ones at each level; using only the fields two particular locators
    /// happen to share can produce a non-transitive comparison across a mixed old/new library.
    private struct Position {
        let totalProgression: Double?
        let position: Int?
        let href: String
        let progression: Double?
        let selector: String

        init(locator: Locator) {
            totalProgression = locator.locations.totalProgression
            position = locator.locations.position
            href = locator.href.string
            progression = locator.locations.progression
            if let cssSelector = locator.locations.cssSelector {
                selector = cssSelector
            } else {
                let start = locator.locations["domRange"]?.object?["start"]?.object
                let cssSelector = start?["cssSelector"]?.string ?? ""
                let offset = start?["charOffset"]?.integer ?? start?["offset"]?.integer
                selector = offset.map { "\(cssSelector):\($0)" } ?? cssSelector
            }
        }

        func isBefore(_ other: Self, id: String, otherID: String) -> Bool {
            if let comparison = Self.compare(totalProgression, other.totalProgression) {
                return comparison
            }
            if let comparison = Self.compare(position, other.position) {
                return comparison
            }
            if href != other.href { return href < other.href }
            if let comparison = Self.compare(progression, other.progression) {
                return comparison
            }
            if selector != other.selector { return selector < other.selector }
            return id < otherID
        }

        private static func compare<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Bool? {
            switch (lhs, rhs) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            default: return nil
            }
        }
    }
}

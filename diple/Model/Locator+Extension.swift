import Foundation
import ReadiumShared

public extension Locator {
    /// Helper to safely deserialize a Readium Locator from a stored JSON string.
    ///
    /// Explicitly `nonisolated`: the project defaults every declaration to `@MainActor`, and a
    /// pure parse of a stored string has no business being pinned there — the search index
    /// resolves locators from `Sendable` value types off the main actor.
    nonisolated static func from(jsonString: String?) -> Locator? {
        guard let locatorStr = jsonString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locatorStr.isEmpty else {
            return nil
        }
        if let jsonValue = try? JSONValue(jsonString: locatorStr),
           let loc = try? Locator(json: jsonValue) {
            return loc
        }
        if let loc = try? Locator(legacyJSONString: locatorStr) {
            return loc
        }
        return nil
    }
}

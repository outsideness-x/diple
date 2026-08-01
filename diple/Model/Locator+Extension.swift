import Foundation
import ReadiumShared

public extension Locator {
    /// Helper to safely deserialize a Readium Locator from a stored JSON string.
    static func from(jsonString: String?) -> Locator? {
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

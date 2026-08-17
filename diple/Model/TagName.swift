import Foundation

/// The one definition of what a tag *is*.
///
/// Notes and sources are tagged independently — they are different vocabularies over different
/// things, and a shared table would force one on the other. What they must not have is two
/// different answers to "are `#Physics`, `physics ` and `Physics` the same tag", because two
/// such rules drift apart at the first edit to either one. So the tables stay separate and the
/// normalisation lives here.
public enum TagName {
    /// Tags are matched case-insensitively and written with or without a leading `#`, so they
    /// are stored in a single normalized form. Returns `nil` for anything that normalizes to
    /// nothing, which is what keeps a stray `#` out of the tag list.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

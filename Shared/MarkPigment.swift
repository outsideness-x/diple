import Foundation

/// What a stored mark colour is **drawn** in.
///
/// A passage keeps the six bytes it was marked with. They are in the database, in the CloudKit
/// record and in every export, and an older build on the reader's other device reads them as they
/// are — so what changed on 2026-09-30 is only how those bytes are drawn, never what is stored.
///
/// Three of the four marks were iOS's own system colours — `systemYellow`, `systemGreen` and
/// `systemPink`, in their dark variants — and on the page, in the highlight bar and down the
/// stripes in Highlights they read as the system's markup tools, neon beside warm paper and the
/// Vellum accent. They now draw as pigments: ochre, rose, sage and lavender, with azure for the
/// retired blue. The bookmarks' own palette, a separate six, goes through the same table.
///
/// **Two strengths per pigment.** `paper` for light pages and the light interface; `night` for
/// dark ones, a step lighter, because the paper strength sinks into a night ground. Choosing the
/// ground is the caller's business — the reader asks the page, the interface asks its appearance.
///
/// **An unknown value draws as itself.** This is a lookup with a pass-through, not a `switch` over
/// the palette: a colour the table has never heard of — imported, or added by a later build — is
/// still a colour rather than a trap, which is the property `DipleColor.Highlight.blue` relies on.
///
/// Lives in `Shared/` because the widget draws the day's passage too, and a mark must be the same
/// colour on the Home Screen as in the app.
public enum MarkPigment {
    public enum Ground: Sendable, Equatable {
        case paper
        case night
    }

    private struct Pigment {
        let name: String
        let paper: String
        let night: String
    }

    private static let ochre = Pigment(name: "Ochre", paper: "#EDC455", night: "#F2CD62")
    private static let rose = Pigment(name: "Rose", paper: "#DE8278", night: "#E99488")
    private static let sage = Pigment(name: "Sage", paper: "#86B070", night: "#98C283")
    private static let lavender = Pigment(name: "Lavender", paper: "#AB90D6", night: "#BCA3E2")
    private static let azure = Pigment(name: "Azure", paper: "#86A9CF", night: "#9DBDE0")
    private static let saffron = Pigment(name: "Saffron", paper: "#E3A456", night: "#EDB570")
    private static let cinnabar = Pigment(name: "Cinnabar", paper: "#D6735F", night: "#E48A76")

    /// Keyed by the stored value, upper-cased with its `#`. The first five are the passage
    /// palette (`DipleColor.Highlight`), the rest the bookmark palette (`AddBookmarkSheetView`);
    /// lilac is in both, and draws as lavender in both.
    private static let table: [String: Pigment] = [
        "#FFD60A": ochre,
        "#FF375F": rose,
        "#30D158": sage,
        "#DF9BE1": lavender,
        "#64D2FF": azure,
        "#FFE066": ochre,
        "#6BCB77": sage,
        "#4D96FF": azure,
        "#FFB03A": saffron,
        "#FF6B6B": cinnabar
    ]

    /// The hex a stored mark colour is drawn in on `ground`, or the stored value itself when the
    /// table does not know it.
    public static func hex(forStored stored: String, on ground: Ground) -> String {
        guard let pigment = table[key(stored)] else { return stored }
        switch ground {
        case .paper: return pigment.paper
        case .night: return pigment.night
        }
    }

    /// What the reader calls the mark — "Ochre", not "Yellow" — or `nil` for a colour the table
    /// does not know, so a caller can fall back to its own word.
    public static func name(forStored stored: String) -> String? {
        table[key(stored)]?.name
    }

    private static func key(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
    }
}

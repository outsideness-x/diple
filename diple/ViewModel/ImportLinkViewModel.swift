import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
public final class ImportLinkViewModel: ObservableObject {
    @Published public var urlText: String = ""
    @Published public private(set) var stage: LinkImporter.Stage? = nil
    @Published public private(set) var errorMessage: String? = nil
    /// True once the pasteboard is known to hold a link, so the paste affordance only appears
    /// when it would do something.
    @Published public private(set) var canPaste: Bool = false

    public init() {}

    public var isImporting: Bool { stage != nil }

    public var resolvedURL: URL? { Self.normalize(urlText) }

    /// Accepts what people actually paste.
    ///
    /// A bare `towardsdatascience.com/…` gets `https://`, because a reader copying a link out
    /// of a share sheet or a message should not have to know that `URL(string:)` treats a
    /// scheme-less string as a relative path. The dot in the host is what separates a real
    /// address from a half-typed one.
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        let lowercased = text.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            guard !lowercased.contains("://") else { return nil }
            text = "https://" + text
        }

        guard let url = URL(string: text),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix(".")
        else { return nil }

        // ATS blocks plain HTTP because the app deliberately carries no arbitrary-loads
        // exception. Upgrade a pasted legacy address here instead of accepting a URL that can
        // only fail later with an opaque network error.
        components.scheme = "https"
        return components.url
    }

    /// `hasURLs`/`hasStrings` answer without handing over the contents, so checking costs the
    /// reader neither a privacy banner nor a permission prompt. The clipboard is only actually
    /// read when they tap Paste.
    public func refreshPasteAvailability() {
        canPaste = UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings
    }

    public func pasteFromClipboard() {
        if let url = UIPasteboard.general.url {
            urlText = url.absoluteString
        } else if let string = UIPasteboard.general.string {
            urlText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        errorMessage = nil
    }

    public func importLink(onFinished: @escaping (Book) -> Void) {
        guard let url = resolvedURL, !isImporting else { return }

        errorMessage = nil
        stage = .fetching

        Task {
            do {
                let book = try await LinkImporter.shared.importLink(from: url) { stage in
                    Task { @MainActor [weak self] in
                        self?.stage = stage
                    }
                }
                HapticManager.shared.notification(.success)
                stage = nil
                onFinished(book)
            } catch {
                HapticManager.shared.notification(.error)
                stage = nil
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

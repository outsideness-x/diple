import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A compilation on its way out of the app.
///
/// Collecting rows into a note keeps them in diple; this is the other half — the same bytes as
/// a file, so a gathered set of passages can land in a vault, a draft or a mail without being
/// copied out of a note by hand afterwards. It is the same document `NoteMarkdownExport` writes
/// into the Markdown folder, because a compilation shared to a friend and a compilation
/// exported to a vault must not be two different documents.
///
/// Two representations, in this order. The file is first because it is the one that cannot be
/// improvised at the other end: Files, Obsidian and any editor want something with a name.
/// The plain string is second, so Messages, Mail and the sheet's own Copy get the text rather
/// than an attachment nobody asked for.
public nonisolated struct MarginaliaDocument: Transferable {
    /// What the file is called, before the extension. Already a real title — the compilation is
    /// named by whatever the board was narrowed to when it was gathered.
    public let name: String
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }

    /// `.md`, and deliberately typed as plain text rather than declared as a Markdown UTI.
    /// Declaring one means owning it in Info.plist and telling the system this app is a handler
    /// for every Markdown file on the device — a claim about the whole app made in order to
    /// name one temporary file.
    public var fileName: String {
        MarkdownLibraryExporter.safeFileName(name) + ".md"
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { document in
            // The app's own temporary directory: it is writable inside the sandbox on both
            // platforms, and the system clears it, so a share that is cancelled halfway leaves
            // nothing behind to clean up.
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(document.fileName)
            try document.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.fileName }

        ProxyRepresentation { $0.text }
    }
}

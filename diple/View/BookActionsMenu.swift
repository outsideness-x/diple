import SwiftUI

/// Everything a reader can do to a source without opening it, in one place.
///
/// The set used to live inside `BookItemView`, which meant it existed on the grid and nowhere
/// else. The list browser had swipe actions covering three of the seven entries, so switching
/// the library to rows quietly took Source Overview, Mark as Finished and Edit Metadata away —
/// the same long press answered differently depending on how the shelf happened to be laid
/// out. A menu owned by one card is a menu that drifts from the other; this one is owned by the
/// action set, and every browser applies it.
///
/// Swipes stay what they are: the two or three moves worth making with a thumb while triaging.
/// They are a shortcut into this menu's contents, never a competing list.
public struct BookActionsMenu: ViewModifier {
    public let book: Book
    public let onShowOverview: () -> Void
    public let onOpenSecondRead: () -> Void
    public let onMarkAsFinished: () -> Void
    public let onMove: (BookLocation) -> Void
    public let onEditTags: () -> Void
    public let onEdit: () -> Void
    public let onDelete: () -> Void

    public func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                onShowOverview()
            } label: {
                Label("Source overview", systemImage: "info.circle")
            }

            if LibraryStatusFilter.finished.includes(book) {
                Button {
                    onOpenSecondRead()
                } label: {
                    Label("Second Read", systemImage: "text.book.closed")
                }
            }

            // Reads the saved position, like everything else the reader is shown: a book that
            // was finished and then reopened to reread is not finished any more, and offering
            // to finish it again is the honest entry.
            if book.progress < 0.995 {
                Button {
                    onMarkAsFinished()
                } label: {
                    Label("Mark as Finished", systemImage: "checkmark.circle")
                }
            }

            // Only the places this source is not already in — an action that would do nothing
            // is one more thing to read past every time the menu opens.
            ForEach(BookLocation.allCases.filter { $0 != book.location }, id: \.self) { destination in
                Button {
                    onMove(destination)
                } label: {
                    Label("Move to \(destination.title)", systemImage: destination.systemImage)
                }
            }

            Button {
                onEditTags()
            } label: {
                Label("Tags…", systemImage: "number")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit metadata", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

public extension View {
    /// Attaches the library's long-press menu to a source, however that source is drawn.
    func bookActionsMenu(
        for book: Book,
        onShowOverview: @escaping () -> Void,
        onOpenSecondRead: @escaping () -> Void,
        onMarkAsFinished: @escaping () -> Void,
        onMove: @escaping (BookLocation) -> Void,
        onEditTags: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(BookActionsMenu(
            book: book,
            onShowOverview: onShowOverview,
            onOpenSecondRead: onOpenSecondRead,
            onMarkAsFinished: onMarkAsFinished,
            onMove: onMove,
            onEditTags: onEditTags,
            onEdit: onEdit,
            onDelete: onDelete
        ))
    }
}

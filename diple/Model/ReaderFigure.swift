import UIKit

/// An illustration lifted off the page, at the size the file actually holds.
///
/// A figure is set at the width the publisher's stylesheet gives it, which on a phone is the
/// column — and a diagram drawn for a printed page does not survive being fitted into 350
/// points. The bytes in the EPUB are usually several times that. Nothing here is stored: the
/// image is read from the publication when it is tapped and released when it is closed.
public struct ReaderFigure: Identifiable {
    /// The illustration's address inside the publication, which is also what makes reopening
    /// the same figure the same view.
    public let id: String
    public let image: UIImage
    /// The publisher's `alt` text, when there is any. Printed under the image, because it is
    /// what the figure says about itself — and it is the only description a reader who cannot
    /// see the image has.
    public let caption: String?
}

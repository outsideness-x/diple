import SwiftUI

public struct BookCoverView: View {
    public let coverPath: String?
    public let title: String
    public let author: String?

    /// The placeholder spells the title and author out, which needs more room than a list
    /// thumbnail has — at that size it would push past its own frame. Compact draws the
    /// glyph alone.
    public let isCompact: Bool

    public init(coverPath: String?, title: String, author: String?, isCompact: Bool = false) {
        self.coverPath = coverPath
        self.title = title
        self.author = author
        self.isCompact = isCompact
    }

    private var loadedImage: UIImage? {
        guard let coverPath = coverPath else { return nil }
        return CoverImageCache.shared.image(atRelativePath: coverPath)
    }

    /// Sized from the cover rather than the type ramp: this glyph is the artwork, so it has to
    /// hold the same proportion of a 44pt thumbnail and a full grid cell.
    private func initialSize(for geometry: GeometryProxy) -> CGFloat {
        min(geometry.size.width, geometry.size.height) * (isCompact ? 0.5 : 0.42)
    }

    public var body: some View {
        GeometryReader { geometry in
            if let uiImage = loadedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: DipleRadius.s))
            } else {
                // A placeholder is cover art, not metadata. The full title and author already
                // sit directly below a library cover; repeating them here creates a visual echo.
                // What it does need is to be *distinguishable*, which a shared surface colour
                // never was — see `DipleCoverArt`.
                ZStack {
                    DipleCoverArt.gradient(for: title)

                    Text(DipleCoverArt.initial(for: title))
                        .font(.system(size: initialSize(for: geometry), weight: .semibold))
                        .foregroundStyle(DipleCoverArt.ink(for: title))
                        // The letter is a mark, not a word: it holds its size against Dynamic
                        // Type instead of outgrowing the cover it is printed on.
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    if !isCompact {
                        VStack {
                            HStack {
                                DipleMark(size: 16)
                                    .foregroundStyle(DipleCoverArt.ink(for: title))
                                    .opacity(0.5)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(DipleSpace.m)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [DipleColor.insetHighlight, DipleColor.hairline],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: DipleStroke.hairline
                        )
                )
            }
        }
        .aspectRatio(1 / 1.5, contentMode: .fit)
    }
}

/// Covers are read inside `body`, which SwiftUI re-evaluates constantly while the library
/// grid scrolls. Decoding a JPEG from disk on every pass makes the grid stutter, so results
/// are kept in memory and dropped under pressure.
final class CoverImageCache: @unchecked Sendable {
    static let shared = CoverImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 120
    }

    func image(atRelativePath relativePath: String) -> UIImage? {
        let key = relativePath as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let url = BookStorageService.shared.absoluteURL(for: relativePath)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Called when a cover is replaced so the grid stops showing the previous artwork.
    func invalidate(relativePath: String) {
        cache.removeObject(forKey: relativePath as NSString)
    }
}

import SwiftUI

/// Shifts a cover slightly against the card it sits in as the grid scrolls.
///
/// A grid of covers scrolls as one flat sheet. Letting the art travel a few points slower than
/// its frame gives the shelf a front and a back, which is most of what makes a scroll feel
/// physical rather than like a list being redrawn. The offset is deliberately tiny — it should
/// register as depth, not as artwork sliding around inside a window.
///
/// Driven by `visualEffect`, so the position is read during rendering rather than published
/// into SwiftUI state: a `GeometryReader` writing a scroll offset would invalidate every cell
/// on every frame of the scroll, which is exactly the cost this effect is not worth.
private struct CoverParallax: ViewModifier {
    /// Points of travel between the top of the viewport and the bottom.
    let travel: CGFloat

    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            let viewport = proxy.bounds(of: .scrollView)?.height ?? 0
            // Outside a scroll view there is no scroll to parallax against — the reader's own
            // cover, for one — and the effect simply does not apply.
            guard viewport > 0 else { return view.offset(y: 0) }
            // −1 at the top of the viewport, +1 at the bottom. Clamped so a cell scrolled far
            // past either edge stops travelling instead of drifting without limit.
            let position = (proxy.frame(in: .scrollView).midY / viewport) * 2 - 1
            return view.offset(y: Swift.min(Swift.max(position, -1), 1) * travel)
        }
    }
}

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
            art(in: geometry)
                // Overscan first, so the art has somewhere to travel to and the parallax never
                // pulls an empty edge into view. The clip and the border sit outside the
                // effect: the card's own outline must not move, or the whole grid appears to
                // wobble instead of the art appearing to sit deeper than it.
                .scaleEffect(isCompact ? 1 : 1.06)
                .modifier(CoverParallax(travel: isCompact ? 0 : 6))
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
        .aspectRatio(1 / 1.5, contentMode: .fit)
    }

    @ViewBuilder
    private func art(in geometry: GeometryProxy) -> some View {
        GeometryReader { _ in
            if let uiImage = loadedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
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
            }
        }
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

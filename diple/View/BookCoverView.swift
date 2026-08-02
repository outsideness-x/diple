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
                ZStack {
                    LinearGradient(
                        colors: [DipleColor.surfaceRaised, DipleColor.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    AccentWash(diameter: min(geometry.size.width, geometry.size.height))
                        .offset(x: geometry.size.width * 0.2, y: -geometry.size.height * 0.2)

                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        DipleMark(size: isCompact ? 18 : 28)
                            .frame(
                                maxWidth: isCompact ? .infinity : nil,
                                maxHeight: isCompact ? .infinity : nil
                            )

                        if !isCompact {
                            Spacer()

                            Text(String(title.prefix(1)).uppercased())
                                .dipleType(.readingTitle)
                                .foregroundStyle(DipleColor.textSecondary)
                        }
                    }
                    .padding(isCompact ? 0 : DipleSpace.m)
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

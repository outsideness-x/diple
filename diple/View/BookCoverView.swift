import SwiftUI

public struct BookCoverView: View {
    public let coverPath: String?
    public let title: String
    public let author: String?

    public init(coverPath: String?, title: String, author: String?) {
        self.coverPath = coverPath
        self.title = title
        self.author = author
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
                    .cornerRadius(6)
            } else {
                // High quality minimalist placeholder
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.07, green: 0.07, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))

                        Spacer()

                        Text(title)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundColor(Color(red: 0.9, green: 0.9, blue: 0.92))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        if let author = author, !author.isEmpty {
                            Text(author)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.6))
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                }
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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

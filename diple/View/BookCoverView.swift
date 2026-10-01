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

    /// A book's corner, not an app tile's.
    ///
    /// Covers used `DipleRadius.s` — 8 pt at every size, which on a 44 pt thumbnail is 18% of
    /// its width: the shelf read as a row of app icons. A book's corner is almost square, so the
    /// radius is a small fraction of the width, held between 1.5 pt (enough that the edge does
    /// not alias) and 3 pt (where a grid cover's corner stops looking cut and starts looking
    /// rounded).
    static func cornerRadius(forWidth width: CGFloat) -> CGFloat {
        min(max(width * 0.022, 1.5), 3)
    }

    public var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(
                cornerRadius: Self.cornerRadius(forWidth: geometry.size.width),
                style: .continuous
            )
            art(in: geometry)
                // Overscan first, so the art has somewhere to travel to and the parallax never
                // pulls an empty edge into view. The clip and the border sit outside the
                // effect: the card's own outline must not move, or the whole grid appears to
                // wobble instead of the art appearing to sit deeper than it.
                .scaleEffect(isCompact ? 1 : 1.06)
                .modifier(CoverParallax(travel: isCompact ? 0 : 6))
                // The hinge sits on the board, not on the picture, so it does not travel.
                .overlay { CoverSpine() }
                .clipShape(shape)
                .overlay(
                    shape.strokeBorder(
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

/// The hinge of a cover: where the board folds round the spine.
///
/// A dark line at the very edge, the light the fold catches just inside it, and a soft shadow
/// where the board flattens out again. It is what turns a rectangle of artwork into the front
/// of a book — the one cue a printed object has that a picture does not — and it is drawn in
/// proportion to the width, because a hinge is a part of the book, not a fixed number of points.
/// White and black over the art rather than ramp colours: it is light falling on a physical
/// object, the same in either appearance.
private struct CoverSpine: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.30), location: 0),
                .init(color: .black.opacity(0.10), location: 0.025),
                .init(color: .white.opacity(0.18), location: 0.045),
                .init(color: .white.opacity(0), location: 0.08),
                .init(color: .black.opacity(0.07), location: 0.095),
                .init(color: .black.opacity(0), location: 0.15)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The colour a book lends to the page it heads — the lead on the front page, its own overview.
///
/// Measured from the cover once and kept: the upper two thirds, where the artwork is, rather
/// than the whole board, whose lower band is usually the publisher's title plate. Only hue and
/// saturation are kept; lightness is the page's to set (see `CoverWash`), so a near-black cover
/// still lends its colour without darkening the page, and a grey one lends nothing at all.
/// A book without a cover lends the hue its generated artwork is drawn in (`DipleCoverArt`).
enum CoverTone {
    struct Tone: Equatable {
        let hue: CGFloat
        let saturation: CGFloat
    }

    private final class Box {
        let tone: Tone?
        init(_ tone: Tone?) { self.tone = tone }
    }

    private static let cache = NSCache<NSString, Box>()

    static func tone(coverPath: String?, title: String) -> Tone? {
        let key = (coverPath ?? "title:" + title) as NSString
        if let box = cache.object(forKey: key) { return box.tone }
        let tone = measure(coverPath: coverPath, title: title)
        cache.setObject(Box(tone), forKey: key)
        return tone
    }

    private static func measure(coverPath: String?, title: String) -> Tone? {
        guard let coverPath,
              let image = CoverImageCache.shared.image(atRelativePath: coverPath)?.cgImage
        else {
            return Tone(hue: DipleCoverArt.hue(for: title), saturation: 0.34)
        }

        // An 8 × 8 average of the artwork: Core Graphics does the averaging as it scales.
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            let artwork = CGRect(
                x: 0, y: 0,
                width: image.width, height: max(1, image.height * 2 / 3)
            )
            guard let top = image.cropping(to: artwork) else { return false }
            context.draw(top, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var red = 0.0, green = 0.0, blue = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Double(pixels[index])
            green += Double(pixels[index + 1])
            blue += Double(pixels[index + 2])
        }
        let count = Double(side * side) * 255
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: red / count, green: green / count, blue: blue / count, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // A grey cover has no colour to lend, and a grey wash over warm paper reads as dirt.
        guard saturation > 0.08 else { return nil }
        return Tone(hue: hue, saturation: saturation)
    }
}

/// A book's colour laid over the top of the page it heads, fading out before the content below.
///
/// The page's lightness, the book's hue: pale and barely tinted on paper, deep and dark at
/// night, with the saturation capped so the cover lends a cast rather than paint. It sits behind
/// the content and in front of the canvas, and it does not scroll — the light of the book being
/// read, not a printed band.
struct CoverWash: View {
    let tone: CoverTone.Tone?
    /// How far down the screen the wash reaches before it is gone, as a fraction of the height.
    var reach: CGFloat = 0.55

    var body: some View {
        if let tone {
            GeometryReader { geometry in
                LinearGradient(
                    colors: [Self.color(for: tone), Self.color(for: tone).opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geometry.size.height * reach)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    private static func color(for tone: CoverTone.Tone) -> Color {
        DipleColor.adaptive(
            // A cast, not a colour: at a third of the cover's saturation a red cover turned the
            // whole head of the page salmon. A sixth reads as warm paper with that cover's light.
            light: UIColor(hue: tone.hue, saturation: min(tone.saturation, 0.5) * 0.17, brightness: 0.96, alpha: 1),
            dark: UIColor(hue: tone.hue, saturation: min(tone.saturation, 0.6) * 0.7, brightness: 0.22, alpha: 1)
        )
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

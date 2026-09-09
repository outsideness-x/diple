import SwiftUI
import UIKit

/// A figure, opened off the page.
///
/// It keeps the page's own ground rather than the black slab a photo viewer would use: a
/// diagram drawn as black ink on white is unreadable floated on black, and the reader chose
/// Paper, Sepia, Carbon or Ink for exactly the surface they want to look at ink on.
struct ReaderFigureView: View {
    let figure: ReaderFigure
    let chrome: ReaderChrome
    let onClose: () -> Void

    var body: some View {
        ZStack {
            chrome.page
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZoomableImage(image: figure.image, onSingleTap: onClose)

                if let caption = figure.caption, !caption.isEmpty {
                    Text(caption)
                        .dipleType(.caption)
                        .foregroundStyle(chrome.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, DipleSpace.xxl)
                        .padding(.top, DipleSpace.m)
                        .accessibilityHidden(true)
                }
            }
            .padding(.bottom, DipleSpace.xl)
        }
        .overlay(alignment: .topTrailing) {
            // The one control on the screen, and it needs to exist: a page of black ink filling
            // the display has nothing on it that says how to leave, and the tap that closes it
            // is also the tap that zooms.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .dipleIcon(15, weight: .semibold)
                    .foregroundStyle(chrome.control)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(chrome.tint)
                            .background(.regularMaterial, in: Circle())
                            .environment(\.colorScheme, chrome.colorScheme)
                    }
                    .overlay {
                        Circle().stroke(chrome.separator, lineWidth: DipleStroke.hairline)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.readerControl)
            .padding(DipleSpace.l)
            .accessibilityLabel("Close figure")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(figure.caption ?? "Figure"))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: Text("Close figure"), onClose)
    }
}

/// Pinch, pan and double-tap, done by `UIScrollView` because it already does all three
/// correctly — including the parts that are easy to forget: the pan bounds that follow the zoom
/// scale, the rubber band at the edges, and keeping the image centred while it is smaller than
/// the screen. A SwiftUI `MagnifyGesture` reproduces the first of those and none of the rest.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> FigureScrollView {
        let scrollView = FigureScrollView()
        scrollView.delegate = context.coordinator
        scrollView.imageView.image = image
        context.coordinator.install(on: scrollView)
        return scrollView
    }

    func updateUIView(_ scrollView: FigureScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if scrollView.imageView.image !== image {
            scrollView.imageView.image = image
            scrollView.refit()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        /// Four times the fitted size. The figure is opened because it was too small on the
        /// page, and the ceiling is what stops a small diagram from being pulled into a blur.
        static let maximumZoomScale: CGFloat = 4

        var onSingleTap: () -> Void

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        func install(on scrollView: FigureScrollView) {
            scrollView.maximumZoomScale = Self.maximumZoomScale

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)

            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
            // Without this the single tap fires on the first of a double tap, and closing the
            // figure would be the answer to asking it to zoom.
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? FigureScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? FigureScrollView)?.centreContent()
        }

        @objc private func handleSingleTap() {
            onSingleTap()
        }

        /// Zooms to the point that was tapped rather than to the middle: on a diagram, the part
        /// worth enlarging is the part under the finger.
        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? FigureScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let target = Self.maximumZoomScale / 2
            let point = recognizer.location(in: scrollView.imageView)
            let size = CGSize(
                width: scrollView.bounds.width / target,
                height: scrollView.bounds.height / target
            )
            scrollView.zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                animated: true
            )
        }
    }
}

/// The fitting has to happen in `layoutSubviews`, and that is the whole reason this subclass
/// exists: `updateUIView` runs when SwiftUI has new *values*, not when UIKit has new *bounds*,
/// so a scroll view sized after the first update — which is every scroll view — kept the
/// content size it was given at zero width and opened the figure already zoomed into its own
/// top-left corner. Measured on the simulator, where a 1024-point mark filled the screen with
/// a quarter of itself.
final class FigureScrollView: UIScrollView {
    let imageView = UIImageView()

    private var fittedBounds: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        minimumZoomScale = 1
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != fittedBounds else { return }
        refit()
    }

    /// Fits the image to the view and starts again at 1×. The scroll view's content is exactly
    /// the fitted rectangle, so the pan bounds are right at every zoom without any arithmetic.
    func refit() {
        guard bounds.width > 0, bounds.height > 0, let image = imageView.image else { return }
        fittedBounds = bounds.size

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        centreContent()
    }

    /// An image smaller than the view sits in the middle of it, not in a corner. The inset is
    /// the remaining room halved, recomputed on every zoom step.
    func centreContent() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(
            top: vertical,
            left: horizontal,
            bottom: vertical,
            right: horizontal
        )
    }
}

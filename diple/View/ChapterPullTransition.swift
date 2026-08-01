import UIKit
import WebKit
import ReadiumShared
import ReadiumNavigator

/// Drives chapter changes in continuous scroll mode.
///
/// Readium renders each EPUB resource in its own web view inside a horizontally paged
/// `PaginationView`. In scroll mode that means reaching the end of a chapter is a dead end:
/// the content simply stops and the only way forward is a horizontal swipe, which has nothing
/// to do with the vertical reading gesture.
///
/// This controller restores the expected behaviour: keep scrolling past the end of a chapter,
/// pull a little further, release — and the next chapter opens with haptic feedback. A pill
/// with a progress ring tracks the pull so the gesture is discoverable.
///
/// Two Readium details make this necessary rather than optional:
/// - `EPUBReflowableSpreadView.setupWebView()` disables bouncing, so the scroll view cannot
///   overscroll at all until we turn it back on.
/// - Spread views are recycled as the reader moves through the book, so the attachment has to
///   be refreshed whenever the navigator loads new spreads.
@MainActor
final class ChapterPullTransitionController {
    /// Visual overscroll, in points, required to arm the transition. Because UIScrollView
    /// rubber-bands, this corresponds to roughly twice as much finger travel — which is
    /// exactly the "longer pull" that separates it from ordinary scrolling.
    private static let activationDistance: CGFloat = 78
    /// Below this fraction the gesture disarms again, so a pull hovering at the threshold
    /// does not tick repeatedly.
    private static let disarmFraction: CGFloat = 0.82

    private enum Direction {
        case forward
        case backward
    }

    private weak var navigator: EPUBNavigatorViewController?
    private let indicator = ChapterPullIndicatorView()
    private let attachedScrollViews = NSHashTable<UIScrollView>.weakObjects()

    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

    private var direction: Direction?
    private var isArmed = false
    private var isTransitioning = false
    private var isIndicatorVisible = false

    /// Resolves the title shown on the pill, e.g. "Next: Chapter IV".
    var chapterTitleProvider: ((AnyURL) -> String?)?

    private(set) var isEnabled = false

    init(navigator: EPUBNavigatorViewController) {
        self.navigator = navigator
    }

    // MARK: - Lifecycle

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            installIndicatorIfNeeded()
            refreshAttachments()
        } else {
            detachAll()
            indicator.removeFromSuperview()
            topConstraint = nil
            bottomConstraint = nil
        }
    }

    /// Attaches to any spread web view that appeared since the last call. Cheap enough to be
    /// called on every location change and SwiftUI update.
    func refreshAttachments() {
        guard isEnabled, let navigator else { return }
        installIndicatorIfNeeded()

        for webView in Self.webViews(in: navigator.view) {
            let scrollView = webView.scrollView
            guard !attachedScrollViews.contains(scrollView) else { continue }
            attachedScrollViews.add(scrollView)

            // Readium turns bouncing off; without it there is nothing to pull against.
            scrollView.bounces = true
            scrollView.alwaysBounceVertical = true
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        }
    }

    private func detachAll() {
        for scrollView in attachedScrollViews.allObjects {
            scrollView.bounces = false
            scrollView.alwaysBounceVertical = false
            scrollView.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
        }
        attachedScrollViews.removeAllObjects()
        resetGestureState()
    }

    // MARK: - Gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEnabled, let scrollView = gesture.view as? UIScrollView else { return }

        switch gesture.state {
        case .began:
            resetGestureState()
        case .changed:
            update(with: scrollView)
        case .ended:
            commit()
        case .cancelled, .failed:
            resetGestureState()
            hideIndicator()
        default:
            break
        }
    }

    private func update(with scrollView: UIScrollView) {
        guard !isTransitioning, let (direction, distance) = overscroll(in: scrollView) else {
            self.direction = nil
            isArmed = false
            hideIndicator()
            return
        }

        guard canMove(direction) else {
            hideIndicator()
            return
        }

        if self.direction != direction {
            self.direction = direction
            setIndicatorEdge(isBottom: direction == .forward)
            indicator.configure(
                isForward: direction == .forward,
                title: targetChapterTitle(for: direction)
            )
        }

        let fraction = min(distance / Self.activationDistance, 1)
        isIndicatorVisible = true
        indicator.update(fraction: fraction, offset: min(distance, Self.activationDistance) * 0.45)

        if fraction >= 1, !isArmed {
            isArmed = true
            HapticManager.shared.impact(.light)
        } else if fraction < Self.disarmFraction, isArmed {
            isArmed = false
        }
    }

    private func commit() {
        guard isArmed, let direction, !isTransitioning, let navigator else {
            resetGestureState()
            hideIndicator()
            return
        }

        isTransitioning = true
        hideIndicator()
        HapticManager.shared.chapterChanged()

        Task { @MainActor [weak self] in
            let options = NavigatorGoOptions(animated: true)
            switch direction {
            case .forward:
                _ = await navigator.goForward(options: options)
            case .backward:
                _ = await navigator.goBackward(options: options)
            }
            self?.isTransitioning = false
            self?.resetGestureState()
            self?.refreshAttachments()
        }
    }

    private func resetGestureState() {
        direction = nil
        isArmed = false
    }

    private func hideIndicator() {
        guard isIndicatorVisible else { return }
        isIndicatorVisible = false
        indicator.hide()
    }

    /// The direction and distance the reader has dragged beyond the chapter's content,
    /// or `nil` while still inside it.
    private func overscroll(in scrollView: UIScrollView) -> (Direction, CGFloat)? {
        let insets = scrollView.adjustedContentInset
        let minY = -insets.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        let offsetY = scrollView.contentOffset.y

        if offsetY > maxY {
            return (.forward, offsetY - maxY)
        }
        if offsetY < minY {
            return (.backward, minY - offsetY)
        }
        return nil
    }

    private func canMove(_ direction: Direction) -> Bool {
        guard
            let navigator,
            let href = navigator.currentLocation?.href,
            let index = navigator.publication.readingOrder.firstIndexWithHREF(href)
        else {
            return true
        }

        switch direction {
        case .forward:
            return index < navigator.publication.readingOrder.count - 1
        case .backward:
            return index > 0
        }
    }

    private func targetChapterTitle(for direction: Direction) -> String? {
        guard
            let navigator,
            let href = navigator.currentLocation?.href,
            let index = navigator.publication.readingOrder.firstIndexWithHREF(href)
        else {
            return nil
        }

        let targetIndex = (direction == .forward) ? index + 1 : index - 1
        guard navigator.publication.readingOrder.indices.contains(targetIndex) else { return nil }

        let link = navigator.publication.readingOrder[targetIndex]
        if let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return chapterTitleProvider?(link.url().removingQuery().removingFragment())
    }

    // MARK: - Indicator placement

    private func installIndicatorIfNeeded() {
        guard let container = navigator?.view, indicator.superview !== container else { return }

        indicator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(indicator)

        let guide = container.safeAreaLayoutGuide
        topConstraint = indicator.topAnchor.constraint(equalTo: guide.topAnchor, constant: 20)
        bottomConstraint = indicator.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -20)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            indicator.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            indicator.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
        ])
        setIndicatorEdge(isBottom: true)
        isIndicatorVisible = false
        indicator.hide(animated: false)
    }

    private func setIndicatorEdge(isBottom: Bool) {
        topConstraint?.isActive = !isBottom
        bottomConstraint?.isActive = isBottom
        indicator.isAnchoredToBottom = isBottom
    }

    private static func webViews(in view: UIView) -> [WKWebView] {
        if let webView = view as? WKWebView {
            return [webView]
        }
        return view.subviews.flatMap { webViews(in: $0) }
    }
}

/// The pill shown while pulling past the end of a chapter: a ring that fills with the pull,
/// a direction chevron and the title of the chapter about to open. Once the ring completes
/// the pill fills with the accent colour to signal that releasing will commit.
private final class ChapterPullIndicatorView: UIView {
    var isAnchoredToBottom = true

    private let ringHost = UIView()
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let chevron = UIImageView()
    private let label = UILabel()

    private let idleBackground = UIColor(white: 0.07, alpha: 0.94)
    private var isArmedAppearance = false

    init() {
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        backgroundColor = idleBackground
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        ringHost.translatesAutoresizingMaskIntoConstraints = false
        for shape in [trackLayer, progressLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 2
            shape.lineCap = .round
            ringHost.layer.addSublayer(shape)
        }
        trackLayer.strokeColor = UIColor(white: 1, alpha: 0.2).cgColor
        progressLayer.strokeColor = UIColor.dipleAccent.cgColor
        progressLayer.strokeEnd = 0

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.contentMode = .scaleAspectFit
        chevron.tintColor = .white
        ringHost.addSubview(chevron)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(ringHost)
        addSubview(label)

        NSLayoutConstraint.activate([
            ringHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            ringHost.centerYAnchor.constraint(equalTo: centerYAnchor),
            ringHost.widthAnchor.constraint(equalToConstant: 20),
            ringHost.heightAnchor.constraint(equalTo: ringHost.widthAnchor),

            chevron.centerXAnchor.constraint(equalTo: ringHost.centerXAnchor),
            chevron.centerYAnchor.constraint(equalTo: ringHost.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 9),
            chevron.heightAnchor.constraint(equalToConstant: 9),

            label.leadingAnchor.constraint(equalTo: ringHost.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2

        let box = ringHost.bounds
        let path = UIBezierPath(
            arcCenter: CGPoint(x: box.midX, y: box.midY),
            radius: max(0, (min(box.width, box.height) - 2) / 2),
            startAngle: -.pi / 2,
            endAngle: 1.5 * .pi,
            clockwise: true
        ).cgPath

        for shape in [trackLayer, progressLayer] {
            shape.frame = box
            shape.path = path
        }
    }

    func configure(isForward: Bool, title: String?) {
        let symbol = isForward ? "chevron.up" : "chevron.down"
        chevron.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        )

        if let title, !title.isEmpty {
            label.text = (isForward ? "Next: " : "Previous: ") + title
        } else {
            label.text = isForward ? "Next chapter" : "Previous chapter"
        }
    }

    func update(fraction: CGFloat, offset: CGFloat) {
        // Implicit CALayer animations lag a whole frame behind the finger.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = fraction
        CATransaction.commit()

        alpha = min(fraction * 1.8, 1)
        let scale = 0.88 + 0.12 * fraction
        let translation = isAnchoredToBottom ? -offset : offset
        transform = CGAffineTransform(translationX: 0, y: translation).scaledBy(x: scale, y: scale)

        setArmedAppearance(fraction >= 1)
    }

    func hide(animated: Bool = true) {
        let collapse = {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }
        guard animated else {
            collapse()
            setArmedAppearance(false)
            return
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState], animations: collapse)
        setArmedAppearance(false)
    }

    private func setArmedAppearance(_ armed: Bool) {
        guard armed != isArmedAppearance else { return }
        isArmedAppearance = armed

        UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState]) {
            self.backgroundColor = armed ? .dipleAccent : self.idleBackground
            self.label.textColor = armed ? .black : .white
            self.chevron.tintColor = armed ? .black : .white
        }
        trackLayer.strokeColor = armed
            ? UIColor.clear.cgColor
            : UIColor(white: 1, alpha: 0.2).cgColor
        progressLayer.strokeColor = armed ? UIColor.black.cgColor : UIColor.dipleAccent.cgColor
    }
}

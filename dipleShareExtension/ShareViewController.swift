import SwiftUI
import UniformTypeIdentifiers
import Combine

final class ShareViewController: UIViewController {
    private var model: ShareExtensionModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let extensionContext else { return }
        let model = ShareExtensionModel(context: extensionContext)
        self.model = model

        let host = UIHostingController(rootView: ShareExtensionView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        model.begin()
    }
}

@MainActor
private final class ShareExtensionModel: ObservableObject {
    enum State: Equatable {
        case reading
        case saving(host: String)
        case saved(host: String)
        case failed(message: String)
    }

    @Published private(set) var state: State = .reading
    private let context: NSExtensionContext

    init(context: NSExtensionContext) {
        self.context = context
    }

    func begin() {
        Task {
            do {
                let url = try await sharedURL()
                let host = url.host(percentEncoded: false) ?? url.host ?? "article"
                state = .saving(host: host)
                _ = try SharedLinkInbox.live().enqueue(url)
                withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
                    state = .saved(host: host)
                }
            } catch {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    state = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    func finish() {
        context.completeRequest(returningItems: nil)
    }

    private func sharedURL() async throws -> URL {
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
            if let url = item as? URL, let normalized = SharedLinkInbox.normalized(url) {
                return normalized
            }
            if let url = item as? NSURL,
               let normalized = SharedLinkInbox.normalized(url as URL) {
                return normalized
            }
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
            guard let text = item as? String else { continue }
            for token in text.split(whereSeparator: { $0.isWhitespace }) {
                guard let url = URL(string: String(token)),
                      let normalized = SharedLinkInbox.normalized(url)
                else { continue }
                return normalized
            }
        }

        throw SharedLinkInbox.InboxError.unsupportedURL
    }
}

private struct ShareExtensionView: View {
    @ObservedObject var model: ShareExtensionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SharePalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(SharePalette.hairline)
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)

                Spacer(minLength: 28)

                mark

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .foregroundStyle(SharePalette.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(detail)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(SharePalette.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(.top, 24)
                .contentTransition(.opacity)

                Spacer(minLength: 28)

                actions
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.84), value: model.state)
    }

    private var mark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(SharePalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(SharePalette.hairline, lineWidth: 1)
                }

            VStack(spacing: 0) {
                Text("d")
                    .font(.system(size: 76, weight: .regular, design: .serif))
                    .foregroundStyle(SharePalette.textPrimary)
                    .tracking(-3)
                    .accessibilityHidden(true)

                Capsule()
                    .fill(SharePalette.accent)
                    .frame(maxWidth: 46)
                    .frame(height: 3)
                    .offset(y: -10)
            }

            if case .saved = model.state {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SharePalette.canvas)
                    .frame(width: 30, height: 30)
                    .background(SharePalette.accent, in: Circle())
                    .overlay { Circle().stroke(SharePalette.canvas, lineWidth: 4) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: 148)
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var actions: some View {
        switch model.state {
        case .reading, .saving:
            HStack(spacing: 12) {
                ProgressView().tint(SharePalette.accent)
                Text("Saving to your inbox…")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(SharePalette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(SharePalette.surface, in: Capsule())

        case .saved:
            Button(action: model.finish) {
                Label("Done", systemImage: "checkmark")
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(SharePalette.canvas)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(SharePalette.accent, in: Capsule())
            }

        case .failed:
            VStack(spacing: 10) {
                Button("Try Again", action: model.begin)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(SharePalette.canvas)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(SharePalette.accent, in: Capsule())

                Button("Cancel", action: model.finish)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(SharePalette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private var title: String {
        switch model.state {
        case .reading: return "Finding the article"
        case .saving: return "Keeping it for later"
        case .saved: return "Saved to diple"
        case .failed: return "Couldn’t save this link"
        }
    }

    private var detail: String {
        switch model.state {
        case .reading:
            return "Reading the shared item…"
        case .saving(let host):
            return host
        case .saved(let host):
            return "\(host) is waiting in your inbox. diple will finish preparing it when the app opens."
        case .failed(let message):
            return message
        }
    }
}

private enum SharePalette {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
            : UIColor(red: 0.957, green: 0.957, blue: 0.969, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.102, green: 0.102, blue: 0.129, alpha: 1)
            : UIColor.white
    })
    static let accent = Color(red: 0.784, green: 0.643, blue: 0.361)
    static let textPrimary = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 1 : 0.05, alpha: 0.93)
    })
    static let textSecondary = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 1 : 0.05, alpha: 0.70)
    })
    static let textTertiary = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 1 : 0.05, alpha: 0.52)
    })
    static let hairline = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 1 : 0.05, alpha: 0.12)
    })
}

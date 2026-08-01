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
        let url = BookStorageService.shared.absoluteURL(for: coverPath)
        return UIImage(contentsOfFile: url.path)
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

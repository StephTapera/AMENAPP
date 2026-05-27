import SwiftUI
import UIKit

// MARK: - PUBLIC INTERFACE

/// A static SwiftUI view that renders a single share card.
/// Caller is responsible for providing a pre-resolved `authorAvatar` (UIImage).
/// `AsyncImage` cannot be used inside `ImageRenderer` reliably.
struct ShareCard: View {
    let post: Post
    let size: ShareCardSize
    let pullQuote: String?
    let verseRef: String?
    let authorAvatar: UIImage?

    init(
        post: Post,
        size: ShareCardSize,
        pullQuote: String? = nil,
        verseRef: String? = nil,
        authorAvatar: UIImage? = nil
    ) {
        self.post = post
        self.size = size
        self.pullQuote = pullQuote
        self.verseRef = verseRef
        self.authorAvatar = authorAvatar
    }

    // MARK: - Derived content

    private var displayQuote: String {
        let raw = pullQuote?.isEmpty == false ? pullQuote! : post.content
        guard raw.count > size.maxPullQuoteChars else { return raw }
        let truncated = raw.prefix(size.maxPullQuoteChars)
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "\u{2026}"
        }
        return String(truncated) + "\u{2026}"
    }

    private var displayVerseRef: String? {
        let ref = verseRef?.isEmpty == false ? verseRef : post.verseReference
        return ref?.isEmpty == false ? ref : nil
    }

    private var initials: String {
        let raw = post.authorInitials
        return raw.isEmpty ? "A" : raw
    }

    // MARK: - View

    var body: some View {
        ZStack {
            ShareCardColors.amenBlack.ignoresSafeArea()
            ShareCardColors.radialBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                authorRow
                    .padding(.bottom, 44)

                pullQuoteText
                    .padding(.bottom, 32)

                if let verse = displayVerseRef {
                    Text(verse)
                        .font(.system(size: size.verseRefFontSize, weight: .medium))
                        .foregroundStyle(ShareCardColors.amenGold)
                        .padding(.bottom, 64)
                }

                Spacer(minLength: 0)

                watermark
            }
            .padding(size.padding)
        }
        .frame(width: size.pixelSize.width, height: size.pixelSize.height)
    }

    // MARK: - Subviews

    private var authorRow: some View {
        HStack(spacing: 16) {
            if let avatar = authorAvatar {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(ShareCardColors.amenGold.opacity(0.25))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(initials)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(ShareCardColors.amenGold)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(post.authorName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let username = post.authorUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private var pullQuoteText: some View {
        Text(displayQuote)
            .font(.system(size: size.pullQuoteFontSize, weight: .black))
            .lineLimit(size.maxLines)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var watermark: some View {
        HStack {
            Spacer()
            Text("AMEN")
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(.white.opacity(0.60))
                .tracking(10)
        }
    }
}

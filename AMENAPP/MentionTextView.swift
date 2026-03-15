import SwiftUI

// MARK: - MentionHighlightModifier

/// Applies an animated yellow-highlighter sweep effect over the @mention runs
/// in a `Text` view by overlaying a Canvas that draws highlighted regions.
///
/// Strategy: set `AttributedString.backgroundColor` on mention ranges so
/// SwiftUI Text renders a tinted background on those characters. Then animate
/// the reveal by sweeping a mask from left to right using a custom `GeometryEffect`.
///
/// We do NOT use UILabel / NSLayoutManager to keep this pure SwiftUI.

// MARK: - Highlight Sweep Mask Modifier

/// Animates a left-to-right reveal clip on the view it is applied to.
private struct SweepRevealModifier: ViewModifier {
    let progress: CGFloat // 0 = fully hidden, 1 = fully revealed

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .frame(width: geo.size.width * max(0, min(1, progress)))
                        Spacer(minLength: 0)
                    }
                }
            )
    }
}

// MARK: - MentionTextView

/// Renders text with:
/// - Tappable @mentions (purple, bold) via AttributedString link — works across
///   all post categories (OpenTable, Testimonies, Prayer, Tips, Church Notes, etc.)
/// - Animated yellow highlighter marker sweep on each mention on appear, like
///   drawing over text with a STAEDTLER marker pen.
struct MentionTextView: View {
    let text: String
    let mentions: [MentionedUser]?
    let font: Font
    let fontSize: CGFloat   // used to size the bold mention font correctly
    let lineSpacing: CGFloat
    let onMentionTap: (MentionedUser) -> Void

    @State private var highlightProgress: CGFloat = 0

    init(
        text: String,
        mentions: [MentionedUser]? = nil,
        font: Font = .body,
        fontSize: CGFloat = 16,
        lineSpacing: CGFloat = 4,
        onMentionTap: @escaping (MentionedUser) -> Void = { _ in }
    ) {
        self.text = text
        self.mentions = mentions
        self.font = font
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.onMentionTap = onMentionTap
    }

    /// Convenience init that auto-extracts @mentions from text.
    /// Use this for comments/replies where a resolved mentions array is not stored.
    init(
        text: String,
        autoDetectMentions: Bool,
        font: Font = .body,
        fontSize: CGFloat = 14,
        lineSpacing: CGFloat = 4,
        onMentionTap: @escaping (MentionedUser) -> Void = { _ in }
    ) {
        self.text = text
        self.font = font
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.onMentionTap = onMentionTap
        if autoDetectMentions {
            let regex = try? NSRegularExpression(pattern: "@(\\w+)")
            let ns = text as NSString
            let matches = regex?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
            self.mentions = matches.map { match in
                let username = ns.substring(with: match.range(at: 1))
                return MentionedUser(userId: "", username: username, displayName: username)
            }
        } else {
            self.mentions = nil
        }
    }

    var body: some View {
        if let mentions = mentions, !mentions.isEmpty {
            ZStack(alignment: .topLeading) {
                // Layer 1: Highlight background (yellow, sweeps in)
                Text(highlightAttributedText(mentions: mentions))
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .modifier(SweepRevealModifier(progress: highlightProgress))
                    .allowsHitTesting(false)

                // Layer 2: Full text with tappable links on top
                Text(linkAttributedText(mentions: mentions))
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .environment(\.openURL, OpenURLAction { url in
                        if let mention = mentions.first(where: {
                            "@\($0.username)" == url.absoluteString
                        }) {
                            onMentionTap(mention)
                            return .handled
                        }
                        return .systemAction
                    })
            }
            // Fix: ZStack does not inherit proposed width — Text layers inside won't
            // wrap unless we explicitly constrain the ZStack to fill available width.
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                highlightProgress = 0
                withAnimation(.easeOut(duration: 0.55).delay(0.2)) {
                    highlightProgress = 1
                }
            }
            .onChange(of: text) { _, _ in
                highlightProgress = 0
                withAnimation(.easeOut(duration: 0.55).delay(0.1)) {
                    highlightProgress = 1
                }
            }
        } else {
            Text(text)
                .font(font)
                .lineSpacing(lineSpacing)
        }
    }

    // MARK: - AttributedString for highlight layer
    // Full text rendered transparently, only mention runs get a yellow background.

    private func highlightAttributedText(mentions: [MentionedUser]) -> AttributedString {
        var result = AttributedString(text)
        // Make all text transparent — only the background color matters for this layer
        result.foregroundColor = .clear

        for mention in mentions {
            let target = "@\(mention.username)"
            var cursor = result.startIndex
            while cursor < result.endIndex {
                guard let range = result[cursor...].range(of: target) else { break }
                result[range].foregroundColor = .clear
                result[range].backgroundColor = Color(red: 1.0, green: 0.88, blue: 0.15, opacity: 0.75)
                cursor = range.upperBound
            }
        }
        return result
    }

    // MARK: - AttributedString for link layer
    // Full text with normal color + bold black on mentions + tappable link.

    private func linkAttributedText(mentions: [MentionedUser]) -> AttributedString {
        var result = AttributedString(text)

        for mention in mentions {
            let target = "@\(mention.username)"
            var cursor = result.startIndex
            while cursor < result.endIndex {
                guard let range = result[cursor...].range(of: target) else { break }
                // Bold black — stands out without the purple distraction
                result[range].foregroundColor = Color(uiColor: .label)
                result[range].font = .boldSystemFont(ofSize: fontSize)
                result[range].link = URL(string: "@\(mention.username)")
                cursor = range.upperBound
            }
        }
        return result
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("Testimonies post")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            MentionTextView(
                text: "So grateful for @john and @sarah who prayed with me through this season. Couldn't have done it without you.",
                mentions: [
                    MentionedUser(userId: "1", username: "john", displayName: "John Doe"),
                    MentionedUser(userId: "2", username: "sarah", displayName: "Sarah Smith")
                ],
                font: .custom("OpenSans-Regular", size: 16),
                lineSpacing: 6
            ) { mention in print("Tapped: @\(mention.username)") }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            Text("Prayer post")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            MentionTextView(
                text: "Praying for @alex today — may God strengthen you. 🙏",
                mentions: [MentionedUser(userId: "4", username: "alex", displayName: "Alex")],
                font: .custom("OpenSans-Regular", size: 16),
                lineSpacing: 6
            ) { _ in }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            Text("Plain post (no mentions)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            MentionTextView(
                text: "A regular post with no mentions — renders plain text.",
                font: .custom("OpenSans-Regular", size: 16),
                lineSpacing: 6
            )
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .padding(.vertical)
    }
    .background(Color(.systemGroupedBackground))
}

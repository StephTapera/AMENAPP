// BereanSourceRowView.swift
// AMENAPP
//
// Row view for a single BereanSourceEntry.
// Tappable: opens the source URL in an in-app Safari sheet when available.

import SwiftUI
import SafariServices

struct BereanSourceRowView: View {

    let source: BereanSourceEntry

    @State private var showSafari = false

    // MARK: - Body

    var body: some View {
        Button(action: { if source.url != nil { showSafari = true } }) {
            HStack(alignment: .top, spacing: 12) {
                sourceIcon
                centerContent
                Spacer(minLength: 4)
                trailingContent
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSafari) {
            if let urlString = source.url, let url = URL(string: urlString) {
                SafariSheet(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Sub-views

    private var sourceIcon: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 36, height: 36)
            Image(systemName: source.sourceType.systemIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var centerContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Title
            Text(source.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            // Author
            if let author = source.author {
                Text(author)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Excerpt
            if let excerpt = source.excerpt {
                Text(excerpt)
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .lineLimit(2)
            }

            // Conflict warning
            if !source.conflictsWithSourceIds.isEmpty {
                Label("conflicts with other sources", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
    }

    private var trailingContent: some View {
        VStack(alignment: .trailing, spacing: 4) {
            qualityBar
            BereanSourceQualityBadge(score: source.qualityScore, sourceType: source.sourceType)
        }
    }

    /// 5-segment horizontal quality bar
    private var qualityBar: some View {
        let filledCount = max(0, min(5, Int((source.qualityScore * 5).rounded())))
        let barColor: Color = source.qualityScore >= 0.8 ? .green
                            : source.qualityScore >= 0.5 ? .yellow
                            : .red
        return HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filledCount ? barColor : Color.secondary.opacity(0.2))
                    .frame(width: 8, height: 14)
            }
        }
        .accessibilityLabel("Quality \(filledCount) out of 5")
    }
}

// MARK: - SafariSheet wrapper

private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    List {
        BereanSourceRowView(source: BereanSourceEntry(
            id: "1",
            url: "https://example.com",
            title: "Does God Exist? A Philosophical Survey",
            author: "Dr. William Lane Craig",
            publishedAt: nil,
            sourceType: .expertCommentary,
            qualityScore: 0.92,
            excerpt: "The cosmological argument remains one of the strongest cases for theism in modern philosophy.",
            conflictsWithSourceIds: [],
            verifiedAt: nil
        ))
        BereanSourceRowView(source: BereanSourceEntry(
            id: "2",
            url: nil,
            title: "Romans 1:20",
            author: nil,
            publishedAt: nil,
            sourceType: .scripture,
            qualityScore: 1.0,
            excerpt: "For since the creation of the world God's invisible qualities...",
            conflictsWithSourceIds: ["1"],
            verifiedAt: Date()
        ))
    }
}

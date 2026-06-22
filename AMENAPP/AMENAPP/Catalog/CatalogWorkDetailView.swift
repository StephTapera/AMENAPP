import SwiftUI

struct CatalogWorkDetailView: View {

    let work: CatalogWork
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroSection
                    infoSection
                    topicsSection
                    linksSection
                }
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                Rectangle()
                    .fill(.secondary.opacity(0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                Image(systemName: work.type.icon)
                    .font(.systemScaled(64, weight: .ultraLight))
                    .foregroundStyle(.secondary)
            }

            LinearGradient(
                colors: [.clear, Color(UIColor.systemBackground).opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 4) {
                typeBadge
                Text(work.title)
                    .font(.systemScaled(22, weight: .bold))
                    .foregroundStyle(.primary)
                if let subtitle = work.subtitle {
                    Text(subtitle)
                        .font(.systemScaled(15))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: work.type.icon)
                .font(.systemScaled(11, weight: .medium))
            Text(work.type.displayName)
                .font(.systemScaled(12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(.secondary.opacity(0.15)))
        .foregroundStyle(.secondary)
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if work.verifiedOwnership {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.systemScaled(13))
                        .foregroundStyle(.blue)
                    Text("Verified by creator")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.blue)
                }
            }

            if let description = work.description {
                Text(description)
                    .font(.systemScaled(15))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
            }

            if let date = work.publishedAt {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                    Text("Published \(date, style: .date)")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Topics

    @ViewBuilder
    private var topicsSection: some View {
        if !work.topics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Topics")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(work.topics, id: \.self) { topic in
                            Text(topic)
                                .font(.systemScaled(13))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.secondary.opacity(0.08)))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Links

    @ViewBuilder
    private var linksSection: some View {
        if !work.links.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where to find it")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    ForEach(work.links) { link in
                        if let url = URL(string: link.url) {
                            linkRow(link: link, url: url)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func linkRow(link: WorkLink, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: linkIcon(kind: link.kind))
                    .font(.systemScaled(16, weight: .light))
                    .foregroundStyle(.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ctaLabel(kind: link.kind))
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("on \(link.platform)")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Helpers

    private var shareURL: URL {
        work.links.first.flatMap { URL(string: $0.url) } ?? URL(string: "https://amenapp.com")!
    }

    private func ctaLabel(kind: String) -> String {
        switch kind {
        case "listen":   return "Listen"
        case "read":     return "Read"
        case "watch":    return "Watch"
        case "buy":      return "Buy"
        case "register": return "Register"
        default:         return "Open"
        }
    }

    private func linkIcon(kind: String) -> String {
        switch kind {
        case "listen":   return "headphones"
        case "read":     return "book"
        case "watch":    return "play.rectangle"
        case "buy":      return "cart"
        case "register": return "calendar.badge.plus"
        default:         return "link"
        }
    }
}

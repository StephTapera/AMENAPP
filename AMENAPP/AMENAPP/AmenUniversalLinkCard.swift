import SwiftUI

enum AmenUniversalLinkCardMode {
    case feedCompact
    case expandedDetail
    case composerPreview
    case savedItem
    case bereanContext
    case selahReflection
    case churchNotesSource
}

struct AmenUniversalLinkCard: View {
    let attachment: AmenSmartAttachment
    let mode: AmenUniversalLinkCardMode
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        AmenLinkSourceBadge(provider: attachment.provider)
                        if let state = attachment.intelligenceState {
                            AmenLinkIntelligenceStatusView(state: state)
                        }
                    }
                    Text(attachment.title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(mode == .expandedDetail ? 3 : 2)
                    if let byline = attachment.creatorName ?? attachment.subtitle {
                        Text(byline)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let summary = attachment.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(mode == .expandedDetail ? 4 : 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attachment.title), \(attachment.provider.rawValue)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let artworkUrl = attachment.artworkUrl, let url = URL(string: artworkUrl) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    fallback
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            fallback
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var fallback: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "link")
                .foregroundStyle(.secondary)
        }
    }
}

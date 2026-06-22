import SwiftUI

struct AmenAttachmentProviderBadge: View {
    let provider: AmenAttachmentProvider

    private var label: String {
        switch provider {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .threads: return "Threads"
        case .tikTok: return "TikTok"
        case .x: return "X"
        case .facebook: return "Facebook"
        case .linkedIn: return "LinkedIn"
        case .applePodcasts: return "Apple Podcasts"
        case .medium: return "Medium"
        case .substack: return "Substack"
        case .rss: return "RSS"
        case .bibleGateway: return "Bible Gateway"
        case .youVersion: return "YouVersion"
        case .eventbrite: return "Eventbrite"
        case .generic: return "Web"
        }
    }

    var body: some View {
        Text(label)
            .font(.systemScaled(11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.06)))
    }
}

struct AmenSmartAttachmentSkeletonCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray6))
            .frame(height: 76)
            .overlay(ProgressView().tint(.gray))
    }
}

struct AmenAttachmentLimitedPreviewCard: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack {
                Image(systemName: "exclamationmark.shield")
                Text("Limited preview. Tap to open safely.")
                    .font(.systemScaled(13, weight: .medium))
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }
}

struct AmenSmartAttachmentCard: View {
    let attachment: AmenSmartAttachment
    let smartAction: AmenSmartAttachmentAction?
    let onTap: () -> Void

    private var primaryCTA: String {
        switch attachment.provider {
        case .appleMusic, .spotify: return "Listen"
        case .youtube: return "Watch"
        case .applePodcasts: return "Listen"
        case .instagram, .threads, .tikTok, .x, .facebook, .linkedIn, .medium, .substack, .rss, .bibleGateway, .youVersion, .eventbrite: return "Open"
        case .generic: return "Open"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(attachment.creatorName ?? attachment.subtitle ?? attachment.attributionText)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack {
                        AmenAttachmentProviderBadge(provider: attachment.provider)
                        if let smartAction {
                            Text(smartAction.rawValue)
                                .font(.systemScaled(10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Text(primaryCTA)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(attachment.provider.rawValue) \(attachment.type.rawValue), \(attachment.title)")
        .accessibilityHint("Double tap to view media options")
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkUrl = attachment.artworkUrl, let url = URL(string: artworkUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallback
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            fallback
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var fallback: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}

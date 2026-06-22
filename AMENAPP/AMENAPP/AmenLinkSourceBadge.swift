import SwiftUI

struct AmenLinkSourceBadge: View {
    let provider: AmenAttachmentProvider

    private var title: String {
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
        Text(title)
            .font(.systemScaled(11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.06)))
    }
}

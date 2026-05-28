import SwiftUI

struct AmenObjectHubHeader: View {
    let canonicalObject: AmenCanonicalObject
    let hub: AmenCommunityHub

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    private var glass: AmenObjectHubLiquidGlassStyle {
        AmenObjectHubLiquidGlassStyle(reduceTransparency: reduceTransparency, increasedContrast: accessibilityContrast == .increased)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundLayer

            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 110)

                HStack(alignment: .bottom, spacing: 16) {
                    artwork
                    VStack(alignment: .leading, spacing: 8) {
                        Text(objectEyebrow)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(glass.secondaryText)

                        Text(canonicalObject.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(glass.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)

                        if let subtitle = canonicalObject.subtitle ?? canonicalObject.creatorName {
                            Text(subtitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(glass.secondaryText)
                                .lineLimit(2)
                        }

                        HStack(spacing: 8) {
                            hubPill(text: privacyText)
                            if hub.explicitContentState == .explicit || hub.explicitContentState == .limited {
                                hubPill(text: hub.explicitContentState == .explicit ? "Explicit content" : "Preview limited")
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
                .background(glass.materialSurface)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(glass.glassBorder, lineWidth: 1))
                .overlay(glass.specularHighlight().clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous)))
                .shadow(color: glass.shadow, radius: 14, x: 0, y: 8)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 390)
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(objectEyebrow), \(canonicalObject.title), by \(canonicalObject.creatorName ?? canonicalObject.subtitle ?? "unknown creator")")
    }

    private var backgroundLayer: some View {
        ZStack {
            if let artworkUrl = canonicalObject.artworkUrl, let url = URL(string: artworkUrl), !reduceTransparency {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        fallbackAmbient
                    }
                }
                .blur(radius: 36)
                .opacity(0.34)
            } else {
                fallbackAmbient
            }

            LinearGradient(
                colors: [Color.white.opacity(0.16), Color.white.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }

    private var artwork: some View {
        Group {
            if let artworkUrl = canonicalObject.artworkUrl, let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholderArtwork
                    }
                }
            } else {
                placeholderArtwork
            }
        }
        .frame(width: 148, height: 148)
        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
            .fill(Color(.systemGray5))
            .overlay(Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.black.opacity(0.45)))
    }

    private var fallbackAmbient: some View {
        LinearGradient(
            colors: [Color(red: 0.95, green: 0.96, blue: 0.98), Color(red: 0.99, green: 0.99, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func hubPill(text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(glass.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(glass.materialSurface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(glass.glassBorder, lineWidth: 1))
    }

    private var objectEyebrow: String {
        let type = canonicalObject.objectType.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized
        if let provider = canonicalObject.primaryProvider {
            return "\(type) • \(providerName(provider))"
        }
        return type
    }

    private var privacyText: String {
        switch hub.privacyLevel {
        case .public: return "Public activity only"
        case .private: return "Private hub"
        case .followersVisible: return "Limited visibility"
        }
    }

    private var artworkCornerRadius: CGFloat {
        switch canonicalObject.objectType {
        case .video: return 22
        case .article: return 24
        case .album, .mediaTrack: return 28
        default: return 24
        }
    }

    private func providerName(_ provider: AmenAttachmentProvider) -> String {
        switch provider {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .youtube: return "YouTube"
        case .applePodcasts: return "Apple Podcasts"
        case .medium: return "Medium"
        case .substack: return "Substack"
        case .bibleGateway: return "Bible Gateway"
        case .youVersion: return "YouVersion"
        default: return "Link"
        }
    }
}

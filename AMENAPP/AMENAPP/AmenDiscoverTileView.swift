import SwiftUI

struct AmenDiscoverTileView: View {
    let item: AmenDiscoverItem
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tileFill)

                if let mediaURLStr = item.media.thumbnailURL,
                   let url = URL(string: mediaURLStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        case .failure:
                            EmptyView()
                        case .empty:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                Text(item.type.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                badgeRow
                    .padding(10)
            }
            .frame(height: item.type == .church || item.type == .selahMedia ? 210 : 160)
            .matchedGeometryEffect(id: "tile_media_\(item.id)", in: namespace)

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .lineLimit(2)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.65))
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : 0.995)
    }

    @ViewBuilder
    private var badgeRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(item.badges.prefix(2)), id: \.self) { badge in
                Text(label(for: badge))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
    }

    private var tileFill: LinearGradient {
        LinearGradient(colors: [Color.black.opacity(0.08), Color.black.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func label(for badge: AmenDiscoverBadge) -> String {
        switch badge {
        case .prayerSafe: return "Prayer-safe"
        case .aiAssisted: return "AI-assisted"
        case .local: return "Local"
        case .scriptureLinked: return "Scripture-linked"
        case .bereanReviewed: return "Berean-reviewed"
        case .testimonySafe: return "Testimony-safe"
        }
    }
}

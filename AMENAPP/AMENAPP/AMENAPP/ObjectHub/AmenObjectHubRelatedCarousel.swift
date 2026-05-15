import SwiftUI

struct AmenObjectHubRelatedCarousel: View {
    let relatedObjects: [AmenCanonicalObject]
    let onSelect: (AmenCanonicalObject) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Related Objects")
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 16)

            if relatedObjects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No related objects yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Related media will appear as this hub grows.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(relatedObjects) { object in
                            Button {
                                onSelect(object)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    AmenRelatedObjectArtwork(object: object)
                                    Text(object.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .lineLimit(2)
                                    if let subtitle = object.subtitle ?? object.creatorName {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 136, alignment: .leading)
                            }
                            .buttonStyle(AmenHubGlassButtonStyle(reduceMotion: reduceMotion))
                            .accessibilityLabel("Related object: \(object.title)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct AmenRelatedObjectArtwork: View {
    let object: AmenCanonicalObject

    var body: some View {
        Group {
            if let art = object.artworkUrl, let url = URL(string: art) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 136, height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.systemGray5))
            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
}

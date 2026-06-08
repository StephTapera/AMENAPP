import SwiftUI

struct AmenDiscoverDetailView: View {
    let item: AmenDiscoverItem
    let namespace: Namespace.ID
    let onWhyThis: () -> Void
    let onFeedback: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 300)
                    .matchedGeometryEffect(id: "tile_media_\(item.id)", in: namespace)

                Text(item.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.black)

                if let caption = item.caption {
                    Text(caption)
                        .foregroundStyle(.black.opacity(0.75))
                }

                if !item.scriptureRefs.isEmpty {
                    Text(item.scriptureRefs.joined(separator: " • "))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.black)
                }

                HStack(spacing: 10) {
                    actionButton("Pray", icon: "hands.sparkles")
                    actionButton("Save", icon: "bookmark")
                    actionButton("Share", icon: "square.and.arrow.up")
                }

                HStack(spacing: 10) {
                    Button("Why this?", action: onWhyThis)
                    Button("Not for me", action: onFeedback)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
    }

    private func actionButton(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.thinMaterial))
    }
}

import SwiftUI

/// Compact overlapping avatar cluster for inline reply previews.
/// Shows up to 3 profile photos with soft white borders and subtle depth.
/// URLs are server-filtered — no unsafe users will appear here.
struct DynamicAvatarCluster: View {
    let urls: [String]

    private let size: CGFloat = 24
    private let overlap: CGFloat = 8

    private var visibleURLs: [String] { Array(urls.prefix(3)) }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(visibleURLs.enumerated()), id: \.offset) { index, urlString in
                avatarCircle(urlString: urlString)
                    .offset(x: CGFloat(index) * (size - overlap))
                    .zIndex(Double(3 - index))
            }
        }
        .frame(
            width: visibleURLs.count > 1
                ? CGFloat(visibleURLs.count - 1) * (size - overlap) + size
                : size,
            height: size,
            alignment: .leading
        )
    }

    private func avatarCircle(urlString: String) -> some View {
        AsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Circle()
                    .fill(.thinMaterial)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.70), lineWidth: 1.4)
        )
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}

#if DEBUG
#Preview {
    DynamicAvatarCluster(urls: [
        "https://i.pravatar.cc/48?img=1",
        "https://i.pravatar.cc/48?img=2",
        "https://i.pravatar.cc/48?img=3"
    ])
    .padding()
}
#endif

import SwiftUI

struct CreatorMediaThumbnail: View {
    let title: String
    let imageURL: URL?

    init(title: String, imageURL: URL? = nil) {
        self.title = title
        self.imageURL = imageURL
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.06))

                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.black)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .frame(height: 120)

            Text(title)
                .font(AMENFont.medium(12))
                .foregroundStyle(Color.black.opacity(0.6))
                .lineLimit(1)
        }
    }
}

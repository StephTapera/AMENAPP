import SwiftUI

struct CreatorTimelineGridView: View {
    let asset: CreatorAsset
    @Binding var trimStart: Double
    @Binding var trimEnd: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.06))

                if let thumbnailURL = asset.thumbnailURL, let url = URL(string: thumbnailURL) {
                    HStack(spacing: 2) {
                        ForEach(0..<8, id: \.self) { _ in
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    Color.black.opacity(0.05)
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    Color.black.opacity(0.08)
                                @unknown default:
                                    Color.black.opacity(0.06)
                                }
                            }
                            .frame(width: geo.size.width / 8, height: geo.size.height)
                            .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .frame(width: max(0, (trimEnd - trimStart)) * geo.size.width)
                    .offset(x: trimStart * geo.size.width)

                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 2)
                    .offset(x: trimStart * geo.size.width)

                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 2)
                    .offset(x: trimEnd * geo.size.width)
            }
        }
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

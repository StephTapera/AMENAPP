import SwiftUI

struct CreatorTimelineStripView: View {
    let assets: [CreatorAsset]
    @Binding var selectedAssetID: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(assets) { asset in
                    Button {
                        selectedAssetID = asset.id
                    } label: {
                        CreatorMediaThumbnail(
                            title: asset.type.rawValue.capitalized,
                            imageURL: URL(string: asset.thumbnailURL ?? asset.downloadURL ?? "")
                        )
                        .frame(width: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selectedAssetID == asset.id ? Color.black.opacity(0.7) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

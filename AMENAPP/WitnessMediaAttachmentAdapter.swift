import SwiftUI
import AVKit

struct WitnessDraftAttachmentPreview: View {
    let attachment: WitnessDraftAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if attachment.isVideo, let url = attachment.finalFileURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 240)
                } else if let url = attachment.finalFileURL,
                          let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 240)
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 240)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    Image(systemName: attachment.mode == .dualPhoto ? "person.crop.rectangle.stack.fill" : (attachment.isVideo ? "video.fill" : "camera.fill"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(attachment.mode == .dualPhoto ? "Witness dual capture" : "Witness capture")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(12)
        }
    }
}

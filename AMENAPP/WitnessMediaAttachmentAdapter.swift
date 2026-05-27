import SwiftUI
import AVKit
import AVFoundation

struct WitnessDraftAttachmentPreview: View {
    let attachment: WitnessDraftAttachment
    let onRemove: () -> Void

    @State private var videoPlayer: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if attachment.isVideo {
                    VideoPlayer(player: videoPlayer)
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
        .onAppear {
            guard attachment.isVideo, let url = attachment.finalFileURL else { return }
            // FIX: Configure AVAudioSession before instantiating AVPlayer.
            // .mixWithOthers prevents silently interrupting Apple Music or other audio.
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                // Non-fatal: video may still play without audio session config
            }
            videoPlayer = AVPlayer(url: url)
        }
        .onDisappear {
            videoPlayer?.pause()
            videoPlayer = nil
        }
    }
}

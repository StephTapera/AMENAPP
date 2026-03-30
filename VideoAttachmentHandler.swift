//
//  VideoAttachmentHandler.swift
//  AMENAPP
//
//  Required Info.plist keys (add if not present):
//    NSPhotoLibraryUsageDescription  — "AMEN needs access to your photo library to share videos."
//    NSMicrophoneUsageDescription    — "AMEN needs microphone access to record voice messages."
//

import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth

// MARK: - PHPicker wrapped for video selection

struct VideoPicker: UIViewControllerRepresentable {

    let conversationId: String
    let onVideoSelected: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker

        init(_ parent: VideoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }

            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                guard let self, let url else { return }
                // Copy to a temp location we own (the system deletes the source after this block)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    DispatchQueue.main.async {
                        self.parent.onVideoSelected(tempURL)
                    }
                } catch {
                    dlog("❌ [Video] Copy temp failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Video compression helper

enum VideoAttachmentService {

    /// Compress a video at `inputURL` using AVAssetExportPresetMediumQuality.
    /// Returns the URL of the compressed file, or the original if compression fails.
    static func compress(_ inputURL: URL) async -> URL {
        let asset = AVAsset(url: inputURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        ) else { return inputURL }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        if session.status == .completed {
            dlog("✅ [Video] Compressed to \(outputURL.lastPathComponent)")
            return outputURL
        } else {
            dlog("⚠️ [Video] Compression failed (\(session.error?.localizedDescription ?? "unknown")), using original")
            return inputURL
        }
    }

    /// Generate a thumbnail image from the first frame of a video.
    static func thumbnail(for url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 400, height: 400)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cgImage = try? gen.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Upload a video file to Firebase Storage and write the Firestore message document.
    /// Progress is reported via the `onProgress` callback (0.0 – 1.0).
    static func uploadAndSend(
        videoURL: URL,
        conversationId: String,
        senderId: String,
        senderName: String?,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (AppMessage) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        Task {
            do {
                // 1. Compress
                let compressedURL = await compress(videoURL)

                // 2. Duration
                let asset = AVAsset(url: compressedURL)
                let duration: Double
                if #available(iOS 16, *) {
                    duration = try await asset.load(.duration).seconds
                } else {
                    duration = asset.duration.seconds
                }

                // 3. Upload
                let filename = "\(UUID().uuidString).mp4"
                let storagePath = "chat_videos/\(conversationId)/\(filename)"
                let storageRef = Storage.storage().reference().child(storagePath)
                let videoData = try Data(contentsOf: compressedURL)

                let metadata = StorageMetadata()
                metadata.contentType = "video/mp4"

                // Report indeterminate progress during upload
                await MainActor.run { onProgress(0.3) }
                _ = try await storageRef.putDataAsync(videoData, metadata: metadata)
                await MainActor.run { onProgress(0.9) }

                let downloadURL = try await storageRef.downloadURL()

                // 4. Build Firestore document
                let messageId = UUID().uuidString
                let db = Firestore.firestore()
                let messageData: [String: Any] = [
                    "id": messageId,
                    "text": "",
                    "senderId": senderId,
                    "senderName": senderName ?? "",
                    "timestamp": FieldValue.serverTimestamp(),
                    "isSent": true,
                    "isDelivered": false,
                    "messageType": MessageType.video.rawValue,
                    "mediaURL": downloadURL.absoluteString,
                    "mediaDuration": duration
                ]

                try await db.collection("conversations").document(conversationId)
                    .collection("messages").document(messageId)
                    .setData(messageData)

                // Update conversation last message
                try? await db.collection("conversations").document(conversationId)
                    .updateData([
                        "lastMessageText": "🎬 Video",
                        "lastMessageTimestamp": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])

                // 5. Return AppMessage for optimistic display
                let msg = AppMessage(
                    id: messageId,
                    text: "",
                    isFromCurrentUser: true,
                    timestamp: Date(),
                    senderId: senderId,
                    senderName: senderName,
                    isSent: true,
                    isDelivered: false,
                    messageType: .video,
                    mediaURL: downloadURL.absoluteString,
                    mediaDuration: duration
                )
                await MainActor.run { onComplete(msg) }

                // Cleanup temp files
                try? FileManager.default.removeItem(at: compressedURL)
                if compressedURL != videoURL {
                    try? FileManager.default.removeItem(at: videoURL)
                }

            } catch {
                await MainActor.run { onError(error) }
            }
        }
    }
}

// MARK: - Video Message Bubble

struct VideoMessageBubble: View {
    let message: AppMessage
    let isFromCurrentUser: Bool

    @State private var thumbnail: UIImage?
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .center) {
            // Thumbnail
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 240, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Play / upload overlay
            if let progress = message.uploadProgress, progress < 1.0 {
                ZStack {
                    Color.black.opacity(0.4)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.2)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 240, height: 200)
            } else {
                // Play button
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 50, height: 50)
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }
            }

            // Duration badge
            if let dur = message.mediaDuration, dur > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(dur))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .padding(8)
                    }
                }
                .frame(width: 240, height: 200)
            }
        }
        .onTapGesture {
            if message.uploadProgress == nil || (message.uploadProgress ?? 0) >= 1.0 {
                showPlayer = true
            }
        }
        .task {
            guard let urlString = message.mediaURL, let url = URL(string: urlString) else { return }
            thumbnail = await Task.detached(priority: .utility) {
                VideoAttachmentService.thumbnail(for: url)
            }.value
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let urlString = message.mediaURL, let url = URL(string: urlString) {
                VideoPlayerSheet(url: url)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return "0:\(String(format: "%02d", s))" }
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

// MARK: - Video Player Sheet

private struct VideoPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(20)
            }
        }
    }
}

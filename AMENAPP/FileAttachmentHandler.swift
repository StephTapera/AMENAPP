//
//  FileAttachmentHandler.swift
//  AMENAPP
//
//  Required Info.plist key (add if not present):
//    NSPhotoLibraryUsageDescription — "AMEN needs access to your photo library to share files."
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {

    let onFilePicked: (URL, String, Int) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .pdf,
            .plainText,
            .spreadsheet,
            .presentation,
            .image,
            .zip
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            // Security-scoped resource access
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            // Copy to a temp location we own
            let filename = url.lastPathComponent
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_" + filename)

            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
                DispatchQueue.main.async {
                    self.parent.onFilePicked(tempURL, filename, size)
                }
            } catch {
                dlog("❌ [File] Copy failed: \(error)")
            }
        }
    }
}

// MARK: - File Upload Service

enum FileAttachmentService {

    static func uploadAndSend(
        fileURL: URL,
        fileName: String,
        fileSize: Int,
        conversationId: String,
        senderId: String,
        senderName: String?,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (AppMessage) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        Task {
            do {
                let fileExtension = (fileName as NSString).pathExtension.lowercased()
                let storageName = "\(UUID().uuidString)_\(fileName)"
                let storagePath = "chat_files/\(conversationId)/\(storageName)"
                let storageRef = Storage.storage().reference().child(storagePath)

                let fileData = try Data(contentsOf: fileURL)

                let metadata = StorageMetadata()
                metadata.contentType = mimeType(for: fileExtension)

                await MainActor.run { onProgress(0.3) }
                _ = try await storageRef.putDataAsync(fileData, metadata: metadata)
                await MainActor.run { onProgress(0.9) }

                let downloadURL = try await storageRef.downloadURL()

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
                    "messageType": MessageType.file.rawValue,
                    "mediaURL": downloadURL.absoluteString,
                    "mediaFileName": fileName,
                    "mediaFileSize": fileSize,
                    "mediaFileExtension": fileExtension
                ]

                try await db.collection("conversations").document(conversationId)
                    .collection("messages").document(messageId)
                    .setData(messageData)

                try? await db.collection("conversations").document(conversationId)
                    .updateData([
                        "lastMessageText": "📎 \(fileName)",
                        "lastMessageTimestamp": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])

                let msg = AppMessage(
                    id: messageId,
                    text: "",
                    isFromCurrentUser: true,
                    timestamp: Date(),
                    senderId: senderId,
                    senderName: senderName,
                    isSent: true,
                    isDelivered: false,
                    messageType: .file,
                    mediaURL: downloadURL.absoluteString,
                    mediaFileName: fileName,
                    mediaFileSize: fileSize,
                    mediaFileExtension: fileExtension
                )
                await MainActor.run { onComplete(msg) }

                try? FileManager.default.removeItem(at: fileURL)

            } catch {
                await MainActor.run { onError(error) }
            }
        }
    }

    static func mimeType(for ext: String) -> String {
        switch ext {
        case "pdf":  return "application/pdf"
        case "doc", "docx": return "application/msword"
        case "xls", "xlsx": return "application/vnd.ms-excel"
        case "ppt", "pptx": return "application/vnd.ms-powerpoint"
        case "txt":  return "text/plain"
        case "zip":  return "application/zip"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default:     return "application/octet-stream"
        }
    }
}

// MARK: - File Message Bubble

struct FileMessageBubble: View {
    let message: AppMessage
    let isFromCurrentUser: Bool

    @State private var downloadedURL: URL?
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var showPreview = false

    var body: some View {
        HStack(spacing: 12) {
            // File type icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(message.mediaFileName ?? "File")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isFromCurrentUser ? .white : Color(.label))
                    .lineLimit(1)

                Text(formattedSize)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isFromCurrentUser ? .white.opacity(0.75) : Color(.secondaryLabel))
            }

            Spacer(minLength: 0)

            // Upload / download indicator
            if let progress = message.uploadProgress, progress < 1.0 {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .tint(isFromCurrentUser ? .white : .blue)
                    .frame(width: 24, height: 24)
            } else if isDownloading {
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.circular)
                    .tint(.blue)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: downloadedURL == nil ? "arrow.down.circle" : "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isFromCurrentUser ? .white.opacity(0.85) : .blue)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFromCurrentUser
                    ? LinearGradient(colors: [Color(red: 0.0, green: 0.50, blue: 1.0), Color(red: 0.0, green: 0.40, blue: 0.92)], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color(.systemGray6), Color(.systemGray6)], startPoint: .top, endPoint: .bottom)
                )
        )
        .onTapGesture { handleTap() }
        .sheet(isPresented: $showPreview) {
            if let url = downloadedURL {
                QuickLookPreview(url: url)
            }
        }
    }

    // MARK: Private helpers

    private var fileExtension: String {
        (message.mediaFileName ?? message.mediaFileExtension ?? "").lowercased()
            .components(separatedBy: ".").last ?? ""
    }

    private var iconName: String {
        switch fileExtension {
        case "pdf":                  return "doc.richtext.fill"
        case "doc", "docx":          return "doc.fill"
        case "xls", "xlsx":          return "tablecells.fill"
        case "ppt", "pptx":          return "rectangle.on.rectangle.angled.fill"
        case "zip", "rar":           return "archivebox.fill"
        case "txt":                  return "doc.plaintext.fill"
        default:                     return "doc.fill"
        }
    }

    private var iconColor: Color {
        switch fileExtension {
        case "pdf":              return .red
        case "doc", "docx":     return .blue
        case "xls", "xlsx":     return .green
        case "ppt", "pptx":     return Color.orange
        case "zip", "rar":      return Color.orange
        default:                return .gray
        }
    }

    private var iconBackground: Color {
        iconColor.opacity(0.15)
    }

    private var formattedSize: String {
        guard let size = message.mediaFileSize, size > 0 else { return "File" }
        if size < 1024 { return "\(size) B" }
        if size < 1_048_576 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / 1_048_576)
    }

    private func handleTap() {
        guard message.uploadProgress == nil || (message.uploadProgress ?? 0) >= 1.0 else { return }
        if let existing = downloadedURL {
            // Already downloaded — show QuickLook
            _ = existing
            showPreview = true
            return
        }
        guard let urlString = message.mediaURL, let remoteURL = URL(string: urlString) else { return }
        downloadFile(from: remoteURL)
    }

    private func downloadFile(from remoteURL: URL) {
        isDownloading = true
        let fileName = message.mediaFileName ?? "file"
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + fileName)

        Task {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                await MainActor.run {
                    downloadedURL = destURL
                    isDownloading = false
                    showPreview = true
                }
            } catch {
                await MainActor.run { isDownloading = false }
                dlog("❌ [File] Download failed: \(error)")
            }
        }
    }
}

// MARK: - QuickLook Preview wrapper

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

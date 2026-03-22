//
//  LinkAttachmentHandler.swift
//  AMENAPP
//
//  No additional Info.plist key required beyond standard network access.
//

import SwiftUI
import LinkPresentation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Link Attach Sheet

struct LinkAttachSheet: View {

    let conversationId: String
    let senderId: String
    let senderName: String?
    let onMessageCreated: (AppMessage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String = ""
    @State private var description: String = ""
    @State private var isFetching: Bool = false
    @State private var fetchedMeta: LPLinkMetadata? = nil
    @State private var fetchError: String? = nil
    @State private var isSending: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // URL field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("URL")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("https://", text: $urlText)
                                    .keyboardType(.URL)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 16))
                                    .onChange(of: urlText) { _, _ in
                                        fetchedMeta = nil
                                        fetchError = nil
                                    }
                                    .onSubmit { fetchMetadata() }

                                if isFetching {
                                    ProgressView().scaleEffect(0.8)
                                } else if !urlText.isEmpty {
                                    Button { fetchMetadata() } label: {
                                        Text("Preview")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }

                        // Optional description
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Caption (optional)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("Add a note…", text: $description, axis: .vertical)
                                .lineLimit(1...3)
                                .font(.system(size: 16))
                                .padding(12)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }

                        // Link preview card
                        if let meta = fetchedMeta {
                            LinkAttachSheetPreviewCard(metadata: meta)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else if let err = fetchError {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Attach button
                        Button {
                            attachLink()
                        } label: {
                            HStack {
                                if isSending {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "link")
                                    Text("Attach Link")
                                }
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(validURL != nil ? Color.blue : Color.gray.opacity(0.4))
                            )
                        }
                        .disabled(validURL == nil || isSending)
                        .animation(.spring(response: 0.3), value: validURL != nil)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Attach Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    private var validURL: URL? {
        guard !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") {
            raw = "https://" + raw
        }
        return URL(string: raw)
    }

    private func fetchMetadata() {
        guard let url = validURL else { return }
        isFetching = true
        fetchError = nil
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { meta, error in
            DispatchQueue.main.async {
                isFetching = false
                if let meta {
                    fetchedMeta = meta
                } else {
                    fetchError = "Could not load preview for this URL."
                }
            }
        }
    }

    private func attachLink() {
        guard let url = validURL else { return }
        isSending = true

        Task {
            // Extract metadata from LPLinkMetadata if available
            let title = fetchedMeta?.title
            let metaDescription: String? = nil  // LPLinkMetadata doesn't expose description directly
            let thumbnailURL: String? = nil      // Thumbnail needs special async handling
            let domain = url.host?.replacingOccurrences(of: "www.", with: "")

            let messageId = UUID().uuidString
            let db = Firestore.firestore()
            let messageData: [String: Any] = [
                "id": messageId,
                "text": description.trimmingCharacters(in: .whitespacesAndNewlines),
                "senderId": senderId,
                "senderName": senderName ?? "",
                "timestamp": FieldValue.serverTimestamp(),
                "isSent": true,
                "isDelivered": false,
                "messageType": MessageType.link.rawValue,
                "linkURL": url.absoluteString,
                "linkTitle": title ?? "",
                "linkDescription": metaDescription ?? "",
                "linkDomain": domain ?? ""
            ]

            do {
                try await db.collection("conversations").document(conversationId)
                    .collection("messages").document(messageId)
                    .setData(messageData)

                try? await db.collection("conversations").document(conversationId)
                    .updateData([
                        "lastMessageText": "🔗 \(title ?? url.absoluteString)",
                        "lastMessageTimestamp": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])

                let msg = AppMessage(
                    id: messageId,
                    text: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFromCurrentUser: true,
                    timestamp: Date(),
                    senderId: senderId,
                    senderName: senderName,
                    isSent: true,
                    isDelivered: false,
                    messageType: .link,
                    linkURL: url.absoluteString,
                    linkTitle: title,
                    linkDescription: metaDescription,
                    linkThumbnailURL: thumbnailURL,
                    linkDomain: domain
                )
                await MainActor.run {
                    onMessageCreated(msg)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    dlog("❌ [Link] Firestore write failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Link Preview Card (used inside the sheet)

private struct LinkAttachSheetPreviewCard: View {
    let metadata: LPLinkMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail from imageProvider
            if let imageProvider = metadata.imageProvider {
                AsyncLPImage(provider: imageProvider)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 4) {
                if let domain = metadata.url?.host?.replacingOccurrences(of: "www.", with: "") {
                    Text(domain.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                }
                if let title = metadata.title {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

// MARK: - NSItemProvider image loader

private struct AsyncLPImage: View {
    let provider: NSItemProvider
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
            }
        }
        .task {
            image = await loadImage()
        }
    }

    private func loadImage() async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { obj, _ in
                continuation.resume(returning: obj as? UIImage)
            }
        }
    }
}

// MARK: - Link Message Bubble

struct LinkMessageBubble: View {
    let message: AppMessage
    let isFromCurrentUser: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Optional caption text above the card
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(isFromCurrentUser ? .white : Color(.label))
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            // Link card
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                if let thumbURLString = message.linkThumbnailURL,
                   let thumbURL = URL(string: thumbURLString) {
                    AsyncImage(url: thumbURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 140).clipped()
                        default:
                            Color(.systemGray5).frame(height: 80)
                        }
                    }
                } else {
                    // Fallback placeholder
                    ZStack {
                        Color(.systemGray5)
                        Image(systemName: "link")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let domain = message.linkDomain, !domain.isEmpty {
                        Text(domain.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                    }
                    if let title = message.linkTitle, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    if let desc = message.linkDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(10)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .padding(.horizontal, isFromCurrentUser ? 10 : 0)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 280, alignment: isFromCurrentUser ? .trailing : .leading)
        .onTapGesture {
            if let urlString = message.linkURL, let url = URL(string: urlString) {
                openURL(url)
            }
        }
    }
}

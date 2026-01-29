//
//  MessagingComponents.swift
//  AMENAPP
//
//  Complete UI components for messaging system
//

import SwiftUI
import PhotosUI
import FirebaseAuth

// MARK: - Photo Picker View

struct MessagingPhotoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImages: [UIImage]
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    
    private let maxSelection = 10
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !selectedImages.isEmpty {
                    selectedImagesPreview
                }
                
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: maxSelection,
                    matching: .images
                ) {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        VStack(spacing: 8) {
                            Text("Select Photos")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            Text("Choose up to \(maxSelection) photos")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                if isLoading {
                    ProgressView("Loading photos...")
                        .padding()
                }
            }
            .navigationTitle("Select Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(selectedImages.isEmpty)
                }
            }
            .onChange(of: selectedItems) { _, newItems in
                loadImages(from: newItems)
            }
        }
    }
    
    private var selectedImagesPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        Button {
                            withAnimation {
                                let _ = selectedImages.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                                .background(
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 20, height: 20)
                                )
                        }
                        .padding(4)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func loadImages(from items: [PhotosPickerItem]) {
        isLoading = true
        selectedImages.removeAll()
        
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImages.append(image)
                    }
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Messaging User Search View
// NOTE: MessagingUserSearchView has been moved to MessagingUserSearchView.swift
// NOTE: FirebaseSearchUser has been moved to UserSearchService.swift

// MARK: - Modern Message Bubble

struct ModernMessageBubble: View {
    let message: AppMessage
    let showAvatar: Bool
    let showTimestamp: Bool
    let showSenderName: Bool
    let onReply: () -> Void
    let onReact: (String) -> Void
    
    @State private var showReactionPicker = false
    
    init(
        message: AppMessage,
        showAvatar: Bool = true,
        showTimestamp: Bool = false,
        showSenderName: Bool = false,
        onReply: @escaping () -> Void,
        onReact: @escaping (String) -> Void
    ) {
        self.message = message
        self.showAvatar = showAvatar
        self.showTimestamp = showTimestamp
        self.showSenderName = showSenderName
        self.onReply = onReply
        self.onReact = onReact
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !message.isFromCurrentUser && showAvatar {
                senderAvatar
            } else if !message.isFromCurrentUser {
                // Spacer for alignment when avatar not shown
                Color.clear.frame(width: 32, height: 32)
            }
            
            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name for group chats
                if showSenderName && !message.isFromCurrentUser {
                    Text(message.senderName ?? "Unknown")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
                
                // System message styling
                if message.senderId == "system" {
                    systemMessageView
                } else if message.isDeleted {
                    deletedMessageView
                } else {
                    regularMessageView
                }
                
                // Timestamp
                if showTimestamp {
                    timestampView
                }
            }
            
            if message.isFromCurrentUser {
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
            }
        }
        .contextMenu {
            messageContextMenu
        }
    }
    
    // MARK: - Avatar
    
    private var senderAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 32, height: 32)
            
            Text(message.senderInitials)
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.blue)
        }
    }
    
    // MARK: - System Message
    
    private var systemMessageView: some View {
        Text(message.text)
            .font(.custom("OpenSans-Regular", size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
            )
            .frame(maxWidth: .infinity)
    }
    
    // MARK: - Deleted Message
    
    private var deletedMessageView: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.slash")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            
            Text("This message was deleted")
                .font(.custom("OpenSans-Regular", size: 14))
                .italic()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemGray6))
        )
    }
    
    // MARK: - Regular Message
    
    private var regularMessageView: some View {
        VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 6) {
            // Reply-to preview
            if let replyTo = message.replyTo {
                replyPreview(replyTo)
            }
            
            // Message text
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(message.isFromCurrentUser ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Attachments
            if !message.attachments.isEmpty {
                attachmentsView
            }
            
            // Edited indicator
            if message.editedAt != nil {
                editedIndicator
            }
            
            // Reactions
            if !message.reactions.isEmpty {
                reactionsView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(message.isFromCurrentUser ? Color.blue : Color(.systemGray5))
        )
    }
    
    // MARK: - Reply Preview
    
    private func replyPreview(_ replyTo: AppMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(replyTo.senderName ?? "Someone")
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(message.isFromCurrentUser ? .white.opacity(0.8) : .secondary)
            
            Text(replyTo.text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(message.isFromCurrentUser ? .white.opacity(0.7) : .secondary)
                .lineLimit(2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(message.isFromCurrentUser ? Color.white.opacity(0.2) : Color(.systemGray6))
        )
    }
    
    // MARK: - Attachments
    
    private var attachmentsView: some View {
        VStack(spacing: 8) {
            ForEach(message.attachments, id: \.id) { attachment in
                if attachment.type == .photo {
                    // Photo placeholder - implement AsyncImage or custom loader
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 200, height: 200)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
    }
    
    // MARK: - Edited Indicator
    
    private var editedIndicator: some View {
        Text("(edited)")
            .font(.custom("OpenSans-Regular", size: 11))
            .italic()
            .foregroundStyle(message.isFromCurrentUser ? .white.opacity(0.7) : .secondary)
    }
    
    // MARK: - Reactions
    
    private var reactionsView: some View {
        HStack(spacing: 6) {
            ForEach(groupedReactions, id: \.emoji) { group in
                HStack(spacing: 4) {
                    Text(group.emoji)
                        .font(.system(size: 16))
                    
                    if group.count > 1 {
                        Text("\(group.count)")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(.systemGray6))
                )
            }
        }
    }
    
    private var groupedReactions: [(emoji: String, count: Int)] {
        let grouped = Dictionary(grouping: message.reactions, by: { $0.emoji })
        return grouped.map { (emoji: $0.key, count: $0.value.count) }
            .sorted { $0.emoji < $1.emoji }
    }
    
    // MARK: - Timestamp
    
    private var timestampView: some View {
        HStack(spacing: 4) {
            Text(formatTime(message.timestamp))
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.secondary)
            
            // Read receipt for sent messages
            if message.isFromCurrentUser {
                if message.isRead {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Context Menu
    
    private var messageContextMenu: some View {
        Group {
            if !message.isDeleted && message.senderId != "system" {
                Button {
                    onReply()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                
                Button {
                    // Show reaction picker
                    onReact("❤️")
                } label: {
                    Label("React", systemImage: "face.smiling")
                }
                
                if message.isFromCurrentUser {
                    Divider()
                    
                    Button(role: .destructive) {
                        // Delete message
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}

// MARK: - Modern Typing Indicator
// Note: ModernTypingIndicator is now defined in MessagingUXComponents.swift to avoid duplication

// MARK: - Modern Chat Input Bar

struct ModernChatInputBar: View {
    @Binding var messageText: String
    @FocusState var isInputFocused: Bool
    @Binding var selectedImages: [UIImage]
    let onSend: () -> Void
    let onPhotoPicker: () -> Void
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Selected images preview
            if !selectedImages.isEmpty {
                selectedImagesPreview
            }
            
            // Input bar
            HStack(spacing: 12) {
                // Photo button
                Button(action: onPhotoPicker) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.2))
                        )
                }
                
                // Text field
                HStack(spacing: 8) {
                    TextField("Message", text: $messageText, axis: .vertical)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white)
                        .focused($isInputFocused)
                        .lineLimit(1...5)
                    
                    if !messageText.isEmpty {
                        Button {
                            messageText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                )
                
                // Send button
                Button(action: {
                    guard canSend else { return }
                    onSend()
                }) {
                    Image(systemName: canSend ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? .blue : .white.opacity(0.3))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)
        }
    }
    
    private var selectedImagesPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Button {
                            withAnimation {
                                let _ = selectedImages.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .background(
                                    Circle()
                                        .fill(Color.black).opacity(0.5)
                                        .frame(width: 16, height: 16)
                                )
                        }
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.8))
    }
}


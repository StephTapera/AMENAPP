//
//  ChatView.swift
//  AMENAPP
//
//  Production-ready chat interface for direct and group messaging
//  Created: January 27, 2026
//

import SwiftUI
import FirebaseAuth
import PhotosUI

struct ChatView: View {
    // MARK: - Properties
    let conversation: ChatConversation
    
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var messages: [AppMessage] = []
    @State private var messageText = ""
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var showScrollToBottom = false
    @State private var isLoadingMessages = true
    @State private var showConversationInfo = false
    
    @FocusState private var isInputFocused: Bool
    
    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            messagesScrollView
            
            // Upload Progress
            if isUploading {
                uploadProgressView
            }
            
            // Message Input
            messageInputBar
        }
        .navigationTitle(conversation.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                navigationMenu
            }
        }
        .onAppear {
            loadMessages()
            markMessagesAsRead()
        }
        .onDisappear {
            stopListening()
        }
        .sheet(isPresented: $showImagePicker) {
            ChatImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showConversationInfo) {
            ConversationInfoView(conversation: conversation)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                uploadImage(image)
            }
        }
    }
    
    // MARK: - Messages ScrollView
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isLoadingMessages {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else if messages.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            ChatMessageBubbleView(
                                message: message,
                                isFromCurrentUser: message.isFromCurrentUser,
                                showSenderName: conversation.isGroup
                            )
                            .id(message.id)
                            .contextMenu {
                                messageContextMenu(for: message)
                            }
                        }
                    }
                    .padding()
                }
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    // MARK: - Message Input Bar
    private var messageInputBar: some View {
        HStack(spacing: 12) {
            // Attachment Button
            Button {
                showImagePicker = true
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            
            // Text Field
            TextField("Message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    if !messageText.isEmpty {
                        sendMessage()
                    }
                }
            
            // Send Button
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(messageText.isEmpty ? .gray : .blue)
            }
            .disabled(messageText.isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color(.separator)),
            alignment: .top
        )
    }
    
    // MARK: - Navigation Menu
    private var navigationMenu: some View {
        Menu {
            Button {
                showConversationInfo = true
            } label: {
                Label("Conversation Info", systemImage: "info.circle")
            }
            
            Button {
                muteConversation()
            } label: {
                Label("Mute", systemImage: "bell.slash")
            }
            
            Button {
                archiveConversation()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            
            Button(role: .destructive) {
                deleteConversation()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
        }
    }
    
    // MARK: - Message Context Menu
    private func messageContextMenu(for message: AppMessage) -> some View {
        Group {
            Button {
                UIPasteboard.general.string = message.text
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            Button {
                pinMessage(message)
            } label: {
                Label(message.isPinned ? "Unpin" : "Pin", systemImage: "pin")
            }
            
            if message.isFromCurrentUser {
                Button(role: .destructive) {
                    deleteMessage(message)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            
            Button {
                // TODO: Implement reply
                print("Reply to message")
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: conversation.isGroup ? "person.3" : "message")
                .font(.system(size: 60))
                .foregroundStyle(.gray)
            
            Text("No messages yet")
                .font(.custom("OpenSans-SemiBold", size: 18))
                .foregroundStyle(.primary)
            
            Text(conversation.isGroup ? "Start the group conversation!" : "Say hi! 👋")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Upload Progress
    private var uploadProgressView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Uploading image...")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding()
    }
    
    // MARK: - Functions
    
    private func loadMessages() {
        let conversationId = conversation.id
        
        // Start listening to messages
        messagingService.startListeningToMessages(
            conversationId: conversationId
        ) { [self] newMessages in
            messages = newMessages
            isLoadingMessages = false
        }
    }
    
    private func stopListening() {
        messagingService.stopListeningToMessages(conversationId: conversation.id)
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let conversationId = conversation.id
        
        Task {
            do {
                try await messagingService.sendMessage(
                    conversationId: conversationId,
                    text: messageText
                )
                
                // Clear input
                await MainActor.run {
                    messageText = ""
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("❌ Error sending message: \(error)")
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func uploadImage(_ image: UIImage) {
        let conversationId = conversation.id
        
        isUploading = true
        
        Task {
            do {
                // Use the service's built-in method for sending images
                try await messagingService.sendMessageWithPhotos(
                    conversationId: conversationId,
                    text: "📷 Photo",
                    images: [image]
                )
                
                await MainActor.run {
                    isUploading = false
                    selectedImage = nil
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("❌ Error uploading image: \(error)")
                await MainActor.run {
                    isUploading = false
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func markMessagesAsRead() {
        // Note: The messaging service automatically marks messages as read when listening
        // This is a placeholder for future explicit read marking if needed
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func pinMessage(_ message: AppMessage) {
        let conversationId = conversation.id
        
        Task {
            do {
                if message.isPinned {
                    try await messagingService.unpinMessage(conversationId: conversationId, messageId: message.id)
                } else {
                    try await messagingService.pinMessage(conversationId: conversationId, messageId: message.id)
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                print("❌ Error pinning message: \(error)")
            }
        }
    }
    
    private func deleteMessage(_ message: AppMessage) {
        let conversationId = conversation.id
        
        Task {
            do {
                try await messagingService.deleteMessage(
                    conversationId: conversationId,
                    messageId: message.id
                )
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                print("❌ Error deleting message: \(error)")
            }
        }
    }
    
    private func muteConversation() {
        let conversationId = conversation.id
        
        Task {
            do {
                try await messagingService.muteConversation(
                    conversationId: conversationId,
                    muted: true
                )
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                print("❌ Error muting conversation: \(error)")
            }
        }
    }
    
    private func archiveConversation() {
        let conversationId = conversation.id
        
        Task {
            do {
                try await messagingService.archiveConversation(
                    conversationId: conversationId
                )
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                print("❌ Error archiving conversation: \(error)")
            }
        }
    }
    
    private func deleteConversation() {
        let conversationId = conversation.id
        
        Task {
            do {
                try await messagingService.deleteConversation(
                    conversationId: conversationId
                )
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                print("❌ Error deleting conversation: \(error)")
            }
        }
    }
}

// MARK: - Message Bubble View
struct ChatMessageBubbleView: View {
    let message: AppMessage
    let isFromCurrentUser: Bool
    let showSenderName: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name (for group chats)
                if showSenderName && !isFromCurrentUser, let senderName = message.senderName {
                    Text(senderName)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
                
                // Message content
                VStack(alignment: .leading, spacing: 8) {
                    // Image attachment
                    if let attachment = message.attachments.first,
                       attachment.type == .photo,
                       let url = attachment.url {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: 250, maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure(_):
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.gray)
                                    .frame(width: 250, height: 200)
                            case .empty:
                                ProgressView()
                                    .frame(width: 250, height: 200)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    // Text (only show if not just image placeholder)
                    if !message.text.isEmpty && message.text != "📷 Photo" {
                        Text(message.text)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(isFromCurrentUser ? .white : .primary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isFromCurrentUser ? Color.blue : Color(.systemGray5))
                )
                
                // Timestamp + read status
                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                    
                    if isFromCurrentUser {
                        Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    if message.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
            }
            
            if !isFromCurrentUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Image Picker
struct ChatImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ChatImagePicker
        
        init(_ parent: ChatImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Conversation Info View
struct ConversationInfoView: View {
    let conversation: ChatConversation
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        // Avatar
                        if conversation.isGroup {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)
                                .frame(width: 100, height: 100)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(conversation.avatarColor.opacity(0.1))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Text(conversation.initials)
                                        .font(.custom("OpenSans-Bold", size: 32))
                                        .foregroundStyle(conversation.avatarColor)
                                )
                        }
                        
                        // Name
                        Text(conversation.name)
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        // Group info
                        if conversation.isGroup {
                            Text("Group Chat")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                
                Section("About") {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(conversation.isGroup ? "Group" : "Direct")
                            .foregroundStyle(.secondary)
                    }
                    
                    if conversation.unreadCount > 0 {
                        HStack {
                            Text("Unread Messages")
                            Spacer()
                            Text("\(conversation.unreadCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Last Message")
                        Spacer()
                        Text(conversation.timestamp)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Conversation Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        ChatView(conversation: ChatConversation(
            id: "preview",
            name: "John Doe",
            lastMessage: "Hello!",
            timestamp: "5m ago",
            isGroup: false,
            unreadCount: 0,
            avatarColor: .blue
        ))
    }
}

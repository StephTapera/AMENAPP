import SwiftUI
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Simple Message Model for UI

/// Simplified message model for UI display
struct MessageUI: Identifiable {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date
}

// MARK: - Unified Messaging Service Wrapper

/// Unified service that wraps the existing messaging services for easier UI integration
class MessagingService {
    static let shared = MessagingService()
    
    private let firebaseService = FirebaseMessagingService.shared
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Get message status for a user
    func getMessageStatus(for userId: String) async -> MessageStatus {
        return await MessagingPermissionService.shared.getMessageStatus(for: userId)
    }
    
    /// Find or create a conversation with another user
    func findOrCreateConversation(with userId: String) async throws -> String {
        // Use the existing Firebase method that handles permissions
        // First, fetch the user's display name
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let userName = userDoc.data()?["displayName"] as? String ?? "Unknown"
        
        return try await firebaseService.getOrCreateDirectConversation(withUserId: userId, userName: userName)
    }
    
    /// Get remaining message requests (returns 1 if they haven't sent any messages yet, 0 if they have)
    func getRemainingMessageRequests(for conversationId: String) async throws -> Int? {
        return try await MessagingPermissionService.shared.getRemainingMessageRequests(for: conversationId)
    }
    
    /// Send a message
    func sendMessage(to conversationId: String, text: String) async throws {
        try await firebaseService.sendMessageWithPermissions(to: conversationId, text: text)
    }
    
    /// Listen to messages in a conversation
    func listenToMessages(conversationId: String, completion: @escaping ([MessageUI]) -> Void) -> ListenerRegistration {
        return db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching messages: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                let messages = documents.compactMap { doc -> MessageUI? in
                    let data = doc.data()
                    guard let senderId = data["senderId"] as? String,
                          let text = data["text"] as? String,
                          let timestamp = data["createdAt"] as? Timestamp else {
                        return nil
                    }
                    
                    return MessageUI(
                        id: doc.documentID,
                        senderId: senderId,
                        text: text,
                        createdAt: timestamp.dateValue()
                    )
                }
                
                completion(messages)
            }
    }
}

// MARK: - Messaging UI Example

struct MessageComposerView: View {
    let otherUserId: String
    let otherUsername: String
    
    @State private var messageText = ""
    @State private var conversationId: String?
    @State private var messages: [MessageUI] = []
    @State private var messageStatus: MessageStatus = .unlimited
    @State private var remainingRequests: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var listener: ListenerRegistration?
    
    var body: some View {
        VStack {
            // Messages list
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages, id: \.id) { message in
                        MessageBubble(
                            message: message,
                            isFromCurrentUser: message.senderId == Auth.auth().currentUser?.uid
                        )
                    }
                }
                .padding()
            }
            
            // Message request banner
            if messageStatus == .messageRequest {
                MessageRequestBanner(remainingRequests: remainingRequests)
            }
            
            // Blocked banner
            if messageStatus == .blocked {
                BlockedBanner()
            }
            
            // Message input
            if messageStatus != .blocked {
                MessageInputBar(
                    text: $messageText,
                    isEnabled: messageStatus != .blocked && (messageStatus == .unlimited || remainingRequests ?? 0 > 0),
                    onSend: sendMessage
                )
            }
        }
        .navigationTitle(otherUsername)
        .task {
            await loadConversation()
        }
        .onDisappear {
            listener?.remove()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    private func loadConversation() async {
        isLoading = true
        
        do {
            // Check message status
            messageStatus = await MessagingService.shared.getMessageStatus(for: otherUserId)
            
            // Find or create conversation
            conversationId = try await MessagingService.shared.findOrCreateConversation(with: otherUserId)
            
            // Get remaining message requests if applicable
            if messageStatus == .messageRequest, let convId = conversationId {
                remainingRequests = try await MessagingService.shared.getRemainingMessageRequests(for: convId)
            }
            
            // Listen to messages
            if let convId = conversationId {
                listener = MessagingService.shared.listenToMessages(conversationId: convId) { newMessages in
                    messages = newMessages
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let convId = conversationId else { return }
        
        let textToSend = messageText
        messageText = ""
        
        Task {
            do {
                try await MessagingService.shared.sendMessage(to: convId, text: textToSend)
                
                // Update remaining requests
                if messageStatus == .messageRequest {
                    remainingRequests = try await MessagingService.shared.getRemainingMessageRequests(for: convId)
                }
            } catch {
                errorMessage = error.localizedDescription
                messageText = textToSend // Restore message on error
            }
        }
    }
}

// MARK: - Message Request Banner

struct MessageRequestBanner: View {
    let remainingRequests: Int?
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "envelope.badge")
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Message Request")
                        .font(.headline)
                    
                    if let remaining = remainingRequests {
                        if remaining > 0 {
                            Text("You can send \(remaining) message. They'll see it if they follow you back.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Message request sent. Wait for them to follow you back.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
        }
    }
}

// MARK: - Blocked Banner

struct BlockedBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(.red)
            
            Text("You cannot message this user")
                .font(.headline)
            
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: MessageUI
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isFromCurrentUser {
                Spacer()
            }
        }
    }
}

// MARK: - Message Input Bar

struct MessageInputBar: View {
    @Binding var text: String
    let isEnabled: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .disabled(!isEnabled)
                .lineLimit(1...5)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isEnabled ? .gray : .blue)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isEnabled)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - User Profile View with Messaging Button

struct MessageableUserProfileView: View {
    let userId: String
    let username: String
    
    @State private var messageStatus: MessageStatus = .unlimited
    @State private var isFollowing = false
    @State private var areFollowingEachOther = false
    @State private var showMessageView = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Profile info
            Text(username)
                .font(.title)
            
            // Follow button
            Button {
                toggleFollow()
            } label: {
                Text(isFollowing ? "Unfollow" : "Follow")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFollowing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            
            // Message button with status
            Button {
                showMessageView = true
            } label: {
                HStack {
                    Image(systemName: messageIcon)
                    Text(messageButtonTitle)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(messageStatus == .blocked ? Color.red.opacity(0.3) : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(messageStatus == .blocked)
            
            // Status text
            Text(messageStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .task {
            await loadUserStatus()
        }
        .sheet(isPresented: $showMessageView) {
            NavigationView {
                MessageComposerView(otherUserId: userId, otherUsername: username)
            }
        }
    }
    
    private var messageIcon: String {
        switch messageStatus {
        case .unlimited:
            return "message.fill"
        case .messageRequest:
            return "envelope"
        case .blocked:
            return "hand.raised.fill"
        }
    }
    
    private var messageButtonTitle: String {
        switch messageStatus {
        case .unlimited:
            return "Message"
        case .messageRequest:
            return "Send Message Request"
        case .blocked:
            return "Cannot Message"
        }
    }
    
    private var messageStatusText: String {
        switch messageStatus {
        case .unlimited:
            if areFollowingEachOther {
                return "You follow each other"
            } else {
                return "They allow messages from anyone"
            }
        case .messageRequest:
            return "You can send 1 message request"
        case .blocked:
            return "You or they have blocked each other"
        }
    }
    
    private func loadUserStatus() async {
        do {
            messageStatus = await MessagingService.shared.getMessageStatus(for: userId)
            isFollowing = await FollowService.shared.isFollowing(userId: userId)
            
            // Check if they follow each other by checking both directions
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            let youFollowThem = isFollowing
            
            // Check if they follow you
            let snapshot = try await Firestore.firestore()
                .collection(FirebaseManager.CollectionPath.follows)
                .whereField("followerId", isEqualTo: userId)
                .whereField("followingId", isEqualTo: currentUserId)
                .limit(to: 1)
                .getDocuments()
            
            let theyFollowYou = !snapshot.documents.isEmpty
            areFollowingEachOther = youFollowThem && theyFollowYou
        } catch {
            print("Error loading status: \(error)")
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await FollowService.shared.unfollowUser(userId: userId)
                } else {
                    try await FollowService.shared.followUser(userId: userId)
                }
                await loadUserStatus()
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
}

// MARK: - Settings View for Message Privacy

struct MessagePrivacySettingsView: View {
    @State private var messagePrivacy: MessagePrivacy = .followers
    @State private var isLoading = false
    
    var body: some View {
        Form {
            Section {
                Picker("Who can message you?", selection: $messagePrivacy) {
                    Text("Followers only").tag(MessagePrivacy.followers)
                    Text("Anyone").tag(MessagePrivacy.anyone)
                }
                .pickerStyle(.inline)
            } header: {
                Text("Message Privacy")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if messagePrivacy == .followers {
                        Text("Only people you follow and who follow you back can send you unlimited messages. Others can send 1 message request.")
                    } else {
                        Text("Anyone can send you messages without following you.")
                    }
                }
                .font(.caption)
            }
        }
        .navigationTitle("Message Settings")
        .task {
            await loadPrivacySetting()
        }
        .onChange(of: messagePrivacy) { _, newValue in
            savePrivacySetting(newValue)
        }
    }
    
    private func loadPrivacySetting() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            messagePrivacy = try await UserServiceExtensions.shared.getMessagePrivacy(for: userId)
        } catch {
            print("Error loading privacy: \(error)")
        }
    }
    
    private func savePrivacySetting(_ privacy: MessagePrivacy) {
        Task {
            isLoading = true
            do {
                try await UserServiceExtensions.shared.updateMessagePrivacy(to: privacy)
            } catch {
                print("Error saving privacy: \(error)")
            }
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        MessageableUserProfileView(userId: "user123", username: "johndoe")
    }
}

//
//  MessageRequestsView.swift
//  AMENAPP
//
//  Message Requests Inbox - Separate from main messages
//  First-message safety filter with hidden links/media
//

import SwiftUI
import Combine
import FirebaseAuth

struct MessageRequestsView: View {
    @ObservedObject private var trustService = TrustByDesignService.shared
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if trustService.messageRequests.isEmpty {
                    emptyStateView
                } else {
                    requestsList
                }
            }
            .navigationTitle("Message Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .task {
                await loadRequests()
            }
        }
    }
    
    private var requestsList: some View {
        List {
            ForEach(trustService.messageRequests) { request in
                ConversationRequestRow(conversation: request) { action in
                    handleRequestAction(request, action: action)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Message Requests")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("Messages from people you don't follow will appear here")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private func loadRequests() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await trustService.loadMessageRequests(userId: userId)
            isLoading = false
        } catch {
            dlog("❌ Error loading message requests: \(error)")
            isLoading = false
        }
    }
    
    private func handleRequestAction(_ request: Conversation, action: MessageRequestAction) {
        Task {
            // OPTIMISTIC UI UPDATE: Remove immediately
            await MainActor.run {
                trustService.messageRequests.removeAll { $0.id == request.id }
            }
            
            do {
                guard let conversationId = request.id,
                      let requesterId = request.requesterId else { return }
                
                switch action {
                case .accept:
                    try await trustService.acceptMessageRequest(conversationId)
                    // Haptic feedback on success
                    await MainActor.run {
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    }
                case .decline:
                    try await trustService.rejectMessageRequest(conversationId)
                    await MainActor.run {
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    }
                case .block:
                    try await trustService.rejectMessageRequest(conversationId)
                    guard let userId = Auth.auth().currentUser?.uid else { return }
                    try await trustService.performQuietBlock(
                        userId: userId,
                        targetUserId: requesterId,
                        action: .block,
                        reason: "Blocked from message request"
                    )
                    await MainActor.run {
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.warning)
                    }
                }
            } catch {
                dlog("❌ Error handling request: \(error)")
                // ROLLBACK: Re-add the request on error
                await MainActor.run {
                    trustService.messageRequests.append(request)
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Conversation Request Row

struct ConversationRequestRow: View {
    let conversation: Conversation
    let onAction: (MessageRequestAction) -> Void
    
    @State private var showActions = false
    @ObservedObject private var trustService = TrustByDesignService.shared
    @State private var settings: TrustPrivacySettings?
    @State private var currentUserId: String = Auth.auth().currentUser?.uid ?? ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                // Profile image
                if let imageURL = conversation.otherParticipantPhoto(currentUserId: currentUserId), !imageURL.isEmpty {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image.resizable()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(.gray)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.otherParticipantName(currentUserId: currentUserId))
                        .font(.custom("OpenSans-SemiBold", size: 16))
                    
                    Text(conversation.createdAt, style: .relative)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
            
            // Message preview (with safety filters)
            VStack(alignment: .leading, spacing: 8) {
                Text(filteredMessagePreview)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .lineLimit(3)
                
                // Safety warnings
                HStack(spacing: 8) {
                    let hasLinks = conversation.lastMessage.contains("http")
                    if hasLinks && (settings?.hideLinksInRequests ?? true) {
                        SafetyBadge(icon: "link", text: "Links hidden")
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onAction(.accept)
                } label: {
                    Text("Accept")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                
                Button {
                    showActions = true
                } label: {
                    Text("Decline")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 8)
        .confirmationDialog("Decline Request", isPresented: $showActions) {
            Button("Decline", role: .destructive) {
                onAction(.decline)
            }
            
            Button("Block User", role: .destructive) {
                onAction(.block)
            }
            
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("What would you like to do with this request?")
        }
        .task {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            do {
                try await trustService.loadPrivacySettings(userId: userId)
                settings = trustService.userSettings
            } catch {
                dlog("❌ Error loading settings: \(error)")
            }
        }
    }
    
    private var filteredMessagePreview: String {
        var preview = conversation.lastMessage
        
        // Hide links if setting enabled
        let hasLinks = preview.contains("http")
        if hasLinks && (settings?.hideLinksInRequests ?? true) {
            preview = preview.replacingOccurrences(
                of: "https?://[^\\s]+",
                with: "[Link hidden]",
                options: .regularExpression
            )
        }
        
        return preview
    }
}

struct SafetyBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.custom("OpenSans-Regular", size: 11))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }
}

enum MessageRequestAction {
    case accept
    case decline
    case block
}

#Preview {
    MessageRequestsView()
}

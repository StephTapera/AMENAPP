//
//  LiquidGlassChatView.swift
//  AMENAPP
//
//  Beautiful minimal chat with liquid glass message bubbles
//

import SwiftUI
import FirebaseAuth
import Combine

struct LiquidGlassChatView: View {
    let conversation: Conversation
    @StateObject private var viewModel: ChatViewModel
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    init(conversation: Conversation) {
        self.conversation = conversation
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversationId: conversation.id ?? ""))
    }
    
    var body: some View {
        chatContent
            .navigationTitle(conversationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadMessages()
            }
    }
    
    private var conversationTitle: String {
        return conversation.otherParticipantName(currentUserId: viewModel.currentUserId)
    }
    
    private var chatContent: some View {
        ZStack {
            // Clean background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                messagesList
                inputBar
            }
        }
    }
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        LiquidGlassMessageBubble(
                            message: message,
                            isFromCurrentUser: message.senderId == viewModel.currentUserId
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private var inputBar: some View {
        LiquidGlassInputBar(
            text: $messageText,
            isFocused: $isTextFieldFocused,
            onSend: sendMessage
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(UIColor.systemBackground)
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = viewModel.messages.last {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            await viewModel.sendMessage(text: messageText)
            messageText = ""
        }
    }
}

// MARK: - Liquid Glass Message Bubble

struct LiquidGlassMessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser { Spacer(minLength: 60) }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.content)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        liquidGlassBackground
                    )
                    .fixedSize(horizontal: false, vertical: true) // ✅ Prevent invalid sizing
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if !isFromCurrentUser { Spacer(minLength: 60) }
        }
        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading) // ✅ Ensure valid layout
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
    
    @ViewBuilder
    var liquidGlassBackground: some View {
        if isFromCurrentUser {
            // Sent message - Blue liquid glass
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.8),
                        Color.blue.opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Glass shine overlay
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.3),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                
                // Subtle inner glow
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.4),
                        Color.blue.opacity(0.2)
                    ],
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
            }
            .clipShape(LiquidGlassBubbleShape(isFromCurrentUser: true))
            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            .shadow(color: Color.blue.opacity(0.15), radius: 2, x: 0, y: 2)
            
        } else {
            // Received message - Frosted glass
            ZStack {
                // Frosted background
                Color.white.opacity(0.7)
                
                // Glass blur effect
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.gray.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Shine overlay
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.6),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
            .clipShape(LiquidGlassBubbleShape(isFromCurrentUser: false))
            .overlay(
                LiquidGlassBubbleShape(isFromCurrentUser: false)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.gray.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - Liquid Glass Bubble Shape

struct LiquidGlassBubbleShape: Shape {
    let isFromCurrentUser: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // ✅ Safety check: Ensure valid dimensions
        guard rect.width > 0, rect.height > 0,
              rect.width.isFinite, rect.height.isFinite else {
            return path
        }
        
        let cornerRadius: CGFloat = min(20, rect.width / 2, rect.height / 2)
        let tailSize: CGFloat = min(8, rect.width / 4, rect.height / 4)
        
        if isFromCurrentUser {
            // Right-aligned bubble with tail on bottom-right
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius - tailSize))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - tailSize, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY - tailSize)
            )
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        } else {
            // Left-aligned bubble with tail on bottom-left
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + tailSize, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius - tailSize),
                control: CGPoint(x: rect.minX, y: rect.maxY - tailSize)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Liquid Glass Input Bar

struct LiquidGlassInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Plus button (for attachments)
            Button {
                // Handle attachments
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Text input with liquid glass background
            HStack(spacing: 8) {
                TextField("Message", text: $text, axis: .vertical)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .focused(isFocused)
                    .lineLimit(1...4)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)
                
                // Voice input button
                if text.isEmpty {
                    Button {
                        // Handle voice input
                    } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .background(liquidGlassInputBackground)
            
            // Send button
            if !text.isEmpty {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text.isEmpty)
    }
    
    var liquidGlassInputBackground: some View {
        ZStack {
            // Base frosted layer
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.6))
            
            // Glass overlay
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.gray.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Shine effect
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Chat View Model

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    let currentUserId = Auth.auth().currentUser?.uid ?? ""
    let conversationId: String
    
    init(conversationId: String) {
        self.conversationId = conversationId
    }
    
    func loadMessages() async {
        // Load messages from Firebase
        // Implementation depends on your messaging service
    }
    
    func sendMessage(text: String) async {
        // Send message to Firebase
        // Implementation depends on your messaging service
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LiquidGlassChatView(
            conversation: Conversation(
                id: "preview",
                participants: ["user1", "user2"],
                participantNames: ["user2": "John Doe"],
                participantPhotos: [:],
                lastMessage: "Hello!",
                lastMessageSenderId: "user2",
                lastMessageTime: Date(),
                unreadCount: [:],
                archivedBy: [],
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
}

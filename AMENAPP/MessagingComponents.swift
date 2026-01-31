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
    
    // MARK: - Regular Message (Liquid Glass Pill Design - Black & White)
    
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
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // 🎨 Liquid Glass Pill Background
                Capsule()
                    .fill(.ultraThinMaterial)
                
                // Black & White gradient overlay
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: message.isFromCurrentUser ? [
                                Color.black.opacity(0.7),
                                Color.black.opacity(0.85)
                            ] : [
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Subtle shimmer edge highlight
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: message.isFromCurrentUser ? [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ] : [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(
            color: message.isFromCurrentUser 
                ? Color.black.opacity(0.3) 
                : Color.black.opacity(0.08),
            radius: 8,
            y: 3
        )
        .transition(.scale(scale: 0.8).combined(with: .opacity))
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
        .padding(10)
        .background(
            Capsule()
                .fill(message.isFromCurrentUser ? Color.white.opacity(0.15) : Color.black.opacity(0.05))
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

// MARK: - Modern Typing Indicator (Liquid Glass Pill Design)

struct ModernTypingIndicator: View {
    @State private var animationIndex = 0
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationIndex == index ? 1.3 : 0.9)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animationIndex
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // 🎨 Liquid Glass Pill Background
                Capsule()
                    .fill(.ultraThinMaterial)
                
                // White gradient overlay
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Subtle shimmer edge
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .onAppear {
            animationIndex = 1
        }
    }
}

// MARK: - Neumorphic Segmented Control

struct NeumorphicSegmentedControl: View {
    @Binding var selectedIndex: Int
    let options: [String]
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedIndex = index
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    ZStack {
                        if selectedIndex == index {
                            Capsule()
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 4, y: 4)
                                .shadow(color: .white.opacity(0.7), radius: 8, x: -4, y: -4)
                                .matchedGeometryEffect(id: "TAB", in: animation)
                        }
                        
                        Text(options[index])
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(selectedIndex == index ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemGray6),
                            Color(.systemGray5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Dia-Style Chat Input Bar

struct ModernChatInputBar: View {
    @Binding var messageText: String
    @FocusState var isInputFocused: Bool
    @Binding var selectedImages: [UIImage]
    let onSend: () -> Void
    let onPhotoPicker: () -> Void
    let onVoiceInput: (() -> Void)?
    
    @State private var isPressed = false
    @State private var showingFilePicker = false
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty
    }
    
    init(
        messageText: Binding<String>,
        isInputFocused: FocusState<Bool>,
        selectedImages: Binding<[UIImage]>,
        onSend: @escaping () -> Void,
        onPhotoPicker: @escaping () -> Void,
        onVoiceInput: (() -> Void)? = nil
    ) {
        self._messageText = messageText
        self._isInputFocused = isInputFocused
        self._selectedImages = selectedImages
        self.onSend = onSend
        self.onPhotoPicker = onPhotoPicker
        self.onVoiceInput = onVoiceInput
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Selected images/files preview
            if !selectedImages.isEmpty {
                selectedImagesPreview
            }
            
            // 🎨 Dia-Style Input Bar
            HStack(spacing: 12) {
                // Plus button (add files/tabs)
                Button(action: onPhotoPicker) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                
                // Main input field with glass effect
                HStack(spacing: 12) {
                    // Search/prompt icon
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    
                    TextField("Hey Dia...", text: $messageText, axis: .vertical)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.primary)
                        .focused($isInputFocused)
                        .lineLimit(1...5)
                        .tint(.primary)
                    
                    // Clear button when typing
                    if !messageText.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                messageText = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(diaInputGlassPill)
                
                // Voice/Send button
                Button(action: {
                    if canSend {
                        onSend()
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    } else if let voiceAction = onVoiceInput {
                        voiceAction()
                    }
                }) {
                    Image(systemName: canSend ? "arrow.up" : "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(
                                    canSend 
                                        ? Color.black 
                                        : Color.black.opacity(0.7)
                                )
                        )
                        .scaleEffect(isPressed ? 0.92 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            isPressed = true
                        }
                        .onEnded { _ in
                            isPressed = false
                        }
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                // Subtle frosted glass background
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.05),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
        }
    }
    
    // MARK: - Liquid Glass Components (Dia Style)
    
    /// Dia-style glass pill for text input
    private var diaInputGlassPill: some View {
        ZStack {
            // Base frosted glass
            Capsule()
                .fill(.ultraThinMaterial)
            
            // Subtle white gradient
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Soft border
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
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
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                            )
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                let _ = selectedImages.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .background(
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 18, height: 18)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        }
                        .padding(4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            Rectangle()
                .fill(Color(.systemBackground))
        )
    }
}

// MARK: - Dia-Style Chat View

struct DiaChatView: View {
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var selectedImages: [UIImage] = []
    @State private var showPhotoPicker = false
    @State private var messages: [AppMessage] = []
    
    let conversationTitle: String
    let conversationSubtitle: String?
    
    init(
        conversationTitle: String = "Dia",
        conversationSubtitle: String? = nil
    ) {
        self.conversationTitle = conversationTitle
        self.conversationSubtitle = conversationSubtitle
    }
    
    var body: some View {
        ZStack {
            // 🎨 Dia Gradient Background
            diaGradientBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom navigation bar
                diaNavigationBar
                
                // Messages scroll view
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            ModernMessageBubble(
                                message: message,
                                showAvatar: false,
                                showTimestamp: false,
                                showSenderName: false,
                                onReply: { },
                                onReact: { _ in }
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                
                // Input bar
                ModernChatInputBar(
                    messageText: $messageText,
                    isInputFocused: _isInputFocused,
                    selectedImages: $selectedImages,
                    onSend: sendMessage,
                    onPhotoPicker: { showPhotoPicker = true },
                    onVoiceInput: handleVoiceInput
                )
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            MessagingPhotoPickerView(selectedImages: $selectedImages)
        }
    }
    
    // MARK: - Dia Gradient Background
    
    private var diaGradientBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.85, green: 0.88, blue: 0.95), // Light lavender blue
                Color(red: 0.95, green: 0.92, blue: 0.98), // Soft purple tint
                Color(red: 1.0, green: 0.95, blue: 0.95),  // Pale pink
                Color(red: 0.98, green: 0.88, blue: 0.85)  // Peach bottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            // Subtle noise texture
            Color.white.opacity(0.05)
                .blendMode(.overlay)
        )
    }
    
    // MARK: - Navigation Bar
    
    private var diaNavigationBar: some View {
        HStack(spacing: 12) {
            // Back button
            Button {
                // Handle back action
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.5))
                            )
                    )
            }
            
            // Conversation info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 14))
                    
                    Text(conversationTitle)
                        .font(.custom("OpenSans-Bold", size: 17))
                }
                .foregroundStyle(.primary)
                
                if let subtitle = conversationSubtitle {
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Menu button
            Button {
                // Handle menu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.5))
                            )
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        // Create and send message
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            messageText = ""
            selectedImages.removeAll()
        }
    }
    
    private func handleVoiceInput() {
        // Handle voice input
        print("Voice input tapped")
    }
}

// MARK: - Dia-Style Action Button

struct DiaActionButton: View {
    let title: String
    let subtitle: String?
    let icon: String
    let action: () -> Void
    
    init(
        title: String,
        subtitle: String? = nil,
        icon: String = "arrow.right",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let subtitle = subtitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subtitle)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        Text(title)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.black)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                Color.white.opacity(0.6),
                                lineWidth: 0.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Dia Empty State View

struct DiaEmptyStateView: View {
    let title: String
    let subtitle: String
    let primaryButtonTitle: String
    let secondaryButtonTitle: String?
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?
    
    init(
        title: String = "Chat with your tabs",
        subtitle: String = "Early access for Arc Members",
        primaryButtonTitle: String = "Download Dia",
        secondaryButtonTitle: String? = "Join the waitlist →",
        onPrimaryAction: @escaping () -> Void,
        onSecondaryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.onPrimaryAction = onPrimaryAction
        self.onSecondaryAction = onSecondaryAction
    }
    
    var body: some View {
        ZStack {
            // Dia gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.88, blue: 0.95),
                    Color(red: 0.95, green: 0.92, blue: 0.98),
                    Color(red: 1.0, green: 0.95, blue: 0.95),
                    Color(red: 0.98, green: 0.88, blue: 0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Logo
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("Dia")
                        .font(.custom("OpenSans-Bold", size: 32))
                }
                .foregroundStyle(.primary)
                
                Spacer()
                    .frame(height: 80)
                
                // Main heading
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 48))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 40)
                
                // CTA Section
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        // Subtitle badge
                        Text(subtitle)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .fill(Color.white.opacity(0.4))
                                    )
                            )
                        
                        // Primary button
                        Button(action: onPrimaryAction) {
                            Text(primaryButtonTitle)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.black)
                                )
                        }
                    }
                    
                    // Secondary action
                    if let secondaryTitle = secondaryButtonTitle,
                       let secondaryAction = onSecondaryAction {
                        Button(action: secondaryAction) {
                            Text(secondaryTitle)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Demo input bar
                demoInputBar
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
    }
    
    private var demoInputBar: some View {
        HStack(spacing: 12) {
            // Plus button
            Button {} label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            
            // Input field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                
                Text("Hey Dia...")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Add tabs or files")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.white.opacity(0.6),
                                lineWidth: 0.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
            
            // Send button
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}

// MARK: - Preview

#Preview("Dia Chat View") {
    DiaChatView(
        conversationTitle: "Dia",
        conversationSubtitle: "Chat with your tabs"
    )
}

#Preview("Dia Empty State") {
    DiaEmptyStateView(
        onPrimaryAction: { },
        onSecondaryAction: { }
    )
}



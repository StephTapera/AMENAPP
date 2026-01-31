//
//  MessagesView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI
import PhotosUI
import Combine
import FirebaseAuth

// MARK: - Sheet Type Enum

enum MessageSheetType: Identifiable, Equatable {
    case chat(ChatConversation)
    case newMessage
    case createGroup
    case settings
    
    var id: String {
        switch self {
        case .chat(let conversation):
            return "chat_\(conversation.id)"
        case .newMessage:
            return "newMessage"
        case .createGroup:
            return "createGroup"
        case .settings:
            return "settings"
        }
    }
    
    static func == (lhs: MessageSheetType, rhs: MessageSheetType) -> Bool {
        lhs.id == rhs.id
    }
}

struct MessagesView: View {
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @StateObject private var messagingCoordinator = MessagingCoordinator.shared
    @State private var searchText = ""
    @State private var activeSheet: MessageSheetType?
    @State private var selectedTab: MessageTab = .messages
    @State private var messageRequests: [MessageRequest] = []
    @State private var showDeleteConfirmation = false
    @State private var conversationToDelete: ChatConversation?
    @State private var isArchiving = false
    @State private var isDeleting = false
    
    enum MessageTab {
        case messages
        case requests
        case archived
    }
    
    // Real conversations from Firebase
    private var conversations: [ChatConversation] {
        messagingService.conversations
    }
    
    var filteredConversations: [ChatConversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // Count of unread requests
    private var unreadRequestsCount: Int {
        messageRequests.filter { !$0.isRead }.count
    }
    
    var body: some View {
        NavigationStack {
            mainContentView
                .navigationBarHidden(true)
                .sheet(item: $activeSheet) { sheetType in
                    switch sheetType {
                    case .chat(let conversation):
                        ModernConversationDetailView(conversation: conversation)
                            .onAppear {
                                print("\n🎬 SHEET OPENED: Chat with \(conversation.name)")
                            }
                    
                    case .newMessage:
                        ProductionMessagingUserSearchView { selectedUser in
                            Task {
                                await startConversation(with: selectedUser)
                            }
                        }
                        .onAppear {
                            print("\n🎬 SHEET OPENED: New Message Search")
                        }
                    
                    case .createGroup:
                        CreateGroupView()
                            .onAppear {
                                print("\n🎬 SHEET OPENED: Create Group")
                            }
                    
                    case .settings:
                        MessageSettingsView()
                            .onAppear {
                                print("\n🎬 SHEET OPENED: Settings")
                            }
                    }
                }
                .onChange(of: activeSheet) { oldValue, newValue in
                    print("\n🔄 SHEET STATE CHANGED")
                    print("   - Old: \(oldValue?.id ?? "nil")")
                    print("   - New: \(newValue?.id ?? "nil")")
                }
                .modifier(LifecycleModifier(
                    messagingService: messagingService,
                    loadMessageRequests: loadMessageRequests,
                    startListeningToMessageRequests: startListeningToMessageRequests,
                    stopListeningToMessageRequests: stopListeningToMessageRequests
                ))
                .modifier(DeleteConfirmationModifier(
                    showDeleteConfirmation: $showDeleteConfirmation,
                    conversationToDelete: $conversationToDelete,
                    deleteConversation: deleteConversation
                ))
                .modifier(CoordinatorModifier(
                    messagingCoordinator: messagingCoordinator,
                    conversations: conversations,
                    activeSheet: $activeSheet,
                    selectedTab: $selectedTab
                ))
        }
    }
    
    // MARK: - Main Content View
    
    private var mainContentView: some View {
        ZStack {
            // Clean background consistent with app
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerSection
                tabContentSection
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            titleAndButtonsRow
            tabSelector
            NeumorphicMessagesSearchBar(text: $searchText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(Color(.systemGroupedBackground))
    }
    
    private var titleAndButtonsRow: some View {
        HStack {
            Text("Messages")
                .font(.custom("OpenSans-Bold", size: 32))
                .foregroundStyle(.primary)
            
            Spacer()
            
            headerActionButtons
        }
    }
    
    private var headerActionButtons: some View {
        HStack(spacing: 12) {
            // Single "Compose" button - industry standard (like iMessage, WhatsApp)
            Menu {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        activeSheet = .newMessage
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Label("New Message", systemImage: "bubble.left.and.bubble.right")
                }
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        activeSheet = .createGroup
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Label("New Group", systemImage: "person.3")
                }
                
                Divider()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        activeSheet = .settings
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                glassmorphicComposeButton
            }
        }
    }
    
    private var glassmorphicComposeButton: some View {
        SmartGlassmorphicButton(
            icon: "square.and.pencil",
            size: 44
        )
    }
    
    private var tabSelector: some View {
        NeomorphicSegmentedControl(
            selectedIndex: Binding(
                get: {
                    switch selectedTab {
                    case .messages: return 0
                    case .requests: return 1
                    case .archived: return 2
                    }
                },
                set: { newIndex in
                    switch newIndex {
                    case 0: selectedTab = .messages
                    case 1: selectedTab = .requests
                    case 2: selectedTab = .archived
                    default: selectedTab = .messages
                    }
                }
            ),
            options: ["Messages", "Requests", "Archived"]
        )
    }
    
    private func unreadBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.custom("OpenSans-Bold", size: 11))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.red)
            )
            .transition(.scale.combined(with: .opacity))
    }
    
    private func archivedBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.custom("OpenSans-Bold", size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.gray.opacity(0.2))
            )
            .transition(.scale.combined(with: .opacity))
    }
    
    private var tabContentSection: some View {
        TabView(selection: $selectedTab) {
            messagesContent
                .tag(MessageTab.messages)
            
            requestsContent
                .tag(MessageTab.requests)
            
            archivedContent
                .tag(MessageTab.archived)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
    
    // MARK: - Content Views
    
    private var messagesContent: some View {
        Group {
            if filteredConversations.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredConversations) { conversation in
                            Button {
                                print("\n========================================")
                                print("💬 EXISTING CONVERSATION TAPPED")
                                print("========================================")
                                print("   - Name: \(conversation.name)")
                                print("   - ID: \(conversation.id)")
                                print("   - Last Message: \(conversation.lastMessage)")
                                print("   - Is Group: \(conversation.isGroup)")
                                print("========================================")
                                
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                
                                activeSheet = .chat(conversation)
                                print("   - Set activeSheet to chat: \(conversation.name)")
                                print("========================================\n")
                            } label: {
                                NeumorphicConversationRow(conversation: conversation)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button {
                                    muteConversation(conversation)
                                } label: {
                                    Label("Mute", systemImage: "bell.slash")
                                }
                                
                                Button {
                                    pinConversation(conversation)
                                } label: {
                                    Label("Pin", systemImage: "pin")
                                }
                                
                                Divider()
                                
                                Button {
                                    archiveConversation(conversation)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                
                                Button(role: .destructive) {
                                    conversationToDelete = conversation
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await refreshConversations()
                }
            }
        }
    }
    
    private func refreshConversations() async {
        // Manually refresh conversations from Firebase
        do {
            print("🔄 Refreshing conversations...")
            
            // Stop current listener
            messagingService.stopListeningToConversations()
            
            // Small delay for better UX
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Restart listener to fetch fresh data
            messagingService.startListeningToConversations()
            
            // Haptic feedback
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
            
            print("✅ Conversations refreshed")
        }
    }
    
    // MARK: - Conversation Management
    
    @State private var isProcessing = false
    
    private func muteConversation(_ conversation: ChatConversation) {
        guard !isProcessing else { return }
        
        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }
            
            do {
                try await FirebaseMessagingService.shared.muteConversation(
                    conversationId: conversation.id,
                    muted: true
                )
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                print("🔕 Muted conversation: \(conversation.name)")
            } catch {
                print("❌ Error muting conversation: \(error)")
                // TODO: Show error to user
            }
        }
    }
    
    private func pinConversation(_ conversation: ChatConversation) {
        guard !isProcessing else { return }
        
        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }
            
            do {
                try await FirebaseMessagingService.shared.pinConversation(
                    conversationId: conversation.id,
                    pinned: true
                )
                
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                
                print("📌 Pinned conversation: \(conversation.name)")
            } catch {
                print("❌ Error pinning conversation: \(error)")
                // TODO: Show error to user
            }
        }
    }
    
    private func deleteConversation(_ conversation: ChatConversation) {
        guard !isDeleting else { return }
        
        Task { @MainActor in
            isDeleting = true
            defer { isDeleting = false }
            
            do {
                // Animate removal
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    // Will be removed from list automatically via Firebase listener
                }
                
                try await FirebaseMessagingService.shared.deleteConversation(
                    conversationId: conversation.id
                )
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                print("🗑️ Deleted conversation: \(conversation.name)")
            } catch {
                print("❌ Error deleting conversation: \(error)")
                // TODO: Show error to user
            }
        }
    }
    
    // MARK: - Archive Management
    
    private func archiveConversation(_ conversation: ChatConversation) {
        guard !isArchiving else { return }
        
        Task { @MainActor in
            isArchiving = true
            defer { isArchiving = false }
            
            do {
                // Animate archiving
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    // Will move to archived tab automatically via listener
                }
                
                try await FirebaseMessagingService.shared.archiveConversation(
                    conversationId: conversation.id
                )
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                print("📦 Archived conversation: \(conversation.name)")
            } catch {
                print("❌ Error archiving conversation: \(error)")
                // TODO: Show error to user
            }
        }
    }
    
    private func unarchiveConversation(_ conversation: ChatConversation) {
        Task { @MainActor in
            do {
                isArchiving = true
                defer { isArchiving = false }
                
                // Animate unarchiving
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    // Will move back to messages tab automatically via listener
                }
                
                try await FirebaseMessagingService.shared.unarchiveConversation(
                    conversationId: conversation.id
                )
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                print("📬 Unarchived conversation: \(conversation.name)")
            } catch {
                print("❌ Error unarchiving conversation: \(error)")
            }
        }
    }
    
    private var archivedContent: some View {
        Group {
            if messagingService.archivedConversations.isEmpty {
                archivedEmptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(messagingService.archivedConversations) { conversation in
                            Button {
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                activeSheet = .chat(conversation)
                            } label: {
                                NeumorphicConversationRow(conversation: conversation)
                                    .overlay(
                                        // Archive badge
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Image(systemName: "archivebox.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                                    .background(
                                                        Circle()
                                                            .fill(Color.gray.opacity(0.8))
                                                    )
                                                    .padding(8)
                                            }
                                            Spacer()
                                        }
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button {
                                    unarchiveConversation(conversation)
                                } label: {
                                    Label("Unarchive", systemImage: "arrow.up.bin")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    conversationToDelete = conversation
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete Forever", systemImage: "trash")
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
    }
    
    private var archivedEmptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 10, y: 10)
                    .shadow(color: .white.opacity(0.7), radius: 20, x: -10, y: -10)
                
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.gray, .gray.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No archived chats")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.primary)
                
                Text("Archived conversations will\nappear here for easy access")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
    }
    
    private var requestsContent: some View {
        Group {
            if messageRequests.isEmpty {
                requestsEmptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(messageRequests) { request in
                            MessageRequestRow(request: request) { action in
                                handleRequestAction(request: request, action: action)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
    }
    
    // MARK: - Request Management
    
    private func loadMessageRequests() async {
        // Load pending message requests from Firebase
        do {
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            
            let service = FirebaseMessagingService.shared
            let requests = try await service.loadMessageRequests()
            
            // Convert MessagingRequest to MessageRequest
            await MainActor.run {
                messageRequests = requests.map { req in
                    MessageRequest(
                        id: req.id,
                        conversationId: req.conversationId,
                        fromUserId: req.fromUserId,
                        fromUserName: req.fromUserName,
                        isRead: req.isRead
                    )
                }
            }
            
            print("✅ Loaded \(requests.count) message requests")
        } catch {
            print("❌ Error loading message requests: \(error)")
            messageRequests = []
        }
    }
    
    private func handleRequestAction(request: MessageRequest, action: RequestAction) {
        Task {
            do {
                switch action {
                case .accept:
                    try await acceptMessageRequest(request)
                case .decline:
                    try await declineMessageRequest(request)
                case .block:
                    try await blockUser(request.fromUserId)
                case .report:
                    try await reportUser(request.fromUserId)
                }
                await loadMessageRequests()
            } catch {
                print("❌ Error handling request action: \(error)")
            }
        }
    }
    
    private func acceptMessageRequest(_ request: MessageRequest) async throws {
        print("✅ Accepting message request from \(request.fromUserName)")
        
        let service = FirebaseMessagingService.shared
        
        // Update the conversation status to accepted (using existing method)
        try await service.acceptMessageRequest(requestId: request.conversationId)
        
        // Mark the request as read
        try await service.markMessageRequestAsRead(requestId: request.conversationId)
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
        
        print("✅ Message request accepted successfully")
    }
    
    private func declineMessageRequest(_ request: MessageRequest) async throws {
        print("❌ Declining message request from \(request.fromUserName)")
        
        let service = FirebaseMessagingService.shared
        
        // Delete the conversation (using existing method)
        try await service.declineMessageRequest(requestId: request.conversationId)
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
        }
        
        print("❌ Message request declined successfully")
    }
    
    private func blockUser(_ userId: String) async throws {
        print("🚫 Blocking user: \(userId)")
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessagesView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        // Block user using BlockService
        try await BlockService.shared.blockUser(userId: userId)
        
        // Remove all conversations with this user (explicit service reference)
        let messagingService = FirebaseMessagingService.shared
        try await messagingService.deleteConversationsWithUser(userId: userId)
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.error)
        
        print("🚫 User blocked successfully")
    }
    
    private func reportUser(_ userId: String) async throws {
        print("⚠️ Reporting user: \(userId)")
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessagesView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        // TODO: Implement reporting in FirebaseMessagingService. Previously attempted to call `reportSpam` which does not exist.
        // try await FirebaseMessagingService.shared.reportSpam(
        //     reporterId: currentUserId,
        //     reportedUserId: userId,
        //     reason: "Spam or inappropriate message request"
        // )
        print("[Report] User \(userId) reported by \(currentUserId) for spam (placeholder)")
        
        // Also decline the request
        if let request = messageRequests.first(where: { $0.fromUserId == userId }) {
            try await declineMessageRequest(request)
        }
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
        
        print("⚠️ User reported successfully")
    }
    
    // MARK: - Real-time Message Request Listening
    
    @State private var messageRequestsListener: (() -> Void)?
    
    private func startListeningToMessageRequests() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        messageRequestsListener = FirebaseMessagingService.shared.startListeningToMessageRequests(
            userId: currentUserId
        ) { requests in
            Task { @MainActor in
                messageRequests = requests.map { req in
                    MessageRequest(
                        id: req.id,
                        conversationId: req.conversationId,
                        fromUserId: req.fromUserId,
                        fromUserName: req.fromUserName,
                        isRead: req.isRead
                    )
                }
                print("📬 Updated message requests: \(requests.count) pending")
            }
        }
    }
    
    private func stopListeningToMessageRequests() {
        messageRequestsListener?()
        messageRequestsListener = nil
    }
    
    private var requestsEmptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 10, y: 10)
                    .shadow(color: .white.opacity(0.7), radius: 20, x: -10, y: -10)
                
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No message requests")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.primary)
                
                Text("When someone you don't follow\nmessages you, it'll appear here")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Helper Functions
    
    /// Start a new conversation with a selected user
    private func startConversation(with user: SearchableUser) async {
        print("\n========================================")
        print("🚀 START CONVERSATION DEBUG")
        print("========================================")
        print("👤 User: \(user.displayName)")
        print("🆔 User ID: \(user.id)")
        print("📧 Username: \(user.username ?? "none")")
        print("========================================\n")
        
        do {
            print("📞 Step 1: Calling getOrCreateDirectConversation...")
            print("   - Target User ID: \(user.id)")
            print("   - Target User Name: \(user.displayName)")
            
            let conversationId = try await messagingService.getOrCreateDirectConversation(
                withUserId: user.id,
                userName: user.displayName
            )
            
            print("✅ Step 2: Got conversation ID: \(conversationId)")
            print("📋 Step 3: Current conversations count: \(conversations.count)")
            
            // Dismiss the search sheet
            await MainActor.run {
                print("🚪 Step 4: Dismissing search sheet...")
                activeSheet = nil
            }
            
            // Small delay for sheet dismissal
            print("⏳ Step 5: Waiting for sheet dismissal...")
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Check if conversation exists in list
            print("🔍 Step 6: Searching for conversation in list...")
            print("   - Looking for ID: \(conversationId)")
            print("   - Available conversations:")
            for (index, conv) in conversations.enumerated() {
                print("     [\(index)] ID: \(conv.id), Name: \(conv.name)")
            }
            
            if let conversation = conversations.first(where: { $0.id == conversationId }) {
                print("✅ Step 7a: Found existing conversation in list")
                print("   - Conversation Name: \(conversation.name)")
                print("   - Last Message: \(conversation.lastMessage)")
                
                await MainActor.run {
                    activeSheet = .chat(conversation)
                    print("   - Set activeSheet to chat: \(conversation.name)")
                }
            } else {
                print("⚠️ Step 7b: Conversation NOT found in list, creating temporary one")
                // Create temporary conversation to open immediately
                await MainActor.run {
                    let tempConversation = ChatConversation(
                        id: conversationId,
                        name: user.displayName,
                        lastMessage: "",
                        timestamp: "Just now",
                        isGroup: false,
                        unreadCount: 0,
                        avatarColor: .blue
                    )
                    
                    print("📝 Created temp conversation:")
                    print("   - ID: \(tempConversation.id)")
                    print("   - Name: \(tempConversation.name)")
                    
                    activeSheet = .chat(tempConversation)
                    print("   - Set activeSheet to chat: \(tempConversation.name)")
                }
            }
            
            // Haptic feedback
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
            
            print("\n========================================")
            print("✅ CONVERSATION START COMPLETE")
            print("   - Conversation ID: \(conversationId)")
            print("   - Active Sheet: \(activeSheet?.id ?? "nil")")
            print("========================================\n")
            
        } catch {
            print("\n========================================")
            print("❌ CONVERSATION START FAILED")
            print("========================================")
            print("Error: \(error)")
            print("Error type: \(type(of: error))")
            print("Error description: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain)")
                print("Error code: \(nsError.code)")
                print("Error userInfo: \(nsError.userInfo)")
            }
            print("========================================\n")
            
            // Show error to user
            await MainActor.run {
                activeSheet = nil
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
                
                // TODO: Show error alert to user
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 10, y: 10)
                    .shadow(color: .white.opacity(0.7), radius: 20, x: -10, y: -10)
                
                Image(systemName: "message.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No messages yet")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.primary)
                
                Text("Start a conversation with\nyour faith community")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                activeSheet = .newMessage
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New Message")
                }
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
                )
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
}

// MARK: - Neumorphic Messages Search Bar

struct NeumorphicMessagesSearchBar: View {
    @Binding var text: String
    @State private var isSearching = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Glassmorphic search icon with animation
            SmartGlassmorphicButton(
                icon: "magnifyingglass",
                size: 36,
                iconSize: 15,
                isActive: isSearching
            )
            
            TextField("Search conversations", text: $text)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.primary)
                .submitLabel(.search)
                .onChange(of: text) { _, newValue in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isSearching = !newValue.isEmpty
                    }
                }
            
            if !text.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        text = ""
                        isSearching = false
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    SmartGlassmorphicButton(
                        icon: "xmark",
                        size: 28,
                        iconSize: 10
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Glassmorphic background
                Capsule()
                    .fill(.ultraThinMaterial)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
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
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: isSearching ? .blue.opacity(0.2) : .black.opacity(0.08), radius: 12, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSearching)
    }
}

// MARK: - Smart Glassmorphic Button with Animations

struct SmartGlassmorphicButton: View {
    let icon: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 18
    var isActive: Bool = false
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            // Glassmorphic background
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.35 : 0.25),
                            Color.white.opacity(isActive ? 0.15 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            // Active state glow
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )
                    .frame(width: size, height: size)
                    .blur(radius: 4)
            }
            
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.7 : 0.5),
                            Color.white.opacity(isActive ? 0.4 : 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: size, height: size)
            
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isActive ? .blue : .primary)
                .symbolEffect(.bounce, value: isPressed)
        }
        .shadow(color: isActive ? .blue.opacity(0.2) : .black.opacity(0.1), radius: 8, y: 4)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - Neumorphic Conversation Row

struct NeumorphicConversationRow: View {
    let conversation: ChatConversation
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar with glassmorphic style
            ZStack {
                // Outer glow for unread
                if conversation.unreadCount > 0 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.blue.opacity(0.3),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                        .frame(width: 70, height: 70)
                        .blur(radius: 8)
                }
                
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                conversation.avatarColor.opacity(0.3),
                                conversation.avatarColor.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 56, height: 56)
                
                if conversation.isGroup {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(conversation.avatarColor)
                        .symbolEffect(.bounce, value: isPressed)
                } else {
                    Text(conversation.initials)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(conversation.avatarColor)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(conversation.name)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(conversation.timestamp)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(conversation.lastMessage)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.custom("OpenSans-Bold", size: 11))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, 6)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    Capsule()
                                        .strokeBorder(
                                            Color.white.opacity(0.3),
                                            lineWidth: 1
                                        )
                                }
                            )
                            .shadow(color: .blue.opacity(0.4), radius: 6, y: 3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                // Glassmorphic background
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: conversation.unreadCount > 0 ? .blue.opacity(0.15) : .black.opacity(0.08), radius: 12, y: 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: conversation.unreadCount)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Modern Conversation Row (Frosted Glass Design)

struct ModernConversationRow: View {
    let conversation: ChatConversation
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar with soft shadow
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                conversation.avatarColor.opacity(0.3),
                                conversation.avatarColor.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: conversation.avatarColor.opacity(0.3), radius: 8, y: 4)
                
                if conversation.isGroup {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(conversation.avatarColor)
                } else {
                    Text(conversation.initials)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(conversation.avatarColor)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(conversation.name)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(conversation.timestamp)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                HStack {
                    Text(conversation.lastMessage)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.black.opacity(0.6))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.custom("OpenSans-Bold", size: 11))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, 6)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.blue.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .blue.opacity(0.4), radius: 4, y: 2)
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                // Frosted glass effect
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: ChatConversation
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(conversation.avatarColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                if conversation.isGroup {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(conversation.avatarColor)
                } else {
                    Text(conversation.initials)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(conversation.avatarColor)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(conversation.name)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(conversation.timestamp)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(conversation.lastMessage)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.custom("OpenSans-Bold", size: 11))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, 6)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
    }
}

// MARK: - Conversation Model
// Note: Conversation model is defined in Conversation.swift

// MARK: - TEMPORARY STUBS (Remove when MessagingPlaceholders.swift is fixed)

// MessageRequest is now defined in MessageModels.swift

enum RequestAction {
    case accept
    case decline
    case block
    case report
}

struct MessageRequestRow: View {
    let request: MessageRequest
    let onAction: (RequestAction) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.fromUserName)
                    .font(.headline)
                Text("sent you a message request")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { onAction(.accept) }) {
                    Text("Accept")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                Button(action: { onAction(.decline) }) {
                    Text("Decline")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }
}

// MARK: - Production-Ready Create Group View

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var messagingService = FirebaseMessagingService.shared
    
    @State private var groupName = ""
    @State private var selectedUsers: [ContactUser] = [] // Store full user objects
    @State private var searchText = ""
    @State private var searchResults: [ContactUser] = []
    @State private var isSearching = false
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasSearched = false
    
    // Search management
    @State private var searchTask: Task<Void, Never>?
    
    // Character limits
    private let nameCharLimit = 50
    private let minMembers = 1
    private let maxMembers = 50
    
    var canCreate: Bool {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidName = !trimmedName.isEmpty
        let hasEnoughMembers = selectedUsers.count >= minMembers
        let notTooManyMembers = selectedUsers.count <= maxMembers
        let notBusy = !isCreating
        
        return hasValidName && hasEnoughMembers && notTooManyMembers && notBusy
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                groupNameSection
                
                Divider()
                
                memberSelectionSection
                
                selectedUsersSection
                
                searchResultsSection
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createGroup()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .alert("Error Creating Group", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onDisappear {
                // Clean up search resources
                searchTask?.cancel()
            }
        }
    }
    
    // MARK: - View Components
    
    private var groupNameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group Name")
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(.secondary)
            
            TextField("Enter group name", text: $groupName)
                .font(.custom("OpenSans-Regular", size: 17))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .onSubmit {
                    // Enforce character limit on submit
                    if groupName.count > nameCharLimit {
                        groupName = String(groupName.prefix(nameCharLimit))
                    }
                }
                .onReceive(Just(groupName)) { newValue in
                    // Enforce character limit in real-time
                    if newValue.count > nameCharLimit {
                        groupName = String(newValue.prefix(nameCharLimit))
                    }
                }
            
            Text("\(groupName.count)/\(nameCharLimit)")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    private var memberSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add Members")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(selectedUsers.count)/\(maxMembers)")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            searchBar
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search people", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task {
                        await performSearch()
                    }
                }
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        searchResults = []
                        hasSearched = false
                        searchTask?.cancel()
                    } else {
                        // Debounced search
                        searchTask?.cancel()
                        searchTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
                                if !Task.isCancelled {
                                    await performSearch()
                                }
                            } catch {
                                // Task was cancelled
                            }
                        }
                    }
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var selectedUsersSection: some View {
        Group {
            if !selectedUsers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected (\(selectedUsers.count))")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedUsers, id: \.id) { user in
                                SelectedUserChip(user: user, onRemove: {
                                    removeUser(user)
                                })
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }
    
    private func removeUser(_ user: ContactUser) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedUsers.removeAll { $0.id == user.id }
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    @ViewBuilder
    private var searchResultsSection: some View {
        if !searchText.isEmpty {
            if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching...")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else if hasSearched && searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    
                    Text("No users found")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text("Try a different search term")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else if !searchResults.isEmpty {
                List {
                    ForEach(searchResults, id: \.id) { user in
                        Button {
                            toggleUserSelection(user)
                        } label: {
                            userRow(for: user)
                        }
                        .disabled(selectedUsers.count >= maxMembers && !isUserSelected(user))
                    }
                }
                .listStyle(.plain)
            }
        } else {
            emptySearchState
        }
    }
    
    private func isUserSelected(_ user: ContactUser) -> Bool {
        selectedUsers.contains { $0.id == user.id }
    }
    
    private func userRow(for user: ContactUser) -> some View {
        HStack(spacing: 12) {
            // Avatar
            if let profileImageURL = user.profileImageURL, let url = URL(string: profileImageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(user.displayName.prefix(2).uppercased())
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.blue)
                        )
                }
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(user.displayName.prefix(2).uppercased())
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.blue)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isUserSelected(user) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
            } else if selectedUsers.count >= maxMembers {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary.opacity(0.3))
            }
        }
        .contentShape(Rectangle())
    }
    
    private var emptySearchState: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                Image(systemName: "person.3")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
                
                Text("Search to add members")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() async {
        guard !searchText.isEmpty, searchText.count >= 2 else {
            searchResults = []
            hasSearched = false
            return
        }
        
        isSearching = true
        hasSearched = true
        
        do {
            print("🔍 Searching for users with query: '\(searchText)'")
            let users = try await messagingService.searchUsers(query: searchText)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                print("✅ Found \(users.count) users")
                searchResults = users
                isSearching = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            
            print("❌ Error searching users: \(error)")
            await MainActor.run {
                searchResults = []
                isSearching = false
                errorMessage = "Failed to search users. Please try again."
            }
        }
    }
    
    private func toggleUserSelection(_ user: ContactUser) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let index = selectedUsers.firstIndex(where: { $0.id == user.id }) {
                selectedUsers.remove(at: index)
            } else if selectedUsers.count < maxMembers {
                selectedUsers.append(user)
            }
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func createGroup() {
        guard canCreate else { return }
        
        isCreating = true
        
        Task {
            do {
                let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Gather participant IDs and names
                let participantIds = selectedUsers.compactMap { $0.id }
                var participantNames: [String: String] = [:]
                
                for user in selectedUsers {
                    if let userId = user.id {
                        participantNames[userId] = user.displayName
                    }
                }
                
                print("🎨 Creating group:")
                print("   - Name: \(trimmedName)")
                print("   - Participants: \(participantIds.count)")
                print("   - Participant Names: \(participantNames)")
                
                // Create group conversation
                let conversationId = try await messagingService.createGroupConversation(
                    participantIds: participantIds,
                    participantNames: participantNames,
                    groupName: trimmedName
                )
                
                print("✅ Group created with ID: \(conversationId)")
                
                await MainActor.run {
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    isCreating = false
                    dismiss()
                    
                    // Open the new group conversation after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        MessagingCoordinator.shared.openConversation(conversationId)
                    }
                }
                
            } catch {
                print("❌ Error creating group: \(error)")
                
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isCreating = false
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Selected User Chip

struct SelectedUserChip: View {
    let user: ContactUser
    let onRemove: () -> Void
    
    private var initials: String {
        let components = user.displayName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan, .red, .indigo]
        let hash = abs(user.displayName.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Avatar
            if let profileImageURL = user.profileImageURL, let url = URL(string: profileImageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(avatarColor.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(initials)
                                .font(.custom("OpenSans-Bold", size: 10))
                                .foregroundStyle(avatarColor)
                        )
                }
            } else {
                Circle()
                    .fill(avatarColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(initials)
                            .font(.custom("OpenSans-Bold", size: 10))
                            .foregroundStyle(avatarColor)
                    )
            }
            
            Text(user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.systemGray6))
        )
    }
}

struct MessageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("muteUnknownSenders") private var muteUnknownSenders = false
    @AppStorage("allowReadReceipts") private var allowReadReceipts = true
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Mute Unknown Senders", isOn: $muteUnknownSenders)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Automatically mute message requests from people you don't follow")
                }
                
                Section {
                    Toggle("Allow Read Receipts", isOn: $allowReadReceipts)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Let people see when you've read their messages")
                }
                
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("Some features are temporarily unavailable during updates")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Message Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Production-Ready User Search View

struct ProductionMessagingUserSearchView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var searchResults: [SearchableUser] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    
    let onUserSelected: (SearchableUser) -> Void
    
    private let messagingService = FirebaseMessagingService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBar
                    .padding()
                    .background(Color(.systemGroupedBackground))
                
                // Results
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    errorView(error)
                } else if searchText.isEmpty {
                    emptySearchView
                } else if searchResults.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        searchTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 4, y: 4)
                    .shadow(color: .white.opacity(0.8), radius: 8, x: -4, y: -4)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            
            TextField("Search by name or username", text: $searchText)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }
            
            if !searchText.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        searchText = ""
                        searchResults = []
                        errorMessage = nil
                        searchTask?.cancel()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty && newValue.count >= 2 {
                // Debounce search
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    if !Task.isCancelled && searchText == newValue {
                        performSearch()
                    }
                }
            } else {
                searchResults = []
                errorMessage = nil
            }
        }
    }
    
    // MARK: - Views
    
    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
            }
            
            VStack(spacing: 8) {
                Text("Search for people")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)
                
                Text("Start typing to find someone\nto message")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.gray)
            
            VStack(spacing: 8) {
                Text("No users found")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                
                Text("Try a different name or username")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            
            Text(message)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                performSearch()
            } label: {
                Text("Try Again")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.blue))
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { user in
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        
                        print("\n========================================")
                        print("👤 USER SELECTED FROM SEARCH")
                        print("========================================")
                        print("   - Name: \(user.displayName)")
                        print("   - ID: \(user.id)")
                        print("   - Username: \(user.username ?? "none")")
                        print("========================================\n")
                        
                        onUserSelected(user)
                    } label: {
                        ProductionUserRow(user: user)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if user.id != searchResults.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        guard !searchText.isEmpty, searchText.count >= 2 else {
            searchResults = []
            return
        }
        
        searchTask?.cancel()
        isSearching = true
        errorMessage = nil
        
        searchTask = Task {
            do {
                print("🔍 Searching for users with query: '\(searchText)'")
                
                let users = try await messagingService.searchUsers(query: searchText)
                
                guard !Task.isCancelled else {
                    print("⚠️ Search cancelled")
                    return
                }
                
                // Convert ContactUser to SearchableUser
                await MainActor.run {
                    searchResults = users.map { SearchableUser(from: $0) }
                    isSearching = false
                    
                    print("✅ Found \(users.count) users")
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    print("❌ Search error: \(error)")
                    errorMessage = "Unable to search users. Please check your connection."
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
}

// MARK: - Production User Row

struct ProductionUserRow: View {
    let user: SearchableUser
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(user.avatarColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } placeholder: {
                        Text(user.initials)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(user.avatarColor)
                    }
                } else {
                    Text(user.initials)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(user.avatarColor)
                }
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                if let username = user.username {
                    Text("@\(username)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Message indicator
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - END TEMPORARY STUBS

// MARK: - View Modifiers to Break Down Complexity

struct LifecycleModifier: ViewModifier {
    let messagingService: FirebaseMessagingService
    let loadMessageRequests: () async -> Void
    let startListeningToMessageRequests: () -> Void
    let stopListeningToMessageRequests: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Start listening to real-time conversations from Firebase
                messagingService.startListeningToConversations()
                messagingService.startListeningToArchivedConversations()
                
                // Fetch and cache current user's name for messaging
                Task {
                    await messagingService.fetchAndCacheCurrentUserName()
                    await loadMessageRequests()
                    
                    // Start listening for real-time message requests
                    startListeningToMessageRequests()
                }
            }
            .onDisappear {
                // Stop listening when view disappears
                messagingService.stopListeningToConversations()
                messagingService.stopListeningToArchivedConversations()
                stopListeningToMessageRequests()
            }
    }
}

struct DeleteConfirmationModifier: ViewModifier {
    @Binding var showDeleteConfirmation: Bool
    @Binding var conversationToDelete: ChatConversation?
    let deleteConversation: (ChatConversation) -> Void
    
    func body(content: Content) -> some View {
        content
            .alert("Delete Conversation", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let conversation = conversationToDelete {
                        deleteConversation(conversation)
                    }
                }
            } message: {
                Text("Are you sure you want to delete this conversation? This action cannot be undone.")
            }
    }
}

struct CoordinatorModifier: ViewModifier {
    let messagingCoordinator: MessagingCoordinator
    let conversations: [ChatConversation]
    @Binding var activeSheet: MessageSheetType?
    @Binding var selectedTab: MessagesView.MessageTab
    
    func body(content: Content) -> some View {
        content
            .onReceive(messagingCoordinator.$conversationToOpen) { conversationId in
                // Handle opening a specific conversation from coordinator
                guard let conversationId = conversationId else { return }
                
                // Find the conversation in our list
                if let conversation = conversations.first(where: { $0.id == conversationId }) {
                    activeSheet = .chat(conversation)
                } else {
                    // Conversation might not be loaded yet, fetch it
                    Task {
                        // Give Firebase a moment to sync
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if let conversation = conversations.first(where: { $0.id == conversationId }) {
                            await MainActor.run {
                                activeSheet = .chat(conversation)
                            }
                        }
                    }
                }
            }
            .onReceive(messagingCoordinator.$shouldOpenMessageRequests) { shouldOpen in
                // Switch to requests tab when coordinator signals
                if shouldOpen {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = .requests
                    }
                }
            }
    }
}

// MARK: - Modern Conversation Detail View

struct ModernConversationDetailView: View {
    @Environment(\.dismiss) var dismiss
    let conversation: ChatConversation
    @State private var messageText = ""
    @State private var messages: [AppMessage] = []
    @FocusState private var isInputFocused: Bool
    @State private var selectedImages: [UIImage] = []
    @State private var showingPhotoPicker = false
    @State private var isRecording = false
    @State private var showingMessageOptions = false
    @State private var selectedMessage: AppMessage?
    @State private var replyingTo: AppMessage?
    @State private var isTyping = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    // Typing debounce timer
    @State private var typingDebounceTimer: Timer?
    
    var body: some View {
        ZStack {
            // 🎨 Beautiful Gradient Background (like Apple's design)
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.15, blue: 0.25),  // Deep blue-gray
                    Color(red: 0.15, green: 0.12, blue: 0.2),  // Purple-gray
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Modern Header
                modernConversationHeader
                
                // Messages
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                ModernMessageBubble(
                                    message: message,
                                    onReply: {
                                        replyingTo = message
                                        isInputFocused = true
                                    },
                                    onReact: { emoji in
                                        addReaction(to: message, emoji: emoji)
                                    }
                                )
                                .id(message.id)
                            }
                            
                            // Typing indicator
                            if isTyping {
                                ModernTypingIndicator()
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding()
                        .padding(.bottom, 100)
                    }
                    .onAppear {
                        scrollProxy = proxy
                    }
                    .onReceive(Just(messages.count)) { _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 0)
            }
            
            // Floating input bar with liquid glass
            VStack {
                Spacer()
                
                ModernChatInputBar(
                    messageText: $messageText,
                    isInputFocused: _isInputFocused,
                    selectedImages: $selectedImages,
                    onSend: { sendMessage() },
                    onPhotoPicker: { showingPhotoPicker = true }
                )
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingPhotoPicker) {
            MessagingPhotoPickerView(selectedImages: $selectedImages)
        }
        .alert("Message Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadSampleMessages()
            simulateTyping()
        }
        .onDisappear {
            // Clean up listeners to prevent memory leaks
            // Call Firebase service's stop methods
            FirebaseMessagingService.shared.stopListeningToMessages(conversationId: conversation.id)
            
            // Cancel typing debounce timer
            typingDebounceTimer?.invalidate()
            typingDebounceTimer = nil
            
            // Send typing stopped status
            Task {
                try? await FirebaseMessagingService.shared.updateTypingStatus(
                    conversationId: conversation.id,
                    isTyping: false
                )
            }
        }
        .onReceive(Just(messageText)) { newValue in
            handleTypingIndicator(isTyping: !newValue.isEmpty)
        }
    }
    
    // MARK: - Modern Header (Liquid Glass Design)
    
    private var modernConversationHeader: some View {
        HStack(spacing: 12) {
            backButton
            conversationAvatar
            conversationTitle
            Spacer()
            moreOptionsButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Frosted glass background
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                // Gradient overlay
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Bottom border
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 0.5)
                }
            }
        )
    }
    
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(liquidGlassCircleSmall)
        }
    }
    
    private var conversationAvatar: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 42, height: 42)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)
            
            if conversation.isGroup {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text(conversation.initials)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.white)
            }
        }
        .overlay(
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private var conversationTitle: some View {
        Text(conversation.name)
            .font(.custom("OpenSans-Bold", size: 18))
            .foregroundStyle(.white)
    }
    
    private var moreOptionsButton: some View {
        Button {
            // More options
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(liquidGlassCircleSmall)
        }
    }
    
    /// Small liquid glass circle for header buttons
    private var liquidGlassCircleSmall: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
    
    // MARK: - Message Actions
    
    private func loadSampleMessages() {
        // Load real messages from Firebase
        let conversationId = conversation.id
        
        // Store the listener cleanup closure if the method returns one
        // If startListeningToMessages doesn't return a cleanup closure, we'll call stopListeningToMessages in onDisappear
        FirebaseMessagingService.shared.startListeningToMessages(
            conversationId: conversationId
        ) { newMessages in
            messages = newMessages
            
            // Mark unread messages as read
            let unreadMessageIds = newMessages.filter { !$0.isRead && !$0.isFromCurrentUser }.map { $0.id }
            if !unreadMessageIds.isEmpty {
                Task {
                    try? await FirebaseMessagingService.shared.markMessagesAsRead(
                        conversationId: conversationId,
                        messageIds: unreadMessageIds
                    )
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty else { return }
        
        let textToSend = messageText
        let imagesToSend = selectedImages
        let replyToId = replyingTo?.id
        
        // Clear input immediately for better UX
        messageText = ""
        selectedImages = []
        replyingTo = nil
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Send to Firebase
        Task {
            do {
                if imagesToSend.isEmpty {
                    try await FirebaseMessagingService.shared.sendMessage(
                        conversationId: conversation.id,
                        text: textToSend,
                        replyToMessageId: replyToId
                    )
                } else {
                    try await FirebaseMessagingService.shared.sendMessageWithPhotos(
                        conversationId: conversation.id,
                        text: textToSend,
                        images: imagesToSend
                    )
                }
            } catch {
                print("❌ Error sending message: \(error)")
                // Show error to user
                await MainActor.run {
                    errorMessage = "Failed to send message. Please check your connection and try again."
                    showErrorAlert = true
                    
                    // Restore message text if send failed
                    messageText = textToSend
                    selectedImages = imagesToSend
                    
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func simulateResponse() {
        // Remove this function - responses will come from real users via Firebase
    }
    
    private func simulateTyping() {
        // Real typing indicators will come from Firebase
        let conversationId = conversation.id
        
        // Store the listener cleanup closure if the method returns one
        FirebaseMessagingService.shared.startListeningToTyping(
            conversationId: conversationId,
            onUpdate: { typingUsers in
                isTyping = !typingUsers.isEmpty
            }
        )
    }
    
    private func handleTypingIndicator(isTyping: Bool) {
        // Cancel previous debounce timer
        typingDebounceTimer?.invalidate()
        
        if isTyping {
            // Send typing started
            Task {
                try? await FirebaseMessagingService.shared.updateTypingStatus(
                    conversationId: conversation.id,
                    isTyping: true
                )
            }
            
            // Auto-stop typing after 5 seconds of no new input
            let conversationId = conversation.id
            typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                Task { @MainActor in
                    try? await FirebaseMessagingService.shared.updateTypingStatus(
                        conversationId: conversationId,
                        isTyping: false
                    )
                }
            }
        } else {
            // Send typing stopped immediately
            Task {
                try? await FirebaseMessagingService.shared.updateTypingStatus(
                    conversationId: conversation.id,
                    isTyping: false
                )
            }
        }
    }
    
    private func addReaction(to message: AppMessage, emoji: String) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Add reaction to Firebase
        Task {
            do {
                try await FirebaseMessagingService.shared.addReaction(
                    conversationId: conversation.id,
                    messageId: message.id,
                    emoji: emoji
                )
            } catch {
                print("❌ Error adding reaction: \(error)")
                errorMessage = "Failed to add reaction."
                showErrorAlert = true
            }
        }
    }
}


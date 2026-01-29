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

struct MessagesView: View {
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @StateObject private var messagingCoordinator = MessagingCoordinator.shared
    @State private var searchText = ""
    @State private var selectedConversation: ChatConversation?
    @State private var showNewMessage = false
    @State private var showCreateGroup = false
    @State private var showChatView = false
    @State private var selectedTab: MessageTab = .messages
    @State private var messageRequests: [MessageRequest] = []
    @State private var archivedConversations: [ChatConversation] = []
    @State private var showSettings = false
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
            ZStack {
                // Clean background consistent with app
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with neumorphic design
                    VStack(spacing: 16) {
                        // Title and buttons
                        HStack {
                            Text("Messages")
                                .font(.custom("OpenSans-Bold", size: 32))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                // Settings button
                                Button {
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                    showSettings = true
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(.systemBackground))
                                            .frame(width: 44, height: 44)
                                            .shadow(color: .black.opacity(0.15), radius: 8, x: 4, y: 4)
                                            .shadow(color: .white.opacity(0.7), radius: 8, x: -4, y: -4)
                                        
                                        Image(systemName: "gearshape.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.primary)
                                    }
                                }
                                
                                // New group button - neumorphic
                                Button {
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                    showCreateGroup = true
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(.systemBackground))
                                            .frame(width: 44, height: 44)
                                            .shadow(color: .black.opacity(0.15), radius: 8, x: 4, y: 4)
                                            .shadow(color: .white.opacity(0.7), radius: 8, x: -4, y: -4)
                                        
                                        Image(systemName: "person.3.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.primary)
                                    }
                                }
                                
                                // New message button - neumorphic
                                Button {
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                    showNewMessage = true
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(.systemBackground))
                                            .frame(width: 44, height: 44)
                                            .shadow(color: .black.opacity(0.15), radius: 8, x: 4, y: 4)
                                            .shadow(color: .white.opacity(0.7), radius: 8, x: -4, y: -4)
                                        
                                        Image(systemName: "square.and.pencil")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                        
                        // Tab Selector
                        HStack(spacing: 16) {
                            // Messages Tab
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = .messages
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Text("Messages")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                        .foregroundStyle(selectedTab == .messages ? .primary : .secondary)
                                    
                                    if selectedTab == .messages {
                                        Capsule()
                                            .fill(Color.blue)
                                            .frame(height: 3)
                                            .transition(.scale.combined(with: .opacity))
                                    } else {
                                        Capsule()
                                            .fill(Color.clear)
                                            .frame(height: 3)
                                    }
                                }
                            }
                            
                            // Requests Tab
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = .requests
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    VStack(spacing: 8) {
                                        HStack(spacing: 6) {
                                            Text("Requests")
                                                .font(.custom("OpenSans-Bold", size: 16))
                                                .foregroundStyle(selectedTab == .requests ? .primary : .secondary)
                                            
                                            if unreadRequestsCount > 0 {
                                                Text("\(unreadRequestsCount)")
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
                                        }
                                        
                                        if selectedTab == .requests {
                                            Capsule()
                                                .fill(Color.blue)
                                                .frame(height: 3)
                                                .transition(.scale.combined(with: .opacity))
                                        } else {
                                            Capsule()
                                                .fill(Color.clear)
                                                .frame(height: 3)
                                        }
                                    }
                                }
                            }
                            
                            // Archived Tab
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = .archived
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        Text("Archived")
                                            .font(.custom("OpenSans-Bold", size: 16))
                                            .foregroundStyle(selectedTab == .archived ? .primary : .secondary)
                                        
                                        if archivedConversations.count > 0 {
                                            Text("\(archivedConversations.count)")
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
                                    }
                                    
                                    if selectedTab == .archived {
                                        Capsule()
                                            .fill(Color.blue)
                                            .frame(height: 3)
                                            .transition(.scale.combined(with: .opacity))
                                    } else {
                                        Capsule()
                                            .fill(Color.clear)
                                            .frame(height: 3)
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        // Neumorphic Search Bar - consistent with app design
                        NeumorphicMessagesSearchBar(text: $searchText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .background(Color(.systemGroupedBackground))
                    
                    // Content based on selected tab
                    Group {
                        switch selectedTab {
                        case .messages:
                            messagesContent
                        case .requests:
                            requestsContent
                        case .archived:
                            archivedContent
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: selectedTab)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showChatView) {
                if let conversation = selectedConversation {
                    NavigationStack {
                        ChatView(conversation: conversation)
                    }
                }
            }
            .sheet(isPresented: $showNewMessage) {
                MessagingUserSearchView { firebaseUser in
                    // Convert FirebaseSearchUser to SearchableUser
                    let selectedUser = SearchableUser(from: firebaseUser)
                    
                    // Start conversation with selected user
                    Task {
                        await startConversation(with: selectedUser)
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView()
            }
            .sheet(isPresented: $showSettings) {
                MessageSettingsView()
            }
            .onAppear {
                // Start listening to real-time conversations from Firebase
                messagingService.startListeningToConversations()
                
                // Fetch and cache current user's name for messaging
                Task {
                    await messagingService.fetchAndCacheCurrentUserName()
                    await loadMessageRequests()
                    await loadArchivedConversations()
                    
                    // Start listening for real-time message requests
                    startListeningToMessageRequests()
                }
            }
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
            .onDisappear {
                // Stop listening when view disappears
                messagingService.stopListeningToConversations()
                stopListeningToMessageRequests()
            }
            .onChange(of: messagingCoordinator.conversationToOpen) { oldValue, conversationId in
                // Handle opening a specific conversation from coordinator
                guard let conversationId = conversationId else { return }
                
                // Find the conversation in our list
                if let conversation = conversations.first(where: { $0.id == conversationId }) {
                    selectedConversation = conversation
                    showChatView = true
                } else {
                    // Conversation might not be loaded yet, fetch it
                    Task {
                        // Give Firebase a moment to sync
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if let conversation = conversations.first(where: { $0.id == conversationId }) {
                            await MainActor.run {
                                selectedConversation = conversation
                                showChatView = true
                            }
                        }
                    }
                }
            }
        }
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
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                selectedConversation = conversation
                                showChatView = true
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
    
    private func muteConversation(_ conversation: ChatConversation) {
        Task.detached { @MainActor in
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
            }
        }
    }
    
    private func pinConversation(_ conversation: ChatConversation) {
        Task.detached { @MainActor in
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
            }
        }
    }
    
    private func deleteConversation(_ conversation: ChatConversation) {
        Task.detached { @MainActor in
            do {
                isDeleting = true
                
                // Animate removal
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    // Will be removed from list automatically via Firebase listener
                }
                
                try await FirebaseMessagingService.shared.deleteConversation(
                    conversationId: conversation.id
                )
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                isDeleting = false
                
                print("🗑️ Deleted conversation: \(conversation.name)")
            } catch {
                print("❌ Error deleting conversation: \(error)")
                isDeleting = false
            }
        }
    }
    
    // MARK: - Archive Management
    
    private func archiveConversation(_ conversation: ChatConversation) {
        Task.detached { @MainActor in
            do {
                isArchiving = true
                
                // Animate archiving
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    // Will move to archived tab
                }
                
                try await FirebaseMessagingService.shared.archiveConversation(
                    conversationId: conversation.id
                )
                
                // Reload both lists
                await loadArchivedConversations()
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                isArchiving = false
                
                print("📦 Archived conversation: \(conversation.name)")
            } catch {
                print("❌ Error archiving conversation: \(error)")
                isArchiving = false
            }
        }
    }
    
    private func unarchiveConversation(_ conversation: ChatConversation) {
        Task { @MainActor in
            do {
                isArchiving = true
                
                // Animate unarchiving
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    // Will move back to messages tab
                }
                
                try await FirebaseMessagingService.shared.unarchiveConversation(
                    conversationId: conversation.id
                )
                
                // Reload both lists
                await loadArchivedConversations()
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                isArchiving = false
                
                print("📬 Unarchived conversation: \(conversation.name)")
            } catch {
                print("❌ Error unarchiving conversation: \(error)")
                isArchiving = false
            }
        }
    }
    
    private func loadArchivedConversations() async {
        do {
            let archived = try await FirebaseMessagingService.shared.getArchivedConversations()
            
            await MainActor.run {
                archivedConversations = archived
            }
            
            print("📦 Loaded \(archived.count) archived conversations")
        } catch {
            print("❌ Error loading archived conversations: \(error)")
            archivedConversations = []
        }
    }
    
    private var archivedContent: some View {
        Group {
            if archivedConversations.isEmpty {
                archivedEmptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(archivedConversations) { conversation in
                            Button {
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                selectedConversation = conversation
                                showChatView = true
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
                .refreshable {
                    await loadArchivedConversations()
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
        try await service.acceptMessageRequest(
            requestId: request.conversationId
        )
        
        // Mark the request as read
        try await service.markMessageRequestAsRead(
            requestId: request.conversationId
        )
        
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
        try await service.declineMessageRequest(
            requestId: request.conversationId
        )
        
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
        do {
            print("🚀 Starting conversation with user: \(user.displayName) (ID: \(user.id))")
            
            // Create or get existing conversation
            let conversationId = try await messagingService.getOrCreateDirectConversation(
                withUserId: user.id,
                userName: user.displayName
            )
            
            print("✅ Got conversation ID: \(conversationId)")
            
            // Dismiss the search sheet
            await MainActor.run {
                showNewMessage = false
            }
            
            // Small delay for sheet dismissal
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Check if conversation exists in list
            if let conversation = conversations.first(where: { $0.id == conversationId }) {
                print("✅ Found existing conversation in list")
                await MainActor.run {
                    selectedConversation = conversation
                    showChatView = true
                }
            } else {
                print("📝 Creating new conversation object")
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
                    selectedConversation = tempConversation
                    showChatView = true
                }
            }
            
            // Haptic feedback
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
            
            print("✅ Started conversation with @\(user.username ?? "unknown")")
            
        } catch {
            print("❌ Failed to start conversation: \(error.localizedDescription)")
            
            // Show error to user
            await MainActor.run {
                showNewMessage = false
                
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
                showNewMessage = true
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
    
    var body: some View {
        HStack(spacing: 14) {
            // Neumorphic search icon circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 5, y: 5)
                    .shadow(color: .white.opacity(0.8), radius: 10, x: -5, y: -5)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.black.opacity(0.5), Color.black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            TextField("Search conversations", text: $text)
                .font(.custom("OpenSans-SemiBold", size: 17))
                .foregroundStyle(.primary)
                .submitLabel(.search)
            
            if !text.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        text = ""
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.15), radius: 15, x: 8, y: 8)
                .shadow(color: .white.opacity(0.7), radius: 15, x: -8, y: -8)
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.white.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
}

// MARK: - Neumorphic Conversation Row

struct NeumorphicConversationRow: View {
    let conversation: ChatConversation
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar with neumorphic style
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 4, y: 4)
                    .shadow(color: .white.opacity(0.7), radius: 8, x: -4, y: -4)
                
                ZStack {
                    Circle()
                        .fill(conversation.avatarColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
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
                                Capsule()
                                    .fill(Color.blue)
                                    .shadow(color: .blue.opacity(0.4), radius: 4, y: 2)
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
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

struct MessageRequest: Identifiable, Hashable {
    let id: String
    let conversationId: String
    let fromUserId: String
    let fromUserName: String
    var isRead: Bool
}

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

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                
                Text("Feature Temporarily Unavailable")
                    .font(.custom("OpenSans-Bold", size: 20))
                
                Text("Group creation is being updated.\nPlease check back soon!")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
            }
            .padding()
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
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

// MARK: - END TEMPORARY STUBS

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
    
    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Modern Header
                modernConversationHeader
                
                // Messages
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
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
                        .padding(.bottom, 80)
                    }
                    .onAppear {
                        scrollProxy = proxy
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 0)
            }
            
            // Floating input bar
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
            // Clean up listeners
            FirebaseMessagingService.shared.stopListeningToMessages(conversationId: conversation.id)
        }
        .onChange(of: messageText) { _, newValue in
            handleTypingIndicator(isTyping: !newValue.isEmpty)
        }
    }
    
    // MARK: - Modern Header
    
    private var modernConversationHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 40)
                
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
            
            // Just the name
            Text(conversation.name)
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.white)
            
            Spacer()
            
            // More options button only
            Button {
                // More options
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }
    
    // MARK: - Message Actions
    
    private func loadSampleMessages() {
        // Load real messages from Firebase
        let conversationId = conversation.id
        FirebaseMessagingService.shared.startListeningToMessages(conversationId: conversationId) { newMessages in
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
        FirebaseMessagingService.shared.startListeningToTyping(conversationId: conversationId) { typingUsers in
            isTyping = !typingUsers.isEmpty
        }
    }
    
    private func handleTypingIndicator(isTyping: Bool) {
        Task {
            try? await FirebaseMessagingService.shared.updateTypingStatus(
                conversationId: conversation.id,
                isTyping: isTyping
            )
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


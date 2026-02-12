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
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    @ObservedObject private var messagingCoordinator = MessagingCoordinator.shared
    @State private var searchText = ""
    @State private var activeSheet: MessageSheetType?
    @State private var selectedTab: MessageTab = .messages
    @State private var messageRequests: [MessageRequest] = []
    @State private var showDeleteConfirmation = false
    @State private var conversationToDelete: ChatConversation?
    @State private var isArchiving = false
    @State private var isDeleting = false
    @State private var isRefreshing = false
    
    enum MessageTab {
        case messages
        case requests
        case archived
    }
    
    // Real conversations from Firebase
    private var conversations: [ChatConversation] {
        messagingService.conversations
    }
    
    // Pinned conversations (separate from regular messages)
    var pinnedConversations: [ChatConversation] {
        var conversations = messagingService.conversations

        // Only show pinned conversations in Messages tab (not in requests or archived)
        guard selectedTab == .messages else { return [] }

        conversations = conversations.filter { $0.status == "accepted" && $0.isPinned }

        // Apply search filter if search text is not empty
        if !searchText.isEmpty {
            conversations = conversations.filter { conversation in
                conversation.name.localizedCaseInsensitiveContains(searchText) ||
                conversation.lastMessage.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort by most recent
        return conversations.sorted { $0.timestamp > $1.timestamp }
    }

    var filteredConversations: [ChatConversation] {
        var conversations = messagingService.conversations
        let currentUserId = Auth.auth().currentUser?.uid ?? ""

        // ✅ Filter by tab FIRST (Instagram/Threads style)
        switch selectedTab {
        case .messages:
            // Show:
            // 1. All accepted conversations (not pinned)
            // 2. Pending conversations that YOU initiated (your outgoing messages)
            conversations = conversations.filter { conversation in
                if conversation.isPinned {
                    return false
                }
                
                if conversation.status == "accepted" {
                    return true
                }
                
                // Show pending conversations that you initiated
                if conversation.status == "pending" && conversation.requesterId == currentUserId {
                    return true
                }
                
                return false
            }
        case .requests:
            // Show only pending conversations FROM others (incoming requests)
            conversations = conversations.filter { conversation in
                conversation.status == "pending" && conversation.requesterId != currentUserId
            }
        case .archived:
            // Archived conversations are handled separately by messagingService.archivedConversations
            conversations = messagingService.archivedConversations
        }

        // Apply search filter if search text is not empty
        if !searchText.isEmpty {
            conversations = conversations.filter { conversation in
                conversation.name.localizedCaseInsensitiveContains(searchText) ||
                conversation.lastMessage.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Deduplicate by ID (in case there are any duplicates)
        var seen = Set<String>()
        var uniqueConversations: [ChatConversation] = []
        var duplicateCount = 0

        for conversation in conversations {
            if !seen.contains(conversation.id) {
                seen.insert(conversation.id)
                uniqueConversations.append(conversation)
            } else {
                duplicateCount += 1
            }
        }
        
        if duplicateCount > 0 {
            print("⚠️ Found and removed \(duplicateCount) duplicate conversation(s)")
        }
        
        return uniqueConversations
    }
    
    // ✅ Count of pending message requests (only incoming requests from others)
    private var pendingRequestsCount: Int {
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        return messagingService.conversations.filter { 
            $0.status == "pending" && $0.requesterId != currentUserId
        }.count
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
                    Group {
                        switch sheetType {
                        case .chat(let conversation):
                            UnifiedChatView(conversation: conversation)
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
                    .presentationDragIndicator(.visible)
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
                    messagingService: messagingService,
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
                    withAnimation(.easeOut(duration: 0.2)) {
                        activeSheet = .newMessage
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Label("New Message", systemImage: "bubble.left.and.bubble.right")
                }
                
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        activeSheet = .createGroup
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Label("New Group", systemImage: "person.3")
                }
                
                Divider()
                
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
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
        HStack(spacing: 0) {
            ForEach([MessageTab.messages, MessageTab.requests, MessageTab.archived], id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selectedTab = tab
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Text(tabTitle(for: tab))
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                        
                        // Badge for unread requests
                        if tab == .requests && unreadRequestsCount > 0 {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 20, height: 20)
                                
                                Text("\(unreadRequestsCount)")
                                    .font(.custom("OpenSans-Bold", size: 10))
                                    .foregroundStyle(.white)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Color.blue)
                                    .matchedGeometryEffect(id: "TAB", in: tabNamespace)
                            }
                        }
                    )
                }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color(.systemGray6))
        )
    }
    
    @Namespace private var tabNamespace
    
    private func tabTitle(for tab: MessageTab) -> String {
        switch tab {
        case .messages: return "Messages"
        case .requests: return "Requests"
        case .archived: return "Archived"
        }
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
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedTab)
    }
    
    // MARK: - Content Views
    
    private var messagesContent: some View {
        Group {
            if filteredConversations.isEmpty && pinnedConversations.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        // Pinned conversations section (only in Messages tab)
                        if !pinnedConversations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Pinned")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .tracking(0.5)

                                    Spacer()

                                    Text("\(pinnedConversations.count)/3")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary.opacity(0.7))
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 8)

                                ForEach(pinnedConversations) { conversation in
                                    Button {
                                        print("\n========================================")
                                        print("📌 PINNED CONVERSATION TAPPED")
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
                                        SmartConversationRow(conversation: conversation)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .contextMenu {
                                        conversationContextMenu(for: conversation)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        // Delete
                                        Button(role: .destructive) {
                                            conversationToDelete = conversation
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash.fill")
                                        }

                                        // Archive
                                        Button {
                                            archiveConversation(conversation)
                                        } label: {
                                            Label("Archive", systemImage: "archivebox.fill")
                                        }
                                        .tint(.orange)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        // Unpin (always unpin for pinned conversations)
                                        Button {
                                            unpinConversation(conversation)
                                        } label: {
                                            Label("Unpin", systemImage: "pin.slash.fill")
                                        }
                                        .tint(.yellow)

                                        // Mute/Unmute
                                        Button {
                                            if conversation.isMuted {
                                                unmuteConversation(conversation)
                                            } else {
                                                muteConversation(conversation)
                                            }
                                        } label: {
                                            Label(
                                                conversation.isMuted ? "Unmute" : "Mute",
                                                systemImage: conversation.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                                            )
                                        }
                                        .tint(.purple)
                                    }
                                }

                                // Divider between pinned and regular
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                            }
                        }

                        // Regular conversations section
                        if !filteredConversations.isEmpty && !pinnedConversations.isEmpty {
                            HStack {
                                Text("Messages")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

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
                                SmartConversationRow(conversation: conversation)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                conversationContextMenu(for: conversation)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                // Delete
                                Button(role: .destructive) {
                                    conversationToDelete = conversation
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }

                                // Archive
                                Button {
                                    archiveConversation(conversation)
                                } label: {
                                    Label("Archive", systemImage: "archivebox.fill")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                // Pin/Unpin
                                Button {
                                    if conversation.isPinned {
                                        unpinConversation(conversation)
                                    } else {
                                        pinConversation(conversation)
                                    }
                                } label: {
                                    Label(
                                        conversation.isPinned ? "Unpin" : "Pin",
                                        systemImage: conversation.isPinned ? "pin.slash.fill" : "pin.fill"
                                    )
                                }
                                .tint(.yellow)

                                // Mute/Unmute
                                Button {
                                    if conversation.isMuted {
                                        unmuteConversation(conversation)
                                    } else {
                                        muteConversation(conversation)
                                    }
                                } label: {
                                    Label(
                                        conversation.isMuted ? "Unmute" : "Mute",
                                        systemImage: conversation.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                                    )
                                }
                                .tint(.purple)
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
        // Prevent multiple simultaneous refreshes
        guard !isRefreshing else { return }
        
        isRefreshing = true
        print("🔄 Refreshing conversations...")
        
        // Stop current listener
        messagingService.stopListeningToConversations()
        
        // Small delay for better UX
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Restart listener to fetch fresh data
        messagingService.startListeningToConversations()
        
        // Wait a bit more for data to load
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            isRefreshing = false
        }
        
        print("✅ Conversations refreshed")
    }
    
    private func refreshMessageRequests() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        print("🔄 Refreshing message requests...")
        
        // Reload message requests
        await loadMessageRequests()
        
        // Small delay for UX
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            isRefreshing = false
        }
        
        print("✅ Message requests refreshed")
    }
    
    private func refreshArchivedConversations() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        print("🔄 Refreshing archived conversations...")
        
        // Stop current listener
        messagingService.stopListeningToArchivedConversations()
        
        // Small delay for better UX
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Restart listener to fetch fresh data
        messagingService.startListeningToArchivedConversations()
        
        // Wait for data to load
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            isRefreshing = false
        }
        
        print("✅ Archived conversations refreshed")
    }
    
    // MARK: - Conversation Management
    
    @State private var isProcessing = false
    
    private func muteConversation(_ conversation: ChatConversation) {
        guard !isProcessing else { return }

        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }

            do {
                try await FirebaseMessagingService.shared.muteConversation(conversation.id)

                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)

                print("🔕 Conversation muted: \(conversation.name)")
            } catch {
                print("❌ Failed to mute conversation: \(error)")
                // TODO: Show error alert to user
            }
        }
    }

    private func unmuteConversation(_ conversation: ChatConversation) {
        guard !isProcessing else { return }

        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }

            do {
                try await FirebaseMessagingService.shared.unmuteConversation(conversation.id)

                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)

                print("🔔 Conversation unmuted: \(conversation.name)")
            } catch {
                print("❌ Failed to unmute conversation: \(error)")
                // TODO: Show error alert to user
            }
        }
    }

    private func pinConversation(_ conversation: ChatConversation) {
        guard !isProcessing else { return }

        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }

            do {
                try await FirebaseMessagingService.shared.pinConversation(conversation.id)

                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)

                print("📌 Conversation pinned: \(conversation.name)")
            } catch {
                print("❌ Failed to pin conversation: \(error.localizedDescription)")
                // TODO: Show error alert to user (e.g., "You can only pin up to 3 conversations")
            }
        }
    }

    private func unpinConversation(_ conversation: ChatConversation) {
        guard !isProcessing else { return }

        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }

            do {
                try await FirebaseMessagingService.shared.unpinConversation(conversation.id)

                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)

                print("📌 Conversation unpinned: \(conversation.name)")
            } catch {
                print("❌ Failed to unpin conversation: \(error)")
                // TODO: Show error alert to user
            }
        }
    }

    private func reportSpam(_ conversation: ChatConversation) {
        guard !isProcessing else { return }

        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }

            do {
                try await FirebaseMessagingService.shared.reportSpam(conversation.id, reason: "Spam or unwanted messages")

                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)

                print("⚠️ Conversation reported as spam: \(conversation.name)")
            } catch {
                print("❌ Failed to report conversation: \(error)")
                // TODO: Show error alert to user
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
                withAnimation(.easeOut(duration: 0.2)) {
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

    // MARK: - Context Menu

    @ViewBuilder
    private func conversationContextMenu(for conversation: ChatConversation) -> some View {
        // Pin/Unpin
        Button {
            if conversation.isPinned {
                unpinConversation(conversation)
            } else {
                pinConversation(conversation)
            }
        } label: {
            Label(
                conversation.isPinned ? "Unpin" : "Pin",
                systemImage: conversation.isPinned ? "pin.slash.fill" : "pin.fill"
            )
        }

        // Mute/Unmute
        Button {
            if conversation.isMuted {
                unmuteConversation(conversation)
            } else {
                muteConversation(conversation)
            }
        } label: {
            Label(
                conversation.isMuted ? "Unmute" : "Mute",
                systemImage: conversation.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
            )
        }

        Divider()

        // Archive
        Button {
            archiveConversation(conversation)
        } label: {
            Label("Archive", systemImage: "archivebox.fill")
        }

        // Delete
        Button(role: .destructive) {
            conversationToDelete = conversation
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash.fill")
        }

        // Report Spam (only for non-group conversations)
        if !conversation.isGroup {
            Divider()

            Button(role: .destructive) {
                reportSpam(conversation)
            } label: {
                Label("Report Spam", systemImage: "exclamationmark.shield.fill")
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
                withAnimation(.easeOut(duration: 0.2)) {
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
        guard !isArchiving else { return }
        
        Task { @MainActor in
            isArchiving = true
            defer { isArchiving = false }
            
            do {
                // Animate unarchiving
                withAnimation(.easeOut(duration: 0.2)) {
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
                .refreshable {
                    await refreshArchivedConversations()
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
                .refreshable {
                    await refreshMessageRequests()
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
                // Optimistic UI update - remove request immediately for smoother UX
                if action == .accept || action == .decline || action == .block {
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.25)) {
                            messageRequests.removeAll { $0.id == request.id }
                        }
                    }
                }
                
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
                
                // Reload to ensure consistency
                await loadMessageRequests()
            } catch {
                print("❌ Error handling request action: \(error)")
                // Reload on error to restore accurate state
                await loadMessageRequests()
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
        
        // Haptic feedback and smooth transition to messages tab
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Smoothly transition to messages tab with animation
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedTab = .messages
            }
            
            if let acceptedConversation = messagingService.conversations.first(where: { $0.id == request.conversationId }) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    activeSheet = .chat(acceptedConversation)
                }
            } else {
                let placeholderConversation = ChatConversation(
                    id: request.conversationId,
                    name: request.fromUserName,
                    lastMessage: "",
                    timestamp: Date().smartTimestamp,
                    isGroup: false,
                    unreadCount: 0,
                    avatarColor: .blue
                )
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    activeSheet = .chat(placeholderConversation)
                }
            }
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
            
            // Small delay for sheet dismissal animation
            print("⏳ Step 5: Waiting for sheet dismissal animation...")
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
                    withAnimation(.easeOut(duration: 0.2)) {
                        isSearching = !newValue.isEmpty
                    }
                }
            
            if !text.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
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
        .animation(.easeOut(duration: 0.2), value: isSearching)
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
        .animation(.easeOut(duration: 0.15), value: isPressed)
        .animation(.easeOut(duration: 0.2), value: isActive)
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
                // Compact glassmorphic background with subtle elevation
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(conversation.isPinned ? 0.5 : 0.35),
                                Color.white.opacity(conversation.isPinned ? 0.2 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Enhanced border for pinned conversations
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: conversation.isPinned ? [
                                Color.orange.opacity(0.4),
                                Color.orange.opacity(0.2)
                            ] : [
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: conversation.isPinned ? 1.5 : 1
                    )
            }
        )
        .shadow(
            color: conversation.isPinned ? .orange.opacity(0.12) :
                   conversation.unreadCount > 0 ? .blue.opacity(0.12) : 
                   .black.opacity(0.06),
            radius: 8,
            y: 3
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: conversation.unreadCount)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: conversation.isPinned)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.12)) {
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
            withAnimation(.easeOut(duration: 0.15)) {
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
            // Avatar with real-time profile photo
            ZStack {
                Circle()
                    .fill(conversation.avatarColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                if conversation.isGroup {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(conversation.avatarColor)
                } else if let profilePhotoURL = conversation.profilePhotoURL, !profilePhotoURL.isEmpty {
                    // Show profile photo with caching for persistence
                    CachedAsyncImage(
                        url: URL(string: profilePhotoURL),
                        content: { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        },
                        placeholder: {
                            ProgressView()
                                .tint(conversation.avatarColor)
                                .frame(width: 56, height: 56)
                        }
                    )
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
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    
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
                .onChange(of: groupName) { _, newValue in
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
        withAnimation(.easeOut(duration: 0.2)) {
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
        withAnimation(.easeOut(duration: 0.2)) {
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
                    
                    print("📬 Opening new group conversation: \(conversationId)")
                    MessagingCoordinator.shared.openConversation(conversationId)
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
                    withAnimation(.easeOut(duration: 0.2)) {
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

// MARK: - Global Message Search View

struct GlobalMessageSearchView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var searchResults: [MessageSearchResult] = []
    @State private var isSearching = false
    @State private var selectedFilter: SearchFilter = .all
    @State private var searchTask: Task<Void, Never>?
    
    enum SearchFilter: String, CaseIterable {
        case all = "All"
        case photos = "Photos"
        case links = "Links"
        case people = "People"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Filter tabs
                if !searchText.isEmpty {
                    filterTabs
                }
                
                // Results
                if isSearching {
                    ProgressView("Searching messages...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchText.isEmpty {
                    emptySearchState
                } else if searchResults.isEmpty {
                    noResultsState
                } else {
                    searchResultsList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Search Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
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
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search in all conversations", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            
            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        searchText = ""
                        searchResults = []
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .padding()
        .onChange(of: searchText) { _, newValue in
            performSearch(query: newValue)
        }
    }
    
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SearchFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(selectedFilter == filter ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == filter ? Color.blue : Color(.systemGray5))
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
    }
    
    private var emptySearchState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("Search all your messages")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                
                Text("Find messages, photos, and links\nacross all conversations")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
    }
    
    private var noResultsState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("No results found")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                
                Text("Try different keywords")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { result in
                    MessageSearchResultRow(result: result) {
                        // Open conversation
                        dismiss()
                        MessagingCoordinator.shared.openConversation(result.conversationId)
                    }
                    
                    if result.id != searchResults.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            .padding()
        }
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty, query.count >= 2 else {
            searchResults = []
            return
        }
        
        searchTask?.cancel()
        isSearching = true
        
        searchTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            guard !Task.isCancelled else { return }
            
            do {
                print("🔍 Searching messages across all conversations for: '\(query)'")
                
                // Get all conversations the user is part of
                let allConversations = FirebaseMessagingService.shared.conversations
                var foundResults: [MessageSearchResult] = []
                
                // Search through each conversation's messages
                for conversation in allConversations {
                    // Search messages in this conversation
                    let messages = try await FirebaseMessagingService.shared.searchMessagesInConversation(
                        conversationId: conversation.id,
                        query: query
                    )
                    
                    // Convert to search results
                    for message in messages {
                        let result = MessageSearchResult(
                            conversationId: conversation.id,
                            conversationName: conversation.name,
                            messageText: message.text,
                            timestamp: message.timestamp,
                            senderName: message.senderName ?? "Unknown",
                            hasAttachment: !message.attachments.isEmpty
                        )
                        foundResults.append(result)
                    }
                }
                
                // Sort by timestamp (most recent first)
                foundResults.sort { $0.timestamp > $1.timestamp }
                
                // Apply filter
                let filteredResults = filterResults(foundResults, by: selectedFilter)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    searchResults = filteredResults
                    isSearching = false
                    print("✅ Found \(filteredResults.count) matching messages")
                }
                
            } catch {
                guard !Task.isCancelled else { return }
                
                print("❌ Error searching messages: \(error)")
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
    
    private func filterResults(_ results: [MessageSearchResult], by filter: SearchFilter) -> [MessageSearchResult] {
        switch filter {
        case .all:
            return results
        case .photos:
            // Filter for messages with photo attachments
            return results.filter { $0.hasAttachment && $0.messageText.contains("📷") }
        case .links:
            // Filter for messages with links
            return results.filter { $0.messageText.contains("http") }
        case .people:
            // Show grouped by sender (keep first message from each sender)
            var seenSenders = Set<String>()
            return results.filter { result in
                if seenSenders.contains(result.senderName) {
                    return false
                } else {
                    seenSenders.insert(result.senderName)
                    return true
                }
            }
        }
    }
}

struct MessageSearchResult: Identifiable {
    let id = UUID()
    let conversationId: String
    let conversationName: String
    let messageText: String
    let timestamp: Date
    let senderName: String
    let hasAttachment: Bool
}

struct MessageSearchResultRow: View {
    let result: MessageSearchResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Conversation avatar
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(result.conversationName.prefix(2).uppercased())
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(result.conversationName)
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Text(result.timestamp.smartTimestamp)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(result.messageText)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Text(result.senderName)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.blue)
                }
                
                if result.hasAttachment {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Smart Conversation Row with Preview (Compact & Enhanced)

struct SmartConversationRow: View {
    let conversation: ChatConversation
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Photo or Avatar (Compact - 48x48)
            ZStack {
                // Outer glow for unread (smaller)
                if conversation.unreadCount > 0 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.blue.opacity(0.25),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 28
                            )
                        )
                        .frame(width: 56, height: 56)
                        .blur(radius: 6)
                }
                
                // Profile photo if available, otherwise gradient avatar
                if let photoURL = conversation.profilePhotoURL, !photoURL.isEmpty {
                    CachedAsyncImage(
                        url: URL(string: photoURL),
                        content: { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
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
                                )
                        },
                        placeholder: {
                            fallbackAvatar
                        }
                    )
                } else {
                    fallbackAvatar
                }
                
                // Pinned indicator
                if conversation.isPinned {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(4)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: .black.opacity(0.15), radius: 2)
                                )
                        }
                        Spacer()
                    }
                    .frame(width: 48, height: 48)
                }
            }
            .frame(width: 48, height: 48)
            
            // Content with smart preview (Compact)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Name with optional muted indicator
                    HStack(spacing: 4) {
                        Text(conversation.name)
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if conversation.isMuted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    // Timestamp
                    Text(parseTimestamp(conversation.timestamp))
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }
                
                HStack(alignment: .center, spacing: 6) {
                    // Smart preview with icons
                    smartMessagePreview
                        .font(.custom("OpenSans-Regular", size: 13))
                    
                    Spacer()
                    
                    // Unread badge with animation
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.custom("OpenSans-Bold", size: 10))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, 5)
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
                                            lineWidth: 0.5
                                        )
                                }
                            )
                            .shadow(color: .blue.opacity(0.4), radius: 4, y: 2)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Message indicators
                    HStack(spacing: 4) {
                        // Delivery status for last message
                        if conversation.lastMessage.hasPrefix("You: ") {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.blue.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
        .animation(.easeOut(duration: 0.15), value: isPressed)
        .animation(.easeOut(duration: 0.2), value: conversation.unreadCount)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.15)) {
                isPressed = pressing
            }
        }, perform: {})
    }
    
    // Fallback avatar when no profile photo
    @ViewBuilder
    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 48, height: 48)
            
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
                .frame(width: 48, height: 48)
            
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
                .frame(width: 48, height: 48)
            
            if conversation.isGroup {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(conversation.avatarColor)
                    .symbolEffect(.bounce, value: isPressed)
            } else {
                Text(conversation.initials)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(conversation.avatarColor)
            }
        }
    }
    
    @ViewBuilder
    private var smartMessagePreview: some View {
        HStack(spacing: 4) {
            // Icon based on message type
            if conversation.lastMessage.contains("📷") || conversation.lastMessage.contains("Photo") {
                Image(systemName: "photo.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if conversation.lastMessage.contains("🎤") || conversation.lastMessage.contains("Voice") {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if conversation.lastMessage.contains("📎") || conversation.lastMessage.contains("Attachment") {
                Image(systemName: "paperclip")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if conversation.lastMessage.contains("❤️") || conversation.lastMessage.contains("Liked") {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
            }
            
            Text(conversation.lastMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
    
    private func parseTimestamp(_ timestamp: String) -> String {
        // Try to parse Firebase timestamp or use smart timestamp
        if let date = parseFirebaseTimestamp(timestamp) {
            return date.smartTimestamp
        }
        return timestamp
    }
    
    private func parseFirebaseTimestamp(_ timestamp: String) -> Date? {
        // Implement Firebase timestamp parsing if needed
        return nil
    }
}

// MARK: - Smart Timestamp Extension

extension Date {
    var smartTimestamp: String {
        let calendar = Calendar.current
        let now = Date()
        
        // Check if today
        if calendar.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: self)
        }
        
        // Check if yesterday
        if calendar.isDateInYesterday(self) {
            return "Yesterday"
        }
        
        // Check if within this week
        if let daysAgo = calendar.dateComponents([.day], from: self, to: now).day,
           daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name
            return formatter.string(from: self)
        }
        
        // Check if this year
        if calendar.component(.year, from: self) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d" // Dec 25
            return formatter.string(from: self)
        }
        
        // Older than this year
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: self)
    }
}

// MARK: - END TEMPORARY STUBS

// MARK: - View Modifiers to Break Down Complexity

struct LifecycleModifier: ViewModifier {
    let messagingService: FirebaseMessagingService
    let loadMessageRequests: () async -> Void
    let startListeningToMessageRequests: () -> Void
    let stopListeningToMessageRequests: () -> Void
    
    @State private var hasAppeared = false
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Prevent duplicate initialization
                guard !hasAppeared else {
                    print("⚠️ MessagesView already initialized, skipping duplicate setup")
                    return
                }
                hasAppeared = true
                
                print("🎬 MessagesView appearing - starting listeners")
                
                // Start listening to real-time conversations from Firebase
                messagingService.startListeningToConversations()
                messagingService.startListeningToArchivedConversations()
                
                // Fetch and cache current user's name for messaging
                Task {
                    await messagingService.fetchAndCacheCurrentUserName()
                    await loadMessageRequests()
                    
                    // Start listening for real-time message requests
                    startListeningToMessageRequests()
                    
                    // ✅ DEBUG: Show conversation breakdown after data loads
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second for data
                    
                    await MainActor.run {
                        let currentUserId = Auth.auth().currentUser?.uid ?? ""
                        
                        print("\n📊 CONVERSATION BREAKDOWN:")
                        print("   Total: \(messagingService.conversations.count)")
                        print("   Accepted: \(messagingService.conversations.filter { $0.status == "accepted" }.count)")
                        print("   Pending (sent by you): \(messagingService.conversations.filter { $0.status == "pending" && $0.requesterId == currentUserId }.count)")
                        print("   Pending (from others): \(messagingService.conversations.filter { $0.status == "pending" && $0.requesterId != currentUserId }.count)")
                        print("   Archived: \(messagingService.archivedConversations.count)")
                        
                        print("\n💬 MESSAGES TAB will show:")
                        print("   ✅ Accepted conversations:")
                        for conv in messagingService.conversations.filter({ $0.status == "accepted" && !$0.isPinned }) {
                            print("      - \(conv.name): \"\(conv.lastMessage)\"")
                        }
                        print("   📤 Your outgoing pending messages:")
                        for conv in messagingService.conversations.filter({ $0.status == "pending" && $0.requesterId == currentUserId }) {
                            print("      - \(conv.name): \"\(conv.lastMessage)\"")
                        }
                        
                        print("\n📥 REQUESTS TAB will show:")
                        for conv in messagingService.conversations.filter({ $0.status == "pending" && $0.requesterId != currentUserId }) {
                            print("   - \(conv.name): \"\(conv.lastMessage)\"")
                        }
                    }
                }
            }
            .onDisappear {
                print("👋 MessagesView disappearing - stopping listeners")
                hasAppeared = false
                
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
    @ObservedObject var messagingCoordinator: MessagingCoordinator
    let messagingService: FirebaseMessagingService
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
                    Task { @MainActor in
                        if let fetchedConversation = await messagingService.fetchConversation(conversationId: conversationId) {
                            activeSheet = .chat(fetchedConversation)
                        }
                    }
                }
            }
            .onReceive(messagingCoordinator.$shouldOpenMessageRequests) { shouldOpen in
                // Switch to requests tab when coordinator signals
                if shouldOpen {
                    withAnimation(.easeOut(duration: 0.2)) {
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
    
    @State private var typingTask: Task<Void, Never>?
    
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
            FirebaseMessagingService.shared.stopListeningToMessages(conversationId: conversation.id)
            
            // Cancel typing task
            typingTask?.cancel()
            typingTask = nil
            
            // Send typing stopped status
            Task { @MainActor in
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
        
        let textToSend = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagesToSend = selectedImages
        let replyToId = replyingTo?.id
        
        // Clear input immediately for better UX
        messageText = ""
        selectedImages = []
        replyingTo = nil
        isInputFocused = false
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Send to Firebase
        Task { @MainActor in
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
        // Cancel previous task
        typingTask?.cancel()
        
        if isTyping {
            // Send typing started
            Task { @MainActor in
                try? await FirebaseMessagingService.shared.updateTypingStatus(
                    conversationId: conversation.id,
                    isTyping: true
                )
            }
            
            // Auto-stop typing after 5 seconds of no new input
            let conversationId = conversation.id
            typingTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled {
                    try? await FirebaseMessagingService.shared.updateTypingStatus(
                        conversationId: conversationId,
                        isTyping: false
                    )
                }
            }
        } else {
            // Send typing stopped immediately
            Task { @MainActor in
                try? await FirebaseMessagingService.shared.updateTypingStatus(
                    conversationId: conversation.id,
                    isTyping: false
                )
            }
        }
    }
    
    private func addReaction(to message: AppMessage, emoji: String) {
        guard messages.contains(where: { $0.id == message.id }) else {
            print("⚠️ Message not found in list, skipping reaction")
            return
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Add reaction to Firebase
        Task { @MainActor in
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


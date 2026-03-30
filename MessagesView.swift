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

// MARK: - Pill Press Style

/// Subtle scale-down on press — gives filter pills premium tactile feedback.
private struct PillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MessagesView: View {
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    @ObservedObject private var messagingCoordinator = MessagingCoordinator.shared
    @ObservedObject private var userService = UserService.shared
    @ObservedObject private var blockService = BlockService.shared
    @State private var searchText = ""
    @State private var activeSheet: MessageSheetType?
    @State private var selectedTab: MessageTab = .messages
    @State private var rowsVisible = false
    @Namespace private var pillNS
    @State private var messageRequests: [MessageRequest] = []
    @State private var showDeleteConfirmation = false
    @State private var conversationToDelete: ChatConversation?
    @State private var isRefreshing = false
    @State private var isMarkingRead = false
    // Dedup guard: tracks in-flight swipe actions per conversation ID
    @State private var actionInFlight: Set<String> = []
    // Swipe-action error feedback
    @State private var showSwipeErrorAlert = false
    @State private var swipeErrorMessage = ""
    // ✅ Scroll tracking for collapsing header
    @State private var scrollOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0
    @State private var showHeader = true
    // Swipe hint (one-time discoverability)
    @AppStorage("hasSeenMessageSwipeHint") private var hasSeenSwipeHint = false
    @State private var showSwipeHint = false

    // Cached filtered lists — recomputed only when their inputs change,
    // not on every body pass.
    @State private var cachedFilteredConversations: [ChatConversation] = []
    @State private var cachedPinnedConversations: [ChatConversation] = []
    
    // ✅ Tab bar visibility control (passed from ContentView)
    @Environment(\.tabBarVisible) private var tabBarVisible
    @Environment(\.mainTabSelection) private var mainTabSelection
    
    enum MessageTab {
        case messages
        case requests
        case archived
    }
    
    // Real conversations from Firebase — deduplicated by participant so pin/unpin
    // doesn't produce a second copy of the same person in any list.
    private var conversations: [ChatConversation] {
        var seen = Set<String>()
        return messagingService.conversations.filter { conv in
            // 1:1 chats: key by the other participant's UID so two docs for the same
            // pair collapse into one. Groups: key by document ID (intentionally unique).
            let pid = conv.otherParticipantId ?? ""
            let key = (!conv.isGroup && !pid.isEmpty) ? pid : conv.id
            return seen.insert(key).inserted
        }
    }
    
    // Pinned conversations — served from cache, populated by recomputeConversationCache().
    var pinnedConversations: [ChatConversation] { cachedPinnedConversations }

    private func computePinnedConversations() -> [ChatConversation] {
        var conversations = messagingService.conversations

        // Only show pinned conversations in Messages tab (not in requests or archived)
        guard selectedTab == .messages else { return [] }

        conversations = conversations.filter { $0.status == "accepted" && $0.isPinned }

        // Block filter: hide conversations with users the current user has blocked
        // (or who have blocked the current user — those conversations are already excluded
        // server-side since blocked users cannot send new messages, but we gate the display
        // here as a defence-in-depth measure for any previously existing threads).
        if !blockService.blockedUsers.isEmpty {
            conversations = conversations.filter { conversation in
                guard let otherId = conversation.otherParticipantId else { return true }
                return !blockService.blockedUsers.contains(otherId)
            }
        }

        // Apply search filter if search text is not empty
        if !searchText.isEmpty {
            conversations = conversations.filter { conversation in
                conversation.name.localizedCaseInsensitiveContains(searchText) ||
                conversation.lastMessage.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Deduplicate pinned conversations by participant UID for 1:1 chats.
        // Using name was incorrect — two users can share a name. UID is unique.
        var seenKeys = Set<String>()
        let deduped = conversations.filter { conv in
            let pid = conv.otherParticipantId ?? ""
            let key = (!conv.isGroup && !pid.isEmpty) ? pid : conv.id
            return seenKeys.insert(key).inserted
        }
        return deduped.sorted { $0.timestamp > $1.timestamp }
    }

    // Filtered conversations — served from cache, populated by recomputeConversationCache().
    var filteredConversations: [ChatConversation] { cachedFilteredConversations }

    private func computeFilteredConversations() -> [ChatConversation] {
        var conversations = messagingService.conversations
        let currentUserId = Auth.auth().currentUser?.uid ?? ""

        // ✅ Filter by tab FIRST (Instagram/Threads style)
        switch selectedTab {
        case .messages:
            // Show:
            // 1. All accepted conversations (pinned excluded when not searching — shown in separate section)
            // 2. Pending conversations that YOU initiated (your outgoing messages)
            // NOTE: When searching, include pinned conversations so they appear in results
            //       (the pinned section is hidden during search, so they would otherwise vanish).
            conversations = conversations.filter { conversation in
                if conversation.isPinned && searchText.isEmpty {
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

        // Deduplicate by document ID first (guard against Firestore listener duplicates)
        var seenIds = Set<String>()
        var idDeduped: [ChatConversation] = []
        for conversation in conversations {
            if seenIds.insert(conversation.id).inserted {
                idDeduped.append(conversation)
            }
        }

        // Deduplicate by participant name for 1-on-1 conversations: if multiple
        // conversation documents exist with the same person (caused by prior bugs
        // creating extras), keep only the most recently active one per contact.
        // Group conversations are exempt since multiple groups can share a name.
        var seenContactKeys = Set<String>()
        var uniqueConversations: [ChatConversation] = []
        var duplicateCount = 0

        for conversation in idDeduped {
            let key: String
            if conversation.isGroup {
                // Groups: always unique by ID (already deduped above)
                key = conversation.id
            } else {
                // 1-on-1: key = other participant's UID, not their display name.
                // Two users can share a name; UID is the only reliable unique identifier.
                let pid = conversation.otherParticipantId ?? ""
                key = pid.isEmpty ? conversation.id : pid
            }
            if seenContactKeys.insert(key).inserted {
                uniqueConversations.append(conversation)
            } else {
                duplicateCount += 1
            }
        }

        #if DEBUG
        if duplicateCount > 0 {
            // Only print to limit log spam — these are stale Firestore duplicates
            // that should be cleaned up server-side. Client dedup is the safety net.
        }
        #endif

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
    
    // AI summary service — inbox-level, request summaries lazily
    @ObservedObject private var aiSummaryService = InboxAISummaryService.shared

    var body: some View {
        NavigationStack {
            amenInboxBody
                .navigationBarHidden(true)
                .onAppear {
                    tabBarVisible.wrappedValue = false
                    BadgeCountManager.shared.clearMessages()
                    // Trigger staggered row entrance
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        rowsVisible = true
                    }
                }
                .onDisappear {
                    tabBarVisible.wrappedValue = true
                }
                .sheet(item: $activeSheet) { sheetType in
                    Group {
                        switch sheetType {
                        case .chat(let conversation):
                            UnifiedChatView(conversation: conversation)
                        case .newMessage:
                            ProductionMessagingUserSearchView { selectedUser in
                                Task { await startConversation(with: selectedUser) }
                            }
                        case .createGroup:
                            CreateGroupView()
                        case .settings:
                            MessageSettingsView()
                        }
                    }
                    .presentationDragIndicator(.visible)
                }
                .onAppear { recomputeConversationCache() }
                .onChange(of: messagingService.conversations) { _, _ in recomputeConversationCache() }
                .onChange(of: messagingService.archivedConversations) { _, _ in recomputeConversationCache() }
                .onChange(of: selectedTab) { _, _ in recomputeConversationCache() }
                .onChange(of: searchText) { _, _ in recomputeConversationCache() }
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
                .alert("Action Failed", isPresented: $showSwipeErrorAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(swipeErrorMessage)
                }
                .modifier(CoordinatorModifier(
                    messagingCoordinator: messagingCoordinator,
                    messagingService: messagingService,
                    conversations: conversations,
                    activeSheet: $activeSheet,
                    selectedTab: $selectedTab
                ))
        }
    }

    // MARK: — AMEN Inbox (new skin)

    private var amenInboxBody: some View {
        ZStack(alignment: .top) {
            AMENInboxTokens.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {

                    // ── HERO HEADER ──────────────────────────────────────────
                    InboxHeroHeader(
                        greetingName: firstName,
                        onCompose: { activeSheet = .newMessage },
                        onBack: { mainTabSelection.wrappedValue = 0 },
                        searchText: $searchText
                    )

                    // ── TAB SELECTOR ─────────────────────────────────────────
                    amenTabSelector
                        .padding(.horizontal, AMENInboxTokens.hPad)
                        .padding(.bottom, 8)

                    // ── QUICK ACCESS STRIP (Messages tab only) ───────────────
                    if selectedTab == .messages && searchText.isEmpty {
                        let recentAccepted = conversations.filter { $0.status == "accepted" }
                        if !recentAccepted.isEmpty {
                            InboxSectionLabel(text: "Recent")
                            QuickAccessRow(conversations: recentAccepted) { conv in
                                openChat(conv)
                            }
                            .padding(.bottom, 8)
                            Divider()
                                .padding(.horizontal, AMENInboxTokens.hPad)
                                .padding(.bottom, 4)
                        }
                    }

                    // ── PINNED CONVERSATIONS ─────────────────────────────────
                    if selectedTab == .messages && !pinnedConversations.isEmpty && searchText.isEmpty {
                        InboxSectionLabel(text: "Pinned")
                        ForEach(pinnedConversations) { conv in
                            amenThreadRow(conv)
                                .contextMenu { conversationContextMenu(for: conv) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    trailingSwipeActions(for: conv)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        unpinConversation(conv)
                                    } label: { Label("Unpin", systemImage: "pin.slash.fill") }
                                        .tint(.gray)
                                }
                            InboxSeparator()
                        }
                        InboxSectionLabel(text: "All Messages")
                    }

                    // ── MAIN LIST ────────────────────────────────────────────
                    if filteredConversations.isEmpty {
                        if searchText.isEmpty {
                            InboxEmptyState(mode: .noMessages)
                                .padding(.top, 60)
                        } else {
                            InboxEmptyState(mode: .noResults(searchText))
                                .padding(.top, 60)
                        }
                    } else {
                        ForEach(Array(filteredConversations.enumerated()), id: \.element.id) { index, conv in
                            amenThreadRow(conv)
                                .contextMenu { conversationContextMenu(for: conv) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    trailingSwipeActions(for: conv)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    leadingSwipeActions(for: conv)
                                }
                                // Request AI summary when row appears
                                .onAppear { aiSummaryService.requestSummary(for: conv) }
                                // Staggered entrance animation
                                .opacity(rowsVisible ? 1 : 0)
                                .offset(x: rowsVisible ? 0 : 20)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.78)
                                    .delay(Double(index) * 0.065),
                                    value: rowsVisible
                                )
                            InboxSeparator()
                        }
                    }

                    // Bottom padding for home indicator
                    Spacer().frame(height: 32)
                }
            }
            .refreshable { await refreshConversations() }
        }
    }

    // Single thread row using the new AMENThreadRow component
    @ViewBuilder
    private func amenThreadRow(_ conv: ChatConversation) -> some View {
        AMENThreadRow(
            conversation: conv,
            aiSummary: aiSummaryService.summary(for: conv),
            onTap: { openChat(conv) }
        )
    }

    // ── Swipe action builders ────────────────────────────────────────────────

    @ViewBuilder
    private func trailingSwipeActions(for conv: ChatConversation) -> some View {
        Button(role: .destructive) {
            conversationToDelete = conv
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash.fill")
        }

        Button {
            archiveConversation(conv)
        } label: {
            Label("Archive", systemImage: "archivebox.fill")
        }
        .tint(.gray)
    }

    @ViewBuilder
    private func leadingSwipeActions(for conv: ChatConversation) -> some View {
        if conv.isPinned {
            Button {
                unpinConversation(conv)
            } label: {
                Label("Unpin", systemImage: "pin.slash.fill")
            }
            .tint(.gray)
        } else {
            Button {
                pinConversation(conv)
            } label: {
                Label("Pin", systemImage: "pin.fill")
            }
            .tint(Color(uiColor: .label))
        }

        Button {
            if conv.unreadCount > 0 {
                markConversationRead(conv)
            } else {
                markConversationUnread(conv)
            }
        } label: {
            Label(
                conv.unreadCount > 0 ? "Mark Read" : "Mark Unread",
                systemImage: conv.unreadCount > 0 ? "envelope.open.fill" : "envelope.badge.fill"
            )
        }
        .tint(.blue)
    }

    // ── Tab selector — premium scrollable pill bar ───────────────────────────

    /// Horizontally-scrollable pill bar. Left-anchored so the active pill is
    /// always visible; extra pills overflow gracefully without wrapping.
    private var amenTabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                amenTabPill(.messages,  label: "All",      badge: nil)
                amenTabPill(.requests,  label: "Requests", badge: pendingRequestsCount > 0 ? pendingRequestsCount : nil)
                amenTabPill(.archived,  label: "Archived", badge: nil)
            }
            .padding(.horizontal, AMENInboxTokens.hPad)
            .padding(.vertical, 2)
        }
        // Prevent the scroll view from eating swipe gestures on the list
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func amenTabPill(_ tab: MessageTab, label: String, badge: Int?) -> some View {
        let isActive = selectedTab == tab

        Button {
            // haptic
            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(isActive ? AMENInboxTokens.pillFontActive : AMENInboxTokens.pillFont)
                    .foregroundStyle(isActive
                        ? AMENInboxTokens.background        // white text on black
                        : AMENInboxTokens.secondaryText)
                    .animation(.easeOut(duration: 0.2), value: isActive)

                // Inline badge count (requests only) with scale animation on first appearance
                if let count = badge, count > 0 {
                    Text("\(min(count, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isActive ? AMENInboxTokens.accent : .white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isActive
                                ? AMENInboxTokens.background.opacity(0.3)
                                : Color.red)
                        )
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(AMENInboxTokens.accent)
                            .matchedGeometryEffect(id: "activePill", in: pillNS)
                    } else {
                        Capsule()
                            .fill(Color(.systemGray6))
                    }
                }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: selectedTab)
        }
        .buttonStyle(PillPressStyle())
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: selectedTab)
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private var firstName: String {
        let display = userService.currentUser?.displayName ?? ""
        return display.components(separatedBy: " ").first ?? display
    }

    private var requestsLabel: String {
        let n = pendingRequestsCount
        return n > 0 ? "Requests (\(n))" : "Requests"
    }
    
    // MARK: - Modern Header Section (Reference Style)
    
    private var modernHeaderSection: some View {
        VStack(spacing: 16) {
            // Top row: Back button + Title + Compose
            HStack(spacing: 16) {
                // ✅ Back button (chevron)
                Button {
                    mainTabSelection.wrappedValue = 0  // Navigate to home tab immediately
                    // haptic
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        )
                }
                
                // ✅ Title (clean, simple - matches reference)
                Text(greetingTitle)
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // ✅ Compose button (liquid glass, like reference)
                Button {
                    activeSheet = .newMessage
                    // haptic
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            // ✅ Segmented control (3 tabs, compact pill style)
            modernTabSelector
                .padding(.horizontal, 20)
            
            // ✅ Search bar (liquid glass, like reference)
            modernSearchBar
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Compact Header (appears when scrolled)
    
    private var compactHeader: some View {
        HStack(spacing: 12) {
            // Back button
            Button {
                mainTabSelection.wrappedValue = 0  // Navigate immediately
                // haptic
                HapticManager.impact(style: .light)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            
            // Compact title
            Text(greetingTitle)
                .font(.custom("OpenSans-Bold", size: 17))
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Compose button
            Button {
                activeSheet = .newMessage
                // haptic
                HapticManager.impact(style: .light)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }
    
    private var greetingTitle: String {
        if let displayName = userService.currentUser?.displayName, !displayName.isEmpty {
            let firstName = displayName.components(separatedBy: " ").first ?? displayName
            return "Hi \(firstName)"
        }
        return "Messages"
    }
    
    // ✅ Modern tab selector (compact pills, like reference)
    private var modernTabSelector: some View {
        HStack(spacing: 8) {
            ForEach([MessageTab.messages, MessageTab.requests, MessageTab.archived], id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                    // haptic
                    HapticManager.impact(style: .light)
                } label: {
                    HStack(spacing: 6) {
                        Text(tabTitle(for: tab))
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                        
                        // Badge for requests
                        if tab == .requests && pendingRequestsCount > 0 {
                            Text("\(pendingRequestsCount)")
                                .font(.custom("OpenSans-Bold", size: 11))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.red)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(selectedTab == tab ? Color.primary : Color.clear)
                    )
                }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
    
    // ✅ Modern search bar (glass pill, like reference)
    @ViewBuilder
    private var modernSearchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search conversations", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.primary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(searchText.isEmpty ? 0.05 : 0.12),
                            radius: searchText.isEmpty ? 8 : 12, y: 2)
            )
            .animation(.easeOut(duration: 0.2), value: searchText.isEmpty)

            // Inline filter chips when searching
            if searchText.count >= 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Photos", "Links", "People"], id: \.self) { filter in
                            Text(filter)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Modern Content Section (Reference Style)
    
    // MARK: - Unified Scrollable Content (Header + Content scroll together)
    
    private var modernScrollableContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Scroll offset tracking
                    GeometryReader { scrollGeometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: scrollGeometry.frame(in: .named("scroll")).minY
                        )
                    }
                    .frame(height: 0)
                    
                    // ✅ Header scrolls WITH content (smooth unified scrolling)
                    modernHeaderSection
                        .opacity(max(0.3, min(1.0, 1.0 + (scrollOffset / 100.0))))
                        .offset(y: min(0, scrollOffset / 3.0))
                    
                    // Content based on selected tab
                    Group {
                        // Pinned section (hidden during search)
                        if selectedTab == .messages && !pinnedConversations.isEmpty && searchText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("PINNED")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1)
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)

                                ForEach(pinnedConversations) { conversation in
                                    modernConversationRow(conversation)
                                        .contextMenu {
                                            conversationContextMenu(for: conversation)
                                        }
                                }

                                // Breathing room divider before All Messages
                                Rectangle()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)

                                Text("ALL MESSAGES")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1)
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 4)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.25), value: searchText.isEmpty)
                        }

                        // Search results header
                        if !searchText.isEmpty {
                            Text("RESULTS")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(.secondary.opacity(0.6))
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                .transition(.opacity.animation(.easeIn(duration: 0.2)))
                        }

                        // Regular conversations
                        if filteredConversations.isEmpty {
                            modernEmptyState
                                .padding(.top, 60)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredConversations) { conversation in
                                    modernConversationRow(conversation)
                                        .contextMenu {
                                            conversationContextMenu(for: conversation)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                handleScrollOffset(value)
            }
            .refreshable {
                await refreshConversations()
            }
            // One-time swipe hint
            .onAppear {
                if !hasSeenSwipeHint && !filteredConversations.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showSwipeHint = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showSwipeHint = false
                                hasSeenSwipeHint = true
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                // Swipe hint tooltip
                if showSwipeHint {
                    Text("Tip: swipe conversations for more options")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Floating compose button (always visible, glass style)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    activeSheet = .newMessage
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(Color.black)
                                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                        )
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    // ✅ Modern conversation row (matches reference)
    private func modernConversationRow(_ conversation: ChatConversation) -> some View {
        Button {
            openChat(conversation)
        } label: {
            HStack(spacing: 12) {
                // ✅ Avatar (circular, 52pt like reference)
                modernAvatarView(for: conversation)
                
                // ✅ Content (name + preview)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conversation.name)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if conversation.isGroup {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // ✅ Timestamp (small, right-aligned)
                        Text(conversation.timestamp)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        // Group indicator
                        if conversation.isGroup {
                            Text("Group • ")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.tertiary)
                        }

                        Text(conversation.lastMessage)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(conversation.unreadCount > 0 ? .secondary : .tertiary)
                            .lineLimit(1)

                        Spacer()

                        // Unread: blue dot always + numeric badge if >9
                        if conversation.unreadCount > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)

                                if conversation.unreadCount > 9 {
                                    Text("\(conversation.unreadCount)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.blue))
                                }
                            }
                        }
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color(.systemBackground))
    }
    
    private func modernAvatarView(for conversation: ChatConversation) -> some View {
        Group {
            if let photoURL = conversation.profilePhotoURL, !photoURL.isEmpty, let url = URL(string: photoURL) {
                CachedAsyncImage(
                    url: url,
                    content: { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                    },
                    placeholder: {
                        fallbackAvatar(for: conversation)
                    }
                )
            } else {
                fallbackAvatar(for: conversation)
            }
        }
    }
    
    private func fallbackAvatar(for conversation: ChatConversation) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.7),
                            Color.purple.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )

            Text(conversation.name.prefix(1).uppercased())
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.white)
        }
    }
    
    // ✅ Modern empty state (adapts to search vs no messages)
    private var modernEmptyState: some View {
        VStack(spacing: 20) {
            if !searchText.isEmpty {
                // Search empty state
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.4))

                Text("No results for \"\(searchText)\"")
                    .font(.custom("OpenSans-SemiBold", size: 18))
                    .foregroundStyle(.primary)

                Button {
                    searchText = ""
                } label: {
                    Text("Clear search")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.blue)
                }
            } else {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary.opacity(0.5))

                Text("No messages yet")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)

                Text("Start a conversation with someone")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)

                Button {
                    activeSheet = .newMessage
                } label: {
                    Text("New Message")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.primary)
                        )
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Scroll Handling (Collapse on Scroll)
    
    private func handleScrollOffset(_ offset: CGFloat) {
        // Update scroll offset for smooth animations
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
            scrollOffset = offset
        }
        
        lastScrollOffset = offset
        
        // Compact header appears when scrolled down significantly
        if offset < -150 {
            if showHeader {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showHeader = false
                }
            }
        }
        // Full header when at top or scrolling up
        else if offset >= -50 {
            if !showHeader {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showHeader = true
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func openChat(_ conversation: ChatConversation) {
        withAnimation(.easeOut(duration: 0.2)) {
            activeSheet = .chat(conversation)
        }
        // haptic
        HapticManager.impact(style: .light)
    }
    
    // MARK: - Header Section (OLD - Keep for compatibility)
    
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
                    // haptic
                    HapticManager.impact(style: .light)
                } label: {
                    Label("New Message", systemImage: "bubble.left.and.bubble.right")
                }
                
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        activeSheet = .createGroup
                    }
                    // haptic
                    HapticManager.impact(style: .light)
                } label: {
                    Label("New Group", systemImage: "person.3")
                }
                
                Divider()
                
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        activeSheet = .settings
                    }
                    // haptic
                    HapticManager.impact(style: .light)
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
                    // haptic
                    HapticManager.impact(style: .light)
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
                                        dlog("\n========================================")
                                        dlog("📌 PINNED CONVERSATION TAPPED")
                                        dlog("========================================")
                                        dlog("   - Name: \(conversation.name)")
                                        dlog("   - ID: \(conversation.id)")
                                        dlog("   - Last Message: \(conversation.lastMessage)")
                                        dlog("   - Is Group: \(conversation.isGroup)")
                                        dlog("========================================")

                                        // haptic
                                        HapticManager.impact(style: .light)

                                        activeSheet = .chat(conversation)
                                        dlog("   - Set activeSheet to chat: \(conversation.name)")
                                        dlog("========================================\n")
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

                                        // Mark Read / Unread
                                        Button {
                                            if conversation.unreadCount > 0 {
                                                markConversationRead(conversation)
                                            } else {
                                                markConversationUnread(conversation)
                                            }
                                        } label: {
                                            Label(
                                                conversation.unreadCount > 0 ? "Mark Read" : "Mark Unread",
                                                systemImage: conversation.unreadCount > 0 ? "envelope.open.fill" : "envelope.badge.fill"
                                            )
                                        }
                                        .tint(.blue)
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
                                dlog("\n========================================")
                                dlog("💬 EXISTING CONVERSATION TAPPED")
                                dlog("========================================")
                                dlog("   - Name: \(conversation.name)")
                                dlog("   - ID: \(conversation.id)")
                                dlog("   - Last Message: \(conversation.lastMessage)")
                                dlog("   - Is Group: \(conversation.isGroup)")
                                dlog("========================================")

                                // haptic
                                HapticManager.impact(style: .light)

                                activeSheet = .chat(conversation)
                                dlog("   - Set activeSheet to chat: \(conversation.name)")
                                dlog("========================================\n")
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

                                // Mark Read / Unread
                                Button {
                                    if conversation.unreadCount > 0 {
                                        markConversationRead(conversation)
                                    } else {
                                        markConversationUnread(conversation)
                                    }
                                } label: {
                                    Label(
                                        conversation.unreadCount > 0 ? "Mark Read" : "Mark Unread",
                                        systemImage: conversation.unreadCount > 0 ? "envelope.open.fill" : "envelope.badge.fill"
                                    )
                                }
                                .tint(.blue)
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

        // Reset staggered entrance so it replays
        rowsVisible = false
        isRefreshing = true

        // Keep the live Firestore listener running — stopping it causes a data hole.
        // Simply reload message requests and let the existing listener deliver any
        // outstanding updates. The listener is already delivering real-time changes,
        // so a pull-to-refresh only needs to sync supplementary data.
        await loadMessageRequests()

        await MainActor.run {
            // haptic
            HapticManager.notification(type: .success)
            isRefreshing = false
            // Replay staggered entrance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                rowsVisible = true
            }
        }
    }
    
    private func refreshMessageRequests() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        dlog("🔄 Refreshing message requests...")
        
        // Reload message requests
        await loadMessageRequests()
        
        // Small delay for UX
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Haptic feedback
        await MainActor.run {
            // haptic
            HapticManager.notification(type: .success)
            isRefreshing = false
        }
        
        dlog("✅ Message requests refreshed")
    }
    
    private func refreshArchivedConversations() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        dlog("🔄 Refreshing archived conversations...")
        
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
            // haptic
            HapticManager.notification(type: .success)
            isRefreshing = false
        }
        
        dlog("✅ Archived conversations refreshed")
    }
    
    // MARK: - Conversation Management
    // P1 FIX: All swipe actions now use per-conversation keys in the existing actionInFlight Set
    // (e.g. "mute-<id>") instead of the former global isProcessing/isArchiving/isDeleting booleans.
    // This allows concurrent actions on different conversations simultaneously.

    private func muteConversation(_ conversation: ChatConversation) {
        let key = "mute-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)

        Task { @MainActor in
            defer { actionInFlight.remove(key) }

            do {
                try await FirebaseMessagingService.shared.muteConversation(conversation.id)

                // haptic
                HapticManager.notification(type: .success)

                dlog("🔕 Conversation muted: \(conversation.name)")
            } catch {
                dlog("❌ Failed to mute conversation: \(error)")
                swipeErrorMessage = "Could not mute this conversation. Please try again."
                showSwipeErrorAlert = true
            }
        }
    }

    private func unmuteConversation(_ conversation: ChatConversation) {
        let key = "unmute-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)

        Task { @MainActor in
            defer { actionInFlight.remove(key) }

            do {
                try await FirebaseMessagingService.shared.unmuteConversation(conversation.id)

                // haptic
                HapticManager.notification(type: .success)

                dlog("🔔 Conversation unmuted: \(conversation.name)")
            } catch {
                dlog("❌ Failed to unmute conversation: \(error)")
                swipeErrorMessage = "Could not unmute this conversation. Please try again."
                showSwipeErrorAlert = true
            }
        }
    }

    private func pinConversation(_ conversation: ChatConversation) {
        let key = "pin-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)

        Task { @MainActor in
            defer { actionInFlight.remove(key) }

            do {
                try await FirebaseMessagingService.shared.pinConversation(conversation.id)

                // haptic
                HapticManager.notification(type: .success)

                dlog("📌 Conversation pinned: \(conversation.name)")
            } catch {
                dlog("❌ Failed to pin conversation: \(error.localizedDescription)")
                swipeErrorMessage = error.localizedDescription.contains("3")
                    ? "You can only pin up to 3 conversations."
                    : "Could not pin this conversation. Please try again."
                showSwipeErrorAlert = true
            }
        }
    }

    private func unpinConversation(_ conversation: ChatConversation) {
        let key = "unpin-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)

        Task { @MainActor in
            defer { actionInFlight.remove(key) }

            do {
                try await FirebaseMessagingService.shared.unpinConversation(conversation.id)

                // haptic
                HapticManager.notification(type: .success)

                dlog("📌 Conversation unpinned: \(conversation.name)")
            } catch {
                dlog("❌ Failed to unpin conversation: \(error)")
                swipeErrorMessage = "Could not unpin this conversation. Please try again."
                showSwipeErrorAlert = true
            }
        }
    }

    private func reportSpam(_ conversation: ChatConversation) {
        let key = "report-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)

        Task { @MainActor in
            defer { actionInFlight.remove(key) }

            do {
                try await FirebaseMessagingService.shared.reportSpam(conversation.id, reason: "Spam or unwanted messages")

                // haptic
                HapticManager.notification(type: .success)

                dlog("⚠️ Conversation reported as spam: \(conversation.name)")
            } catch {
                dlog("❌ Failed to report conversation: \(error)")
                swipeErrorMessage = "Could not report this conversation. Please try again."
                showSwipeErrorAlert = true
            }
        }
    }

    private func deleteConversation(_ conversation: ChatConversation) {
        let key = "delete-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)

        Task { @MainActor in
            defer { actionInFlight.remove(key) }

            do {
                // Animate removal
                withAnimation(.easeOut(duration: 0.2)) {
                    // Will be removed from list automatically via Firebase listener
                }

                try await FirebaseMessagingService.shared.deleteConversation(
                    conversationId: conversation.id
                )

                // haptic
                HapticManager.notification(type: .success)

                dlog("🗑️ Deleted conversation: \(conversation.name)")
            } catch {
                dlog("❌ Error deleting conversation: \(error)")
                swipeErrorMessage = "Could not delete this conversation. Please try again."
                showSwipeErrorAlert = true
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

        // Mark Read / Unread
        Button {
            if conversation.unreadCount > 0 {
                markConversationRead(conversation)
            } else {
                markConversationUnread(conversation)
            }
        } label: {
            Label(
                conversation.unreadCount > 0 ? "Mark as Read" : "Mark as Unread",
                systemImage: conversation.unreadCount > 0 ? "envelope.open.fill" : "envelope.badge.fill"
            )
        }

        // View Profile (1:1 conversations only)
        if !conversation.isGroup, let otherUserId = conversation.otherParticipantId {
            Button {
                DeepLinkRouter.shared.navigate(to: .userProfile(userId: otherUserId))
            } label: {
                Label("View Profile", systemImage: "person.circle.fill")
            }
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

        // Block & Report (only for non-group conversations)
        if !conversation.isGroup {
            Divider()

            // Block the other participant
            if let otherUserId = conversation.otherParticipantId {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await blockUser(otherUserId)
                        } catch {
                            dlog("❌ Block failed: \(error)")
                        }
                    }
                } label: {
                    Label("Block", systemImage: "hand.raised.slash.fill")
                }
            }

            Button(role: .destructive) {
                reportSpam(conversation)
            } label: {
                Label("Report Spam", systemImage: "exclamationmark.shield.fill")
            }
        }
    }
    
    // MARK: - Archive Management
    
    private func archiveConversation(_ conversation: ChatConversation) {
        let key = "archive-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)

        Task { @MainActor in
            defer { actionInFlight.remove(key) }
            
            do {
                // Animate archiving
                withAnimation(.easeOut(duration: 0.2)) {
                    // Will move to archived tab automatically via listener
                }
                
                try await FirebaseMessagingService.shared.archiveConversation(
                    conversationId: conversation.id
                )
                
                // haptic
                HapticManager.notification(type: .success)
                
                dlog("📦 Archived conversation: \(conversation.name)")
            } catch {
                dlog("❌ Error archiving conversation: \(error)")
                swipeErrorMessage = "Failed to archive conversation. Please try again."
                showSwipeErrorAlert = true
            }
        }
    }
    
    private func unarchiveConversation(_ conversation: ChatConversation) {
        let key = "unarchive-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)

        Task { @MainActor in
            defer { actionInFlight.remove(key) }
            
            do {
                // Animate unarchiving
                withAnimation(.easeOut(duration: 0.2)) {
                    // Will move back to messages tab automatically via listener
                }
                
                try await FirebaseMessagingService.shared.unarchiveConversation(
                    conversationId: conversation.id
                )
                
                // haptic
                HapticManager.notification(type: .success)
                
                dlog("📬 Unarchived conversation: \(conversation.name)")
            } catch {
                dlog("❌ Error unarchiving conversation: \(error)")
                swipeErrorMessage = "Failed to unarchive conversation. Please try again."
                showSwipeErrorAlert = true
            }
        }
    }
    
    // MARK: - Mark Read / Unread

    private func markConversationRead(_ conversation: ChatConversation) {
        let key = "read-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)
        Task { @MainActor in
            defer { actionInFlight.remove(key) }
            do {
                try await FirebaseMessagingService.shared.clearUnreadCount(conversationId: conversation.id)
            } catch {
                dlog("❌ Error marking conversation read: \(error)")
            }
        }
    }

    private func markConversationUnread(_ conversation: ChatConversation) {
        let key = "unread-\(conversation.id)"
        guard !actionInFlight.contains(key) else { return }
        actionInFlight.insert(key)
        Task { @MainActor in
            defer { actionInFlight.remove(key) }
            do {
                try await FirebaseMessagingService.shared.markAsUnread(conversationId: conversation.id)
            } catch {
                dlog("❌ Error marking conversation unread: \(error)")
            }
        }
    }

    private var archivedContent: some View {
        Group {
            if messagingService.archivedConversations.isEmpty {
                archivedEmptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(messagingService.archivedConversations) { conversation in
                            AMENThreadRow(
                                conversation: conversation,
                                aiSummary: nil,
                                onTap: {
                                    // haptic
                                    HapticManager.impact(style: .light)
                                    activeSheet = .chat(conversation)
                                }
                            )
                            .equatable()
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
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    unarchiveConversation(conversation)
                                } label: {
                                    Label("Unarchive", systemImage: "arrow.up.bin.fill")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    conversationToDelete = conversation
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }

                            InboxSeparator()
                        }
                    }
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
                            HStack(spacing: 0) {
                                // Left accent stripe for request rows
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.blue.opacity(0.4))
                                    .frame(width: 3)
                                    .padding(.vertical, 4)

                                MessageRequestRow(request: request) { action in
                                    handleRequestAction(request: request, action: action)
                                }
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
    
    // MARK: - Conversation Cache
    
    /// Rebuilds the cached filtered/pinned conversation lists.
    /// Called on appear and whenever conversations, tab, or search text changes
    /// so the expensive dedup logic runs once, not on every body re-render.
    private func recomputeConversationCache() {
        cachedFilteredConversations = computeFilteredConversations()
        cachedPinnedConversations = computePinnedConversations()
    }

    // MARK: - Request Management
    
    private func loadMessageRequests() async {
        // Load pending message requests from Firebase
        do {
            guard Auth.auth().currentUser?.uid != nil else { return }
            
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
            
            dlog("✅ Loaded \(requests.count) message requests")
        } catch {
            dlog("❌ Error loading message requests: \(error)")
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
                dlog("❌ Error handling request action: \(error)")
                // Reload on error to restore accurate state
                await loadMessageRequests()
            }
        }
    }
    
    private func acceptMessageRequest(_ request: MessageRequest) async throws {
        dlog("✅ Accepting message request from \(request.fromUserName)")
        
        let service = FirebaseMessagingService.shared
        
        // Update the conversation status to accepted (using existing method)
        try await service.acceptMessageRequest(requestId: request.conversationId)
        
        // Mark the request as read
        try await service.markMessageRequestAsRead(requestId: request.conversationId)
        
        // Haptic feedback and smooth transition to messages tab
        await MainActor.run {
            // haptic
            HapticManager.notification(type: .success)
            
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
        
        dlog("✅ Message request accepted successfully")
    }
    
    private func declineMessageRequest(_ request: MessageRequest) async throws {
        dlog("❌ Declining message request from \(request.fromUserName)")
        
        let service = FirebaseMessagingService.shared
        
        // Delete the conversation (using existing method)
        try await service.declineMessageRequest(requestId: request.conversationId)
        
        // Haptic feedback
        await MainActor.run {
            // haptic
            HapticManager.notification(type: .warning)
        }
        
        dlog("❌ Message request declined successfully")
    }
    
    private func blockUser(_ userId: String) async throws {
        dlog("🚫 Blocking user: \(userId)")
        
        guard Auth.auth().currentUser?.uid != nil else {
            throw NSError(domain: "MessagesView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        // Block user using BlockService
        try await BlockService.shared.blockUser(userId: userId)
        
        // Remove all conversations with this user (explicit service reference)
        let messagingService = FirebaseMessagingService.shared
        try await messagingService.deleteConversationsWithUser(userId: userId)
        
        // Haptic feedback
        // haptic
        HapticManager.notification(type: .error)
        
        dlog("🚫 User blocked successfully")
    }
    
    private func reportUser(_ userId: String) async throws {
        dlog("⚠️ Reporting user: \(userId)")
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessagesView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        // Report via conversationId using the existing reportSpam service method
        if let request = messageRequests.first(where: { $0.fromUserId == userId }) {
            try await FirebaseMessagingService.shared.reportSpam(
                request.conversationId,
                reason: "Spam or inappropriate message request"
            )
            dlog("[Report] User \(userId) reported by \(currentUserId) via conversation \(request.conversationId)")
        } else {
            dlog("[Report] No message request found for user \(userId); report skipped")
        }
        
        // Also decline the request
        if let request = messageRequests.first(where: { $0.fromUserId == userId }) {
            try await declineMessageRequest(request)
        }
        
        // Haptic feedback
        await MainActor.run {
            // haptic
            HapticManager.notification(type: .error)
        }
        
        dlog("⚠️ User reported successfully")
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
                dlog("📬 Updated message requests: \(requests.count) pending")
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
        do {
            let conversationId = try await messagingService.getOrCreateDirectConversation(
                withUserId: user.id,
                userName: user.displayName
            )

            // Dismiss the search sheet
            await MainActor.run { activeSheet = nil }

            // Brief pause for the sheet dismissal animation before opening the chat
            try? await Task.sleep(nanoseconds: 300_000_000)

            await MainActor.run {
                if let conversation = conversations.first(where: { $0.id == conversationId }) {
                    activeSheet = .chat(conversation)
                } else {
                    // Conversation not yet in the live list — open with a stub that the
                    // Firestore listener will fill in momentarily.
                    let tempConversation = ChatConversation(
                        id: conversationId,
                        name: user.displayName,
                        lastMessage: "",
                        timestamp: "Just now",
                        isGroup: false,
                        unreadCount: 0,
                        avatarColor: .blue
                    )
                    activeSheet = .chat(tempConversation)
                }
                // haptic
                HapticManager.notification(type: .success)
            }

        } catch {
            dlog("❌ startConversation failed: \(error.localizedDescription)")
            await MainActor.run {
                activeSheet = nil
                // haptic
                HapticManager.notification(type: .error)
                swipeErrorMessage = "Could not start conversation. Please try again."
                showSwipeErrorAlert = true
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
                // haptic
                HapticManager.impact(style: .light)
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
                    // haptic
                    HapticManager.impact(style: .light)
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
                    if newValue.count > nameCharLimit {
                        groupName = String(newValue.prefix(nameCharLimit))
                    }
                }

            HStack {
                // Helper text
                if groupName.isEmpty {
                    Text("Tip: Short, descriptive names work best")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }

                Spacer()

                Text("\(groupName.count)/\(nameCharLimit)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(
                        groupName.isEmpty ? Color.secondary :
                        groupName.count > 45 ? Color.orange :
                        Color.green.opacity(0.7)
                    )
            }
            .animation(.easeOut(duration: 0.2), value: groupName.isEmpty)

            // Group preview line
            HStack(spacing: 6) {
                Text("Members: \(selectedUsers.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            // Inline validation checklist (shows when Create is disabled)
            if !canCreate && (groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedUsers.isEmpty) {
                VStack(alignment: .leading, spacing: 4) {
                    checklistItem(
                        text: "Add a group name",
                        satisfied: !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    checklistItem(
                        text: "Add at least 1 member",
                        satisfied: !selectedUsers.isEmpty
                    )
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeOut(duration: 0.25), value: canCreate)
            }
        }
        .padding()
    }

    private func checklistItem(text: String, satisfied: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(satisfied ? .green : Color.secondary.opacity(0.5))
            Text(text)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundColor(satisfied ? .green : Color.secondary.opacity(0.5))
        }
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
        
        // haptic
        HapticManager.impact(style: .light)
    }
    
    @ViewBuilder
    private var searchResultsSection: some View {
        if !searchText.isEmpty {
            if isSearching {
                VStack(spacing: 12) {
                    AMENLoadingIndicator()
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
                CachedAsyncImage(url: url) { image in
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
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    Text("Limit")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                }
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
            dlog("🔍 Searching for users with query: '\(searchText)'")
            let users = try await messagingService.searchUsers(query: searchText)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                dlog("✅ Found \(users.count) users")
                searchResults = users
                isSearching = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            
            dlog("❌ Error searching users: \(error)")
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
        
        // haptic
        HapticManager.impact(style: .light)
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
                
                dlog("🎨 Creating group:")
                dlog("   - Name: \(trimmedName)")
                dlog("   - Participants: \(participantIds.count)")
                dlog("   - Participant Names: \(participantNames)")
                
                // Create group conversation
                let conversationId = try await messagingService.createGroupConversation(
                    participantIds: participantIds,
                    participantNames: participantNames,
                    groupName: trimmedName
                )
                
                dlog("✅ Group created with ID: \(conversationId)")
                
                await MainActor.run {
                    // Success haptic
                    HapticManager.notification(type: .success)
                    isCreating = false
                }

                // Brief delay so the button press feels acknowledged before navigation
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

                await MainActor.run {
                    dismiss()
                    dlog("📬 Opening new group conversation: \(conversationId)")
                    MessagingCoordinator.shared.openConversation(conversationId)
                }
                
            } catch {
                dlog("❌ Error creating group: \(error)")
                
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isCreating = false
                    
                    // haptic
                    HapticManager.notification(type: .error)
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
                CachedAsyncImage(url: url) { image in
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
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        CreateGroupView()
                    } label: {
                        Label("New Group", systemImage: "person.3")
                            .labelStyle(.iconOnly)
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
                AMENLoadingIndicator(dotSize: 7, spacing: 6, bounceHeight: 8)
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
                        // haptic
                        HapticManager.impact(style: .light)
                        
                        dlog("\n========================================")
                        dlog("👤 USER SELECTED FROM SEARCH")
                        dlog("========================================")
                        dlog("   - Name: \(user.displayName)")
                        dlog("   - ID: \(user.id)")
                        dlog("   - Username: \(user.username ?? "none")")
                        dlog("========================================\n")
                        
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
                dlog("🔍 Searching for users with query: '\(searchText)'")
                
                let users = try await messagingService.searchUsers(query: searchText)
                
                guard !Task.isCancelled else {
                    dlog("⚠️ Search cancelled")
                    return
                }
                
                // Convert ContactUser to SearchableUser
                await MainActor.run {
                    searchResults = users.map { SearchableUser(from: $0) }
                    isSearching = false
                    
                    dlog("✅ Found \(users.count) users")
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    dlog("❌ Search error: \(error)")
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
                    CachedAsyncImage(url: url) { image in
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
                AMENLoadingIndicator(dotSize: 7, spacing: 6, bounceHeight: 8)
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
                dlog("🔍 Searching messages across all conversations for: '\(query)'")
                
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
                    dlog("✅ Found \(filteredResults.count) matching messages")
                }
                
            } catch {
                guard !Task.isCancelled else { return }
                
                dlog("❌ Error searching messages: \(error)")
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
                guard !hasAppeared else { return }
                hasAppeared = true
                
                // Start listening to real-time conversations from Firebase
                messagingService.startListeningToConversations()
                messagingService.startListeningToArchivedConversations()
                
                // Fetch and cache current user's name for messaging
                Task {
                    await messagingService.fetchAndCacheCurrentUserName()
                    await loadMessageRequests()
                    startListeningToMessageRequests()
                }
            }
            .onDisappear {
                // P0-3 FIX: DO NOT stop conversation listeners when view disappears
                // They must stay active to keep thread list updated in real-time
                // Only stop message request listener since it's UI-specific
                stopListeningToMessageRequests()
                
                // Note: hasAppeared is intentionally NOT reset here
                // This prevents duplicate listener setup when navigating back
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
    @Environment(\.mainTabSelection) private var mainTabSelection
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                mainTabSelection.wrappedValue = 0  // Navigate to home tab
            }
            // haptic
            HapticManager.impact(style: .light)
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
        
        // haptic
        HapticManager.impact(style: .light)
        
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
                dlog("❌ Error sending message: \(error)")
                // Show error to user
                errorMessage = "Failed to send message. Please check your connection and try again."
                showErrorAlert = true
                
                // Restore message text if send failed
                messageText = textToSend
                selectedImages = imagesToSend
                
                // haptic
                HapticManager.notification(type: .error)
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
            dlog("⚠️ Message not found in list, skipping reaction")
            return
        }
        
        // haptic
        HapticManager.impact(style: .light)
        
        // Add reaction to Firebase
        Task { @MainActor in
            do {
                try await FirebaseMessagingService.shared.addReaction(
                    conversationId: conversation.id,
                    messageId: message.id,
                    emoji: emoji
                )
            } catch {
                dlog("❌ Error adding reaction: \(error)")
                errorMessage = "Failed to add reaction."
                showErrorAlert = true
            }
        }
    }
}


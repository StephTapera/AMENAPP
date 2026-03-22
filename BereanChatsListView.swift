//
//  BereanChatsListView.swift
//  AMENAPP
//
//  Smart conversation history for Berean AI
//  Instagram/Threads-inspired UI with search, filter, pin, archive
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Conversation history list for Berean AI — smart, searchable, fully-wired
struct BereanChatsListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bereanVM = BereanViewModel()
    
    // UI State
    @State private var searchText = ""
    @State private var showFilterMenu = false
    @State private var selectedFilter: ConversationFilter = .all
    @State private var showNewChatView = false
    @State private var selectedConversation: SavedConversation?
    @State private var conversationToDelete: SavedConversation?
    @State private var showDeleteConfirm = false
    @State private var showSettingsMenu = false
    
    // Smart features
    @State private var groupByDate = true
    @State private var showPinnedSection = true
    @State private var animateIn = false
    
    enum ConversationFilter: String, CaseIterable {
        case all = "All"
        case pinned = "Pinned"
        case recent = "Recent"
        case archived = "Archived"
        
        var icon: String {
            switch self {
            case .all: return "tray.fill"
            case .pinned: return "pin.fill"
            case .recent: return "clock.fill"
            case .archived: return "archivebox.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background matching screenshot
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    if !bereanVM.savedConversations.isEmpty {
                        searchBarView
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                    }
                    
                    // Content
                    if filteredConversations.isEmpty {
                        emptyStateView
                    } else {
                        conversationListView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Chats")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            selectedFilter = .all
                        } label: {
                            Label("All Chats", systemImage: "tray.fill")
                        }
                        
                        Button {
                            selectedFilter = .pinned
                        } label: {
                            Label("Pinned", systemImage: "pin.fill")
                        }
                        
                        Button {
                            selectedFilter = .recent
                        } label: {
                            Label("Recent", systemImage: "clock.fill")
                        }
                        
                        Divider()
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                groupByDate.toggle()
                            }
                        } label: {
                            Label(groupByDate ? "Ungroup by Date" : "Group by Date", 
                                  systemImage: groupByDate ? "calendar.badge.minus" : "calendar.badge.plus")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            if !bereanVM.savedConversations.isEmpty {
                                showDeleteConfirm = true
                            }
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                    }
                }
            }
            .sheet(item: $selectedConversation) { conversation in
                BereanAIAssistantView()
                    .onAppear {
                        bereanVM.loadConversation(conversation)
                    }
            }
            .alert("Delete All Conversations", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    bereanVM.clearAllConversations()
                }
            } message: {
                Text("This will permanently delete all your Berean AI conversations. This action cannot be undone.")
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                    animateIn = true
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Floating + button to create new chat
            newChatButton
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 10) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            
            // Text field
            TextField("Search conversations", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            
            // Clear button
            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Sparkle icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.4, blue: 1.0),
                                Color(red: 0.4, green: 0.3, blue: 0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .opacity(0.15)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.7, green: 0.5, blue: 1.0),
                                Color(red: 0.5, green: 0.4, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(animateIn ? 1.0 : 0.8)
            .opacity(animateIn ? 1.0 : 0.0)
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No chats yet" : "No results found")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundColor(.white)
                
                Text(searchText.isEmpty ? 
                     "Tap + to start a conversation with Berean AI" :
                     "Try a different search term")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .opacity(animateIn ? 1.0 : 0.0)
            .offset(y: animateIn ? 0 : 20)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Conversation List
    
    private var conversationListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if groupByDate {
                    ForEach(groupedConversations.keys.sorted(by: >), id: \.self) { date in
                        Section {
                            ForEach(groupedConversations[date] ?? []) { conversation in
                                conversationRow(conversation)
                            }
                        } header: {
                            HStack {
                                Text(dateHeaderText(for: date))
                                    .font(.custom("OpenSans-Bold", size: 13))
                                    .foregroundColor(.white.opacity(0.5))
                                    .textCase(.uppercase)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                        }
                    }
                } else {
                    ForEach(filteredConversations) { conversation in
                        conversationRow(conversation)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }
    
    private func conversationRow(_ conversation: SavedConversation) -> some View {
        Button {
            selectedConversation = conversation
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: conversation.isPinned ? 
                                    [Color.purple.opacity(0.3), Color.blue.opacity(0.3)] :
                                    [Color.white.opacity(0.08), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Text(conversationEmoji(for: conversation))
                        .font(.system(size: 24))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(conversation.title)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.purple.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Text(timeAgoText(from: conversation.date))
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Text(conversationPreview(for: conversation))
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.02))
        }
        .buttonStyle(ConversationRowButtonStyle())
        .contextMenu {
            Button {
                bereanVM.togglePin(conversation)
            } label: {
                Label(conversation.isPinned ? "Unpin" : "Pin", 
                      systemImage: conversation.isPinned ? "pin.slash" : "pin")
            }
            
            Button {
                bereanVM.toggleStar(conversation)
            } label: {
                Label(conversation.isStarred ? "Unstar" : "Star", 
                      systemImage: conversation.isStarred ? "star.slash" : "star")
            }
            
            Divider()
            
            Button(role: .destructive) {
                conversationToDelete = conversation
                bereanVM.deleteConversation(conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                conversationToDelete = conversation
                bereanVM.deleteConversation(conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                bereanVM.togglePin(conversation)
            } label: {
                Label(conversation.isPinned ? "Unpin" : "Pin", 
                      systemImage: conversation.isPinned ? "pin.slash" : "pin")
            }
            .tint(.purple)
        }
    }
    
    // MARK: - New Chat Button
    
    private var newChatButton: some View {
        Button {
            showNewChatView = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.4, blue: 1.0),
                                Color(red: 0.5, green: 0.3, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.purple.opacity(0.4), radius: 12, x: 0, y: 4)
                
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .scaleEffect(animateIn ? 1.0 : 0.5)
        .opacity(animateIn ? 1.0 : 0.0)
        .fullScreenCover(isPresented: $showNewChatView) {
            BereanAIAssistantView()
        }
    }
    
    // MARK: - Helpers
    
    private var filteredConversations: [SavedConversation] {
        var conversations = bereanVM.savedConversations
        
        // Apply search filter
        if !searchText.isEmpty {
            conversations = conversations.filter { conversation in
                conversation.title.localizedCaseInsensitiveContains(searchText) ||
                conversationPreview(for: conversation).localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply category filter
        switch selectedFilter {
        case .all:
            break
        case .pinned:
            conversations = conversations.filter { $0.isPinned }
        case .recent:
            conversations = conversations.filter { 
                Calendar.current.isDateInToday($0.date) ||
                Calendar.current.isDateInYesterday($0.date)
            }
        case .archived:
            // SavedConversation doesn't have isArchived, skip for now
            break
        }
        
        return conversations
    }
    
    private var groupedConversations: [String: [SavedConversation]] {
        Dictionary(grouping: filteredConversations) { conversation in
            dateGroupKey(for: conversation.date)
        }
    }
    
    private func dateGroupKey(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateComponents([.day], from: date, to: Date()).day ?? 0 < 7 {
            return "This Week"
        } else if calendar.dateComponents([.day], from: date, to: Date()).day ?? 0 < 30 {
            return "This Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
    }
    
    private func conversationEmoji(for conversation: SavedConversation) -> String {
        // Smart emoji based on conversation title
        let title = conversation.title.lowercased()
        if title.contains("pray") { return "🙏" }
        if title.contains("jesus") || title.contains("christ") { return "✝️" }
        if title.contains("love") { return "❤️" }
        if title.contains("faith") { return "💫" }
        if title.contains("grace") { return "💚" }
        if title.contains("psalm") { return "🎵" }
        if title.contains("gospel") || title.contains("john") || title.contains("matthew") { return "📖" }
        if title.contains("genesis") || title.contains("creation") { return "🌟" }
        return "✨"
    }
    
    private func conversationPreview(for conversation: SavedConversation) -> String {
        // Generate preview from last user message or first AI response
        if let lastUserMsg = conversation.messages.last(where: { $0.isFromUser }) {
            return lastUserMsg.content
        } else if let firstAIMsg = conversation.messages.first(where: { !$0.isFromUser }) {
            return String(firstAIMsg.content.prefix(100))
        }
        return "No messages"
    }
    
    private func dateHeaderText(for groupKey: String) -> String {
        groupKey
    }
    
    private func timeAgoText(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return "\(days)d"
        } else if let weeks = calendar.dateComponents([.weekOfYear], from: date, to: now).weekOfYear, weeks < 4 {
            return "\(weeks)w"
        } else if let months = calendar.dateComponents([.month], from: date, to: now).month, months < 12 {
            return "\(months)mo"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Button Style

struct ConversationRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.white.opacity(configuration.isPressed ? 0.05 : 0.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

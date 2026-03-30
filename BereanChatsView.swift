// BereanChatsView.swift
// AMENAPP
//
// Chat history screen for Berean AI.
// Dark glassmorphic card grid — pure black background.

import SwiftUI

// MARK: - Data Model

struct BereanChat: Identifiable, Codable {
    let id: UUID
    var title: String
    var preview: String
    var timestamp: Date
    var messageCount: Int
    var isPinned: Bool
    var isNew: Bool

    static func new() -> BereanChat {
        BereanChat(
            id: UUID(),
            title: "Chat — \(Date().formatted(.dateTime.month(.abbreviated).day()))",
            preview: "",
            timestamp: Date(),
            messageCount: 0,
            isPinned: false,
            isNew: true
        )
    }
}

// MARK: - Date Helper

private extension Date {
    var relativeFormatted: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            let mins = Int(Date().timeIntervalSince(self) / 60)
            if mins < 1 { return "just now" }
            if mins < 60 { return "\(mins)m ago" }
            return "\(mins / 60)h ago"
        }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        return self.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Persistence

private enum BereanChatStore {
    static let key = "amen_berean_chats_v1"

    static func load() -> [BereanChat] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let chats = try? JSONDecoder().decode([BereanChat].self, from: data)
        else { return [] }
        return chats
    }

    static func save(_ chats: [BereanChat]) {
        guard let data = try? JSONEncoder().encode(chats) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - BereanChatsView

struct BereanChatsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var chats: [BereanChat] = []
    @State private var searchQuery = ""
    @State private var showSearch = false
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showArchived = false
    @State private var confirmClearAll = false
    @State private var showProfile = false

    @State private var selectedChat: BereanChat? = nil
    @State private var showChatDetail = false

    @State private var fabScale: CGFloat = 1.0

    @State private var showVoice = false
    @State private var showTopics = false

    private var filteredChats: [BereanChat] {
        guard !searchQuery.isEmpty else { return chats }
        return chats.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.preview.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    searchBar
                    chatGrid
                    Spacer(minLength: 0)
                }

                // Bottom toolbar pinned above home indicator
                VStack {
                    Spacer()
                    bottomToolbar
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .navigationDestination(isPresented: $showChatDetail) {
                if let chat = selectedChat {
                    BereanChatDetailView(chat: Binding(
                        get: { chat },
                        set: { updated in
                            if let idx = chats.firstIndex(where: { $0.id == updated.id }) {
                                chats[idx] = updated
                                BereanChatStore.save(chats)
                            }
                        }
                    ))
                }
            }
        }
        .onAppear { chats = BereanChatStore.load() }
        .confirmationDialog("Clear all chats?", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { chats = [] }
                BereanChatStore.save(chats)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { showProfile = true } label: {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.system(size: 16))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Chats")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Menu {
                Button("Select Chats", systemImage: "checkmark.circle") {
                    selectionMode = true
                }
                Button("Archived", systemImage: "archivebox") {
                    showArchived = true
                }
                Divider()
                Button("Clear All", systemImage: "trash", role: .destructive) {
                    confirmClearAll = true
                }
            } label: {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.system(size: 16))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        Group {
            if showSearch {
                TextField("Search chats...", text: $searchQuery)
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                    .tint(.purple)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }
        }
        .offset(y: showSearch ? 0 : -20)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: showSearch)
    }

    // MARK: - Chat Grid

    private var chatGrid: some View {
        ScrollView(showsIndicators: false) {
            // Pull-down shows search bar
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .named("scroll")).minY) { _, y in
                        if y > 20 && !showSearch {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                showSearch = true
                            }
                        }
                    }
            }
            .frame(height: 0)

            if chats.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(Array(filteredChats.enumerated()), id: \.element.id) { index, chat in
                        ChatCardView(
                            chat: chat,
                            index: index,
                            selectionMode: selectionMode,
                            isSelected: selectedIDs.contains(chat.id),
                            onTap: {
                                if selectionMode {
                                    toggleSelection(chat.id)
                                } else {
                                    openChat(chat)
                                }
                            },
                            onDelete: { deleteChat(chat) },
                            onRename: { rename(chat) },
                            onPin: { pin(chat) }
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 120)
            }
        }
        .coordinateSpace(name: "scroll")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.15))
                .symbolEffect(.pulse)
            Text("No chats yet")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
            Text("Tap + to start a conversation\nwith Berean AI")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            BereanToolbarButton(icon: "waveform", label: "voice") { showVoice = true }
            BereanToolbarButton(icon: "square.grid.2x2", label: "topics") { showTopics = true }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.2)
                    .frame(width: 36, height: 36)
                Text("\(chats.count)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }

            BereanToolbarButton(icon: "doc.on.doc", label: "copy") { duplicateLastChat() }

            Spacer()

            // FAB — New chat
            Button(action: createNewChat) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#8B5CF6"), Color(hex: "#6D28D9")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color(hex: "#7C3AED").opacity(0.5), radius: 12, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(fabScale)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.01)) // transparent safe area cover
    }

    // MARK: - Actions

    private func createNewChat() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.45)) { fabScale = 0.88 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.1)) { fabScale = 1.0 }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let newChat = BereanChat.new()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            chats.insert(newChat, at: 0)
        }
        BereanChatStore.save(chats)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            selectedChat = newChat
            showChatDetail = true
        }
    }

    private func deleteChat(_ chat: BereanChat) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            chats.removeAll { $0.id == chat.id }
        }
        BereanChatStore.save(chats)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func openChat(_ chat: BereanChat) {
        selectedChat = chat
        showChatDetail = true
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func rename(_ chat: BereanChat) {
        // Rename handled inside ChatCardView long-press context menu
    }

    private func pin(_ chat: BereanChat) {
        if let idx = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[idx].isPinned.toggle()
            BereanChatStore.save(chats)
        }
    }

    private func duplicateLastChat() {
        guard let last = chats.first else { return }
        var copy = last
        copy = BereanChat(
            id: UUID(),
            title: last.title + " (copy)",
            preview: last.preview,
            timestamp: Date(),
            messageCount: last.messageCount,
            isPinned: false,
            isNew: last.isNew
        )
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            chats.insert(copy, at: 0)
        }
        BereanChatStore.save(chats)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Chat Card View

private struct ChatCardView: View {
    let chat: BereanChat
    let index: Int
    let selectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void
    let onPin: () -> Void

    @State private var appeared = false
    @State private var renaming = false
    @State private var newTitle = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardBody
            if selectionMode {
                selectionOverlay
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .scaleEffect(appeared ? 1 : 0.94)
        .onAppear {
            withAnimation(
                .spring(response: 0.45, dampingFraction: 0.72)
                .delay(Double(index) * 0.07)
            ) { appeared = true }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renaming = true; newTitle = chat.title }
            Button(chat.isPinned ? "Unpin" : "Pin", systemImage: "pin") { onPin() }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
        .alert("Rename Chat", isPresented: $renaming) {
            TextField("Chat name", text: $newTitle)
            Button("Rename") { /* parent would handle via binding */ }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(chat.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: "#8B5CF6"))
                    }
                }
                Spacer()
                Button(action: onDelete) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Bottom: preview + timestamp
            VStack(alignment: .trailing, spacing: 2) {
                if chat.isNew {
                    Text("New chat")
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(chat.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(chat.timestamp.relativeFormatted)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .onTapGesture { onTap() }
    }

    private var selectionOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color(hex: "#8B5CF6") : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 0.5)

            if isSelected {
                Circle()
                    .fill(Color(hex: "#8B5CF6"))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Toolbar Button

struct BereanToolbarButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.25)) { pressed = false }
            }
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, height: 44)
                .scaleEffect(pressed ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Berean Chat Detail (placeholder wrapper)

struct BereanChatDetailView: View {
    @Binding var chat: BereanChat

    var body: some View {
        BereanAIAssistantView(seedMessage: chat.isNew ? nil : chat.preview)
            .navigationBarTitleDisplayMode(.inline)
    }
}

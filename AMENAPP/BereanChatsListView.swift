//
//  BereanChatsListView.swift
//  AMENAPP
//
//  Liquid Glass conversations panel for Berean AI.
//  Visual redesign: neumorphic → translucent glass on white.
//  Functionality, navigation, and data loading unchanged.
//

import SwiftUI

// MARK: - Models (unchanged)

struct BereanChatListItem: Identifiable {
    let id: String
    let title: String
    let translation: String
    let date: Date
    var isBookmarked: Bool = false
}

// MARK: - Main View

struct BereanChatsListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bereanVM = BereanViewModel()
    @State private var searchText = ""
    @State private var conversations: [BereanChatListItem] = []
    @State private var showNewConversation = false
    @State private var animateIn = false
    @State private var showCollectionsSheet = false

    var filtered: [BereanChatListItem] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            // Pure white base — Liquid Glass philosophy
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        newConversationButton
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        if !filtered.isEmpty {
                            sectionLabel("RECENT")
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                                .padding(.bottom, 8)

                            conversationList
                                .padding(.horizontal, 20)
                        } else if !searchText.isEmpty {
                            emptySearchState
                                .padding(.top, 40)
                        }

                        sectionLabel("TOOLS")
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                            .padding(.bottom, 8)

                        toolsList
                            .padding(.horizontal, 20)

                        clearAllRow
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 100)
                    }
                }
            }
        }
        .onAppear {
            loadConversations()
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.8))) {
                animateIn = true
            }
        }
        .sheet(isPresented: $showCollectionsSheet) {
            BereanChatCollectionsSheet()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Conversations")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(conversations.count) saved")
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCollectionsSheet = true
                } label: {
                    Image(systemName: "folder")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                }

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.systemScaled(14))
            TextField("Search conversations", text: $searchText)
                .font(.systemScaled(15))
                .foregroundStyle(.primary)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.systemScaled(14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: - New Conversation

    private var newConversationButton: some View {
        Button {
            showNewConversation = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.background)
                }

                Text("New Conversation")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showNewConversation) {
            BereanChatView()
        }
    }

    // MARK: - Section Label

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(1.2)
            Spacer()
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        VStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, convo in
                conversationRow(convo, isLast: index == filtered.count - 1)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func conversationRow(_ convo: BereanChatListItem, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(convo.title)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(convo.translation)
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))

                    Text(convo.date.relativeFormatted)
                        .font(.systemScaled(11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, 68)
                    .opacity(0.5)
            }
        }
    }

    // MARK: - Tools List

    private var toolsList: some View {
        VStack(spacing: 0) {
            toolRow(icon: "bookmark.fill", title: "Saved Messages", isLast: false)
            toolRow(icon: "book.closed.fill", title: "Bible Translation", isLast: false)
            toolRow(icon: "questionmark.circle.fill", title: "Berean Tutorial", isLast: true)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func toolRow(icon: String, title: String, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.systemScaled(15, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .medium))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, 68)
                    .opacity(0.5)
            }
        }
    }

    // MARK: - Clear All

    private var clearAllRow: some View {
        Button {
            bereanVM.clearAllData()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                        .frame(width: 38, height: 38)
                    Image(systemName: "trash")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.7))
                }

                Text("Clear All Conversations")
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(Color.red.opacity(0.75))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty Search State

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(32))
                .foregroundStyle(.quaternary)
            Text("No results for \"\(searchText)\"")
                .font(.systemScaled(15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load

    private func loadConversations() {
        conversations = bereanVM.savedConversations.map { saved in
            BereanChatListItem(
                id: saved.id.uuidString,
                title: saved.title,
                translation: "KJV", // TODO(legal): was ESV (Crossway, copyrighted) — changed to KJV per AMEN-CONTENT-001
                date: saved.date
            )
        }
    }
}

// MARK: - Collections Sheet

private struct BereanChatCollectionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Label("All Conversations", systemImage: "bubble.left.and.bubble.right")
                Label("Saved", systemImage: "bookmark.fill")
                Label("Scripture Study", systemImage: "book.fill")
                Label("Prayer", systemImage: "hands.and.sparkles.fill")
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeFormatted: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 86400 { return "Today" }
        if diff < 172800 { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}

// MARK: - Preview

#Preview {
    BereanChatsListView()
}

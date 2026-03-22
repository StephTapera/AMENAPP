//
//  BereanChatsListView.swift
//  AMENAPP
//
//  Neumorphic conversation history for Berean AI
//

import SwiftUI

// MARK: - Neumorphic Helpers

private let neuBackground = Color(red: 0.94, green: 0.94, blue: 0.96)
private let neuDark = Color(red: 0.78, green: 0.78, blue: 0.82).opacity(0.8)
private let neuLight = Color.white.opacity(0.95)

struct NeumorphicCard: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(neuBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: neuDark, radius: 8, x: 4, y: 4)
            .shadow(color: neuLight, radius: 8, x: -4, y: -4)
    }
}

struct NeumorphicInset: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(neuBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(neuLight, lineWidth: 1)
                    .blur(radius: 1)
                    .offset(x: -1, y: -1)
                    .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(neuDark, lineWidth: 1)
                    .blur(radius: 1)
                    .offset(x: 1, y: 1)
                    .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
    }
}

extension View {
    func neuCard(radius: CGFloat = 16) -> some View { modifier(NeumorphicCard(radius: radius)) }
    func neuInset(radius: CGFloat = 12) -> some View { modifier(NeumorphicInset(radius: radius)) }
}

// MARK: - Models

struct BereanConversation: Identifiable {
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
    @State private var conversations: [BereanConversation] = []
    @State private var showNewConversation = false
    @State private var animateIn = false

    var filtered: [BereanConversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            neuBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                // Search
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // Suggest pill
                suggestPill
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // New Conversation
                        newConversationRow
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        // Recent Section
                        if !filtered.isEmpty {
                            sectionHeader("RECENT")
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                                .padding(.bottom, 8)

                            conversationList
                                .padding(.horizontal, 20)
                        }

                        // Tools Section
                        sectionHeader("TOOLS")
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        toolsList
                            .padding(.horizontal, 20)

                        // Clear All
                        clearAllButton
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 100)
                    }
                }
            }

            // Floating Ask Button
            VStack {
                Spacer()
                floatingAskButton
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            loadConversations()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                animateIn = true
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 40, height: 40)
                    .neuCard(radius: 12)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Conversations")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(white: 0.2))
                Text("\(conversations.count) saved")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    // folder action
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 40, height: 40)
                        .neuCard(radius: 12)
                }

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 40, height: 40)
                        .neuCard(radius: 12)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 15))
            TextField("Search conversations...", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(Color(white: 0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .neuInset()
    }

    // MARK: - Suggest Pill

    private var suggestPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.3, green: 0.7, blue: 0.5))
            Text("Suggest for you")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(white: 0.3))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.95, blue: 0.88),
                    Color(red: 0.86, green: 0.90, blue: 0.98)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: neuDark, radius: 6, x: 3, y: 3)
        .shadow(color: neuLight, radius: 6, x: -3, y: -3)
    }

    // MARK: - New Conversation Row

    private var newConversationRow: some View {
        Button {
            showNewConversation = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.42, blue: 0.32))
                        .frame(width: 44, height: 44)
                        .shadow(color: Color(red: 0.98, green: 0.42, blue: 0.32).opacity(0.4), radius: 8, x: 0, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text("New Conversation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(white: 0.2))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .neuCard()
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showNewConversation) {
            BereanAIAssistantView()
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(white: 0.55))
                .kerning(1.2)
            Spacer()
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        VStack(spacing: 2) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, convo in
                conversationRow(convo, isLast: index == filtered.count - 1)
            }
        }
        .neuCard()
    }

    private func conversationRow(_ convo: BereanConversation, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(neuBackground)
                    .frame(width: 40, height: 40)
                    .shadow(color: neuDark, radius: 4, x: 2, y: 2)
                    .shadow(color: neuLight, radius: 4, x: -2, y: -2)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(convo.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(white: 0.2))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(convo.translation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.98, green: 0.42, blue: 0.32))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color(red: 0.98, green: 0.42, blue: 0.32).opacity(0.1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(convo.date.relativeFormatted)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(neuBackground)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, 70)
            }
        }
    }

    // MARK: - Tools List

    private var toolsList: some View {
        VStack(spacing: 2) {
            toolRow(icon: "bookmark.fill", iconColor: Color(red: 0.35, green: 0.5, blue: 0.95), title: "Saved Messages", isLast: false)
            toolRow(icon: "book.closed.fill", iconColor: Color(red: 0.98, green: 0.42, blue: 0.32), title: "Bible Translation", isLast: false)
            toolRow(icon: "questionmark.circle.fill", iconColor: Color(red: 0.3, green: 0.7, blue: 0.5), title: "Berean Tutorial", isLast: true)
        }
        .neuCard()
    }

    private func toolRow(icon: String, iconColor: Color, title: String, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(neuBackground)
                    .frame(width: 40, height: 40)
                    .shadow(color: neuDark, radius: 4, x: 2, y: 2)
                    .shadow(color: neuLight, radius: 4, x: -2, y: -2)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(white: 0.2))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(white: 0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(neuBackground)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, 70)
            }
        }
    }

    // MARK: - Clear All

    private var clearAllButton: some View {
        Button {
            bereanVM.clearAllData()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(neuBackground)
                        .frame(width: 40, height: 40)
                        .shadow(color: neuDark, radius: 4, x: 2, y: 2)
                        .shadow(color: neuLight, radius: 4, x: -2, y: -2)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 0.98, green: 0.42, blue: 0.32))
                }

                Text("Clear All Conversations")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.98, green: 0.42, blue: 0.32))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .neuCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Floating Ask Button

    private var floatingAskButton: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(neuBackground)
                    .frame(width: 56, height: 56)
                    .shadow(color: neuDark, radius: 10, x: 5, y: 5)
                    .shadow(color: neuLight, radius: 10, x: -5, y: -5)

                // Decorative ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.7, blue: 0.5).opacity(0.6),
                                Color(red: 0.35, green: 0.5, blue: 0.95).opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(Color(white: 0.35))
            }

            Text("ask anything...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Load

    private func loadConversations() {
        // Load from existing BereanViewModel saved conversations
        conversations = bereanVM.savedConversations.map { saved in
            BereanConversation(
                id: saved.id.uuidString,
                title: saved.title,
                translation: "ESV",
                date: saved.date
            )
        }
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

// BereanStudyHomeView.swift
// AMENAPP
//
// The Berean 5-tab study experience hub:
//   Chat | Study | Journey | Reflect | Discuss
//
// Entry point from BereanHomeView when user taps a mode.
// Liquid Glass design — white, black hierarchy, minimal chrome.

import SwiftUI

// MARK: - Berean Tab

enum BereanTab: String, CaseIterable, Identifiable {
    case chat    = "Chat"
    case study   = "Study"
    case journey = "Journey"
    case reflect = "Reflect"
    case discuss = "Discuss"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat:    return "bubble.left.and.bubble.right"
        case .study:   return "book.pages"
        case .journey: return "map"
        case .reflect: return "sparkles"
        case .discuss: return "person.2"
        }
    }

    var subtitle: String {
        switch self {
        case .chat:    return "Ask anything"
        case .study:   return "Deep Scripture study"
        case .journey: return "Your formation path"
        case .reflect: return "Private journaling"
        case .discuss: return "Talk to a leader"
        }
    }
}

// MARK: - BereanStudyHomeView

struct BereanStudyHomeView: View {
    @State private var selectedTab: BereanTab = .chat
    @State private var showNewConversation = false
    @State private var newConversationPrompt: String? = nil
    @State private var showScriptureSearch = false
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .top) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                studyTopBar

                // Tab selector
                bereanTabBar
                    .padding(.top, 2)

                Divider()
                    .foregroundColor(Color.black.opacity(0.06))

                // Tab content
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showNewConversation) {
            BereanConversationView(initialPrompt: newConversationPrompt)
        }
        .sheet(isPresented: $showScriptureSearch) {
            BereanScriptureSearchSheet { ref in
                newConversationPrompt = "Let's study \(ref)"
                showScriptureSearch = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showNewConversation = true
                }
            }
        }
    }

    // MARK: - Top Bar

    private var studyTopBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Berean")
                    .font(AMENFont.bold(26))
                    .foregroundColor(.primary)
                Text(selectedTab.subtitle)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.secondary)
                    .transition(.opacity)
                    .id(selectedTab)
            }
            .animation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.8)), value: selectedTab)

            Spacer()

            // Scripture search shortcut
            Button {
                showScriptureSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
            }

            // New conversation
            Button {
                newConversationPrompt = nil
                showNewConversation = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17))
                    .foregroundColor(.black)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Bar

    private var bereanTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(BereanTab.allCases) { tab in
                    bereanTabPill(tab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func bereanTabPill(_ tab: BereanTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(tab.rawValue)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundColor(isSelected ? .black : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
                            .matchedGeometryEffect(id: "berean_tab", in: tabNamespace)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.5)
                    }
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.black.opacity(0.08) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .chat:
            BereanChatListTab(onNewChat: {
                newConversationPrompt = nil
                showNewConversation = true
            })

        case .study:
            BereanStudyTab(onStudyPassage: { ref in
                newConversationPrompt = "Let's study \(ref)"
                showNewConversation = true
            })

        case .journey:
            DiscipleshipJourneyView()

        case .reflect:
            BereanReflectTab()

        case .discuss:
            BereanDiscussTab()
        }
    }
}

// MARK: - Chat List Tab

private struct BereanChatListTab: View {
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Quick-start prompts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(quickPrompts, id: \.self) { prompt in
                        BereanSuggestionChip(text: prompt, icon: "bubble.left", onTap: onNewChat)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.top, 16)

            Divider().padding(.horizontal, 18)

            // Recents pulled from session manager
            BereanRecentChatsList()

            Spacer()
        }
    }

    private let quickPrompts = [
        "Open Romans 8",
        "Help me pray about anxiety",
        "What is justification?",
        "How do I forgive?",
        "Study Psalm 23",
    ]
}

// MARK: - Study Tab

private struct BereanStudyTab: View {
    let onStudyPassage: (String) -> Void
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Passage entry
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study a Passage")
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 18)

                    HStack {
                        TextField("e.g. Romans 5:3 or John 3:16", text: $searchText)
                            .font(AMENFont.regular(15))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .submitLabel(.search)
                            .onSubmit { if !searchText.isEmpty { onStudyPassage(searchText) } }

                        Button {
                            if !searchText.isEmpty { onStudyPassage(searchText) }
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, 18)
                }

                // Featured study paths
                VStack(alignment: .leading, spacing: 10) {
                    Text("Featured Studies")
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 18)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(featuredStudies, id: \.title) { study in
                                BereanFeaturedStudyCard(study: study) {
                                    onStudyPassage(study.passage)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private let featuredStudies: [(title: String, passage: String, theme: String)] = [
        (title: "Suffering & Hope", passage: "Romans 5:3–5", theme: "Endurance"),
        (title: "Fear Not", passage: "Isaiah 41:10", theme: "Courage"),
        (title: "The Good Shepherd", passage: "John 10:11–18", theme: "Provision"),
        (title: "Walking in Light", passage: "1 John 1:5–9", theme: "Holiness"),
    ]
}

private struct BereanFeaturedStudyCard: View {
    let study: (title: String, passage: String, theme: String)
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(study.theme.uppercased())
                    .font(AMENFont.semiBold(10))
                    .foregroundColor(.secondary)
                    .kerning(0.8)
                Text(study.title)
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.primary)
                Text(study.passage)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(width: 160)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reflect Tab

private struct BereanReflectTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .padding(.top, 60)

            Text("Private Reflections")
                .font(AMENFont.semiBold(18))

            Text("Your reflections are saved privately. Only you can see them, unless you choose to share with a connected leader.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Discuss Tab

private struct BereanDiscussTab: View {
    var body: some View {
        BereanDiscussTabContent()
    }
}

private struct BereanDiscussTabContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connect with a Leader")
                    .font(AMENFont.semiBold(18))
                    .padding(.horizontal, 18)
                    .padding(.top, 24)

                Text("Berean is a study companion, not a substitute for pastoral wisdom. These connections help you bring what you've been studying to the people who know you.")
                    .font(AMENFont.regular(14))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)

                // Leader connection options
                VStack(spacing: 10) {
                    BereanLeaderOptionRow(
                        icon: "cross.fill",
                        title: "Talk to Your Pastor",
                        subtitle: "Connect via AMEN or share a reflection note",
                        color: Color(red: 0.18, green: 0.44, blue: 0.80)
                    )
                    BereanLeaderOptionRow(
                        icon: "person.2.fill",
                        title: "Reach Out to a Mentor",
                        subtitle: "Someone who walks with you in your faith",
                        color: Color(red: 0.22, green: 0.62, blue: 0.28)
                    )
                    BereanLeaderOptionRow(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "Find a Counselor",
                        subtitle: "Christian counseling for deeper support",
                        color: Color(red: 0.52, green: 0.26, blue: 0.73)
                    )
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 40)
        }
    }
}

private struct BereanLeaderOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.10))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Recent Chats List

private struct BereanRecentChatsList: View {
    var body: some View {
        let sessions = BereanChatSessionManager.shared.sessions.prefix(6)
        if sessions.isEmpty {
            Text("Your recent conversations will appear here.")
                .font(AMENFont.regular(14))
                .foregroundColor(.secondary)
                .padding(.horizontal, 18)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessions)) { session in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.06))
                                .frame(width: 38, height: 38)
                            Text(String(session.displayTitle.prefix(1)))
                                .font(AMENFont.semiBold(15))
                                .foregroundColor(.primary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.displayTitle)
                                .font(AMENFont.semiBold(14))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            if let preview = session.lastAssistantMessage?.content {
                                Text(preview)
                                    .font(AMENFont.regular(12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(session.relativeTimestamp)
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    Divider().padding(.leading, 70)
                }
            }
        }
    }
}

// MARK: - Scripture Search Sheet

struct BereanScriptureSearchSheet: View {
    let onSelect: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Enter a reference (e.g. John 3:16)", text: $query)
                    .font(AMENFont.regular(16))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal, 18)
                    .submitLabel(.go)
                    .onSubmit {
                        guard !query.isEmpty else { return }
                        onSelect(query)
                        dismiss()
                    }

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Open Scripture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        guard !query.isEmpty else { return }
                        onSelect(query)
                        dismiss()
                    }
                    .disabled(query.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BereanStudyHomeView()
}

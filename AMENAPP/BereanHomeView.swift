// BereanHomeView.swift
// AMEN App — Berean AI landing/home screen.
// White Liquid Glass design. Shows greeting, mode selector, suggestion chips,
// and recent chats. Entry point to BereanAIAssistantView for new and existing conversations.

import SwiftUI
import Foundation
import FirebaseAuth
import Combine

// MARK: - BereanMode (display-friendly wrapper for BereanPersonalityMode)

/// Display-friendly mode entries shown in the horizontal mode selector.
/// Maps directly to `BereanPersonalityMode` for AI calls.
enum BereanHomeMode: String, CaseIterable, Identifiable {
    case ask      = "Ask"
    case study    = "Study"
    case reflect  = "Reflect"
    case build    = "Build"
    case pray     = "Pray"
    case explore  = "Explore"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ask:     return "bubble.left.and.bubble.right"
        case .study:   return "book.pages"
        case .reflect: return "sparkles"
        case .build:   return "hammer"
        case .pray:    return "hands.sparkles"
        case .explore: return "magnifyingglass"
        }
    }

    /// Maps to the underlying AI personality mode.
    var personalityMode: BereanPersonalityMode {
        switch self {
        case .ask:     return .shepherd
        case .study:   return .scholar
        case .reflect: return .creator
        case .build:   return .builder
        case .pray:    return .shepherd
        case .explore: return .strategist
        }
    }

    /// Accent color used for recent chat avatars.
    var accentColor: Color {
        switch self {
        case .ask:     return Color(red: 0.30, green: 0.50, blue: 0.90)
        case .study:   return Color(red: 0.35, green: 0.30, blue: 0.90)
        case .reflect: return Color(red: 0.55, green: 0.30, blue: 0.85)
        case .build:   return Color(red: 0.85, green: 0.45, blue: 0.20)
        case .pray:    return Color(red: 0.30, green: 0.65, blue: 0.55)
        case .explore: return Color(red: 0.15, green: 0.55, blue: 0.75)
        }
    }
}

// MARK: - BereanHomeViewModel

@MainActor
final class BereanHomeViewModel: ObservableObject {
    @Published var selectedMode: BereanHomeMode = .ask
    @Published var recentSessions: [BereanChatSession] = []
    @Published var suggestedPrompts: [BereanHomePrompt] = []

    struct BereanHomePrompt: Identifiable {
        let id = UUID()
        let text: String
        let icon: String
        let mode: BereanHomeMode
    }

    init() {
        loadRecentSessions()
        loadSuggestedPrompts()
    }

    private func loadRecentSessions() {
        // Load from BereanChatSessionManager if available; otherwise show sample placeholders.
        recentSessions = Array(BereanChatSessionManager.shared.sessions.prefix(8))
    }

    func refreshSessions() {
        recentSessions = Array(BereanChatSessionManager.shared.sessions.prefix(8))
    }

    private func loadSuggestedPrompts() {
        suggestedPrompts = [
            BereanHomePrompt(text: "Explain Romans 8:28",       icon: "book",            mode: .study),
            BereanHomePrompt(text: "Help me make a decision",   icon: "arrow.triangle.branch", mode: .ask),
            BereanHomePrompt(text: "Write a morning prayer",    icon: "hands.sparkles",  mode: .pray),
            BereanHomePrompt(text: "What does Proverbs say about wisdom?", icon: "lightbulb", mode: .study),
        ]
    }

    var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = Auth.auth().currentUser?.displayName?.components(separatedBy: " ").first ?? "friend"
        switch hour {
        case 0..<12:  return "Good morning, \(firstName)"
        case 12..<17: return "Good afternoon, \(firstName)"
        default:      return "Good evening, \(firstName)"
        }
    }

    var verseOfDay: (reference: String, text: String) {
        // Static rotation — in production wire to a verse service.
        let verses: [(reference: String, text: String)] = [
            ("Proverbs 3:5–6",   "Trust in the LORD with all your heart and lean not on your own understanding."),
            ("Philippians 4:13", "I can do all things through Christ who strengthens me."),
            ("Psalm 119:105",    "Your word is a lamp to my feet and a light to my path."),
            ("Isaiah 40:31",     "Those who hope in the LORD will renew their strength."),
        ]
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return verses[dayOfYear % verses.count]
    }
}

// MARK: - BereanHomeView

struct BereanHomeView: View {
    @StateObject private var viewModel = BereanHomeViewModel()
    @State private var showNewChat = false
    @State private var selectedSession: BereanChatSession? = nil
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // Background
                Color.white.ignoresSafeArea()

                // Content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Greeting card
                        greetingCard
                            .padding(.horizontal, 18)
                            .padding(.top, 8)
                            .padding(.bottom, 20)

                        // Mode selector
                        modeSelector
                            .padding(.bottom, 20)

                        // Suggestion chips
                        suggestionSection
                            .padding(.bottom, 24)

                        // Recent chats
                        recentSection

                        // Bottom spacer for FAB
                        Spacer().frame(height: 96)
                    }
                }

                // FAB — New Chat
                newChatFAB
                    .padding(.trailing, 20)
                    .padding(.bottom, 28)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Berean")
                        .font(AMENFont.bold(28))
                        .foregroundColor(BereanColor.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.systemScaled(20, weight: .light))
                            .foregroundColor(BereanColor.textSecondary)
                    }
                }
            }
        }
        .onAppear { viewModel.refreshSessions() }
        .sheet(isPresented: $showNewChat) {
            BereanAIAssistantView()
        }
        .sheet(isPresented: $showSettings) {
            BereanAISettingsView()
        }
    }

    // MARK: - Greeting Card

    private var greetingCard: some View {
        let verse = viewModel.verseOfDay
        return VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.greetingText)
                .font(AMENFont.semiBold(15))
                .foregroundColor(BereanColor.textSecondary)
            Text("\u{201C}\(verse.text)\u{201D}")
                .font(AMENFont.regular(13))
                .foregroundColor(BereanColor.textTertiary)
                .lineLimit(2)
            Text("— \(verse.reference)")
                .font(AMENFont.regular(12))
                .foregroundColor(Color(white: 0.72))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BereanHomeMode.allCases) { mode in
                    modePill(mode)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .background(Color.clear)
    }

    private func modePill(_ mode: BereanHomeMode) -> some View {
        let isSelected = viewModel.selectedMode == mode
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.72))) {
                viewModel.selectedMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(mode.rawValue)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundColor(isSelected ? Color.black : BereanColor.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Group {
                    if isSelected {
                        Capsule().fill(Color.white)
                    } else {
                        Capsule().fill(.ultraThinMaterial).opacity(0.6)
                    }
                }
                .shadow(
                    color: isSelected ? Color.black.opacity(0.10) : Color.clear,
                    radius: isSelected ? 6 : 0, x: 0, y: isSelected ? 3 : 0
                )
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? BereanColor.glassStroke : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suggestion Chips

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.suggestedPrompts) { prompt in
                        BereanSuggestionChip(text: prompt.text, icon: prompt.icon) {
                            showNewChat = true
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: - Recent Chats

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Recent")
                .font(AMENFont.semiBold(13))
                .foregroundColor(BereanColor.textSecondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

            if viewModel.recentSessions.isEmpty {
                recentEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentSessions) { session in
                        recentRow(session: session)
                        Divider()
                            .padding(.leading, 72)
                            .foregroundColor(BereanColor.separator)
                    }
                }
            }
        }
    }

    private var recentEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(28))
                .foregroundColor(BereanColor.textTertiary)
            Text("No recent chats")
                .font(AMENFont.semiBold(15))
                .foregroundColor(BereanColor.textPrimary)
            Text("Start a new conversation with Berean.")
                .font(AMENFont.regular(13))
                .foregroundColor(BereanColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 40)
    }

    private func recentRow(session: BereanChatSession) -> some View {
        Button {
            selectedSession = session
        } label: {
            HStack(spacing: 14) {
                // Avatar circle
                ZStack {
                    Circle()
                        .fill(BereanHomeMode.ask.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(String(session.displayTitle.prefix(1)).uppercased())
                        .font(AMENFont.semiBold(17))
                        .foregroundColor(BereanHomeMode.ask.accentColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.displayTitle)
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(BereanColor.textPrimary)
                        .lineLimit(1)
                    if let preview = session.lastAssistantMessage?.content, !preview.isEmpty {
                        Text(preview)
                            .font(AMENFont.regular(13))
                            .foregroundColor(BereanColor.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.relativeTimestamp)
                        .font(AMENFont.regular(12))
                        .foregroundColor(BereanColor.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundColor(BereanColor.textTertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - FAB

    private var newChatFAB: some View {
        Button {
            showNewChat = true
        } label: {
            HStack(spacing: 8) {
                Text("New Chat")
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(Color.black)
                Text("+")
                    .font(.systemScaled(18, weight: .light))
                    .foregroundColor(Color.black)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 6)
                    .overlay(Capsule().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

struct BereanHomeView_Previews: PreviewProvider {
    static var previews: some View {
        BereanHomeView()
    }
}

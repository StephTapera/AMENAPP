// BereanConversationView.swift
// AMENAPP
//
// ChatGPT-style conversation surface for Berean Spiritual Intelligence.
// Liquid Glass design — white background, black hierarchy, sacred red accents.
//
// Design rules:
//   - Composer is the primary object on screen
//   - Single-thread conversation layout
//   - Messages fade+rise in with soft spring
//   - Structured cards bloom below response text
//   - Leadership/crisis cards are always visible when triggered
//   - No clutter. No generic chatbot look.

import SwiftUI
import FirebaseAuth

// MARK: - BereanConversationView

struct BereanConversationView: View {
    @StateObject private var viewModel: BereanSpiritualViewModel
    @State private var showScriptureInsight = false
    @State private var selectedPassageRef: String? = nil
    @State private var showJourney = false
    @FocusState private var composerFocused: Bool
    @Environment(\.dismiss) private var dismiss

    let conversationId: String
    let initialPrompt: String?

    init(conversationId: String = UUID().uuidString, initialPrompt: String? = nil) {
        self.conversationId = conversationId
        self.initialPrompt = initialPrompt
        _viewModel = StateObject(wrappedValue: BereanSpiritualViewModel(conversationId: conversationId))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                conversationNavBar

                // Message thread
                messageList
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 120)
                    }
            }

            // Composer overlay
            composerSection
                .padding(.bottom, 12)
        }
        .navigationBarHidden(true)
        .task {
            if let prompt = initialPrompt, !prompt.isEmpty {
                viewModel.currentInput = prompt
                await viewModel.sendMessage()
            }
        }
        .sheet(isPresented: $showScriptureInsight) {
            if let ref = selectedPassageRef {
                ScriptureInsightView(reference: ref)
            }
        }
        .sheet(isPresented: $showJourney) {
            DiscipleshipJourneyView()
        }
    }

    // MARK: - Nav Bar

    private var conversationNavBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
            }

            Spacer()

            // Spiritual state indicator (subtle)
            if let state = viewModel.currentState {
                Text(state.displayLabel)
                    .font(AMENFont.regular(12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemBackground))
                    )
                    .transition(.opacity)
            }

            Spacer()

            Button { showJourney = true } label: {
                Image(systemName: "map")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    // Empty state
                    if viewModel.messages.isEmpty && !viewModel.isLoading {
                        BereanConversationEmptyState()
                            .padding(.top, 60)
                            .padding(.horizontal, 24)
                    }

                    ForEach(viewModel.messages) { message in
                        BereanConvMessageBubble(
                            message: message,
                            onPassageTap: { ref in
                                selectedPassageRef = ref
                                showScriptureInsight = true
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .id(message.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Loading indicator
                    if viewModel.isLoading {
                        BereanConvThinkingIndicator()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .id("loading")
                    }

                    // Leadership/crisis banner
                    if viewModel.showLeadershipPrompt,
                       let msg = viewModel.leadershipPromptMessage {
                        BereanLeadershipBanner(message: msg) {
                            viewModel.dismissLeadershipPrompt()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id("leadership")
                    }

                    // Error
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(AMENFont.regular(13))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.top, 8)
                .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8)), value: viewModel.messages.count)
            }
            .onChange(of: viewModel.messages.count) { _ in
                withAnimation { proxy.scrollTo(viewModel.messages.last?.id ?? "loading", anchor: .bottom) }
            }
            .onChange(of: viewModel.isLoading) { loading in
                if loading { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Composer

    private var composerSection: some View {
        VStack(spacing: 0) {
            // Bottom blur fade
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 32)

            HStack(alignment: .bottom, spacing: 10) {
                // Input field
                TextField("Ask Berean or search scripture…", text: $viewModel.currentInput, axis: .vertical)
                    .font(AMENFont.regular(16))
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.white.opacity(0.8))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(
                                        composerFocused
                                            ? Color.black.opacity(0.18)
                                            : Color.black.opacity(0.08),
                                        lineWidth: composerFocused ? 1 : 0.5
                                    )
                            )
                            .shadow(color: Color.black.opacity(composerFocused ? 0.10 : 0.05), radius: composerFocused ? 12 : 6, x: 0, y: composerFocused ? 4 : 2)
                    )
                    .scaleEffect(composerFocused ? 1.0 : 0.99)
                    .animation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.75)), value: composerFocused)
                    .onSubmit { Task { await viewModel.sendMessage() } }

                // Send button
                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.currentInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color(.systemGray5) : Color.black)
                            .frame(width: 42, height: 42)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(viewModel.currentInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color(.systemGray3) : .white)
                    }
                }
                .disabled(viewModel.currentInput.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
                .animation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8)), value: viewModel.currentInput.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .background(Color.white)
        }
    }
}

// MARK: - Message Bubble

struct BereanConvMessageBubble: View {
    let message: BereanSpiritualMessage
    let onPassageTap: (String) -> Void

    var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                if !isUser {
                    // Berean avatar
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 28, height: 28)
                        Text("B")
                            .font(AMENFont.semiBold(12))
                            .foregroundColor(.black)
                    }
                }

                // Bubble
                Text(message.content)
                    .font(AMENFont.regular(16))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        isUser
                        ? AnyView(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground)))
                        : AnyView(Color.clear)
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.82, alignment: isUser ? .trailing : .leading)

                if isUser { Spacer() }
            }

            // Structured cards for assistant messages
            if !isUser, let response = message.structuredResponse {
                BereanStructuredCardStack(
                    response: response,
                    onPassageTap: onPassageTap
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

// MARK: - Structured Card Stack

struct BereanStructuredCardStack: View {
    let response: BereanStructuredResponse
    let onPassageTap: (String) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Scripture references row
            if !response.studyCards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(response.studyCards.prefix(3)) { card in
                            BereanMiniCard(card: card, onPassageTap: onPassageTap)
                        }
                        if response.studyCards.count > 3 && !expanded {
                            Button {
                                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                                    expanded = true
                                }
                            } label: {
                                Text("+\(response.studyCards.count - 3) more")
                                    .font(AMENFont.semiBold(12))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(response.studyCards.dropFirst(3)) { card in
                            BereanMiniCard(card: card, onPassageTap: onPassageTap)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            // Follow-up suggestion
            if let followUp = response.followUpSuggestion, !followUp.isEmpty {
                Label(followUp, systemImage: "sparkles")
                    .font(AMENFont.regular(13))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 36) // align with Berean avatar
    }
}

// MARK: - Mini Card

struct BereanMiniCard: View {
    let card: StudyCard
    let onPassageTap: (String) -> Void
    @State private var isExpanded = false

    var accentColor: Color {
        switch card.type {
        case .scripture:        return Color(red: 0.18, green: 0.44, blue: 0.80)
        case .wordStudy:        return Color(red: 0.52, green: 0.26, blue: 0.73)
        case .christConnection: return Color(red: 0.85, green: 0.60, blue: 0.15)
        case .application:      return Color(red: 0.22, green: 0.62, blue: 0.28)
        case .leaderReferral:   return Color(red: 0.18, green: 0.44, blue: 0.80)
        case .crisisResource:   return Color(red: 0.85, green: 0.25, blue: 0.30)
        default:                return Color.secondary
        }
    }

    var body: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(AMENFont.semiBold(12))
                    .foregroundColor(accentColor)
                    .lineLimit(isExpanded ? nil : 1)
                if isExpanded {
                    Text(card.content)
                        .font(AMENFont.regular(12))
                        .foregroundColor(.primary)
                        .lineSpacing(2)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.20), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: isExpanded ? .infinity : 180, alignment: .leading)
    }
}

// MARK: - Leadership Banner

struct BereanLeadershipBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(red: 0.18, green: 0.44, blue: 0.80))
                .padding(.top, 2)

            Text(message)
                .font(AMENFont.regular(13))
                .foregroundColor(.primary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.18, green: 0.44, blue: 0.80).opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.18, green: 0.44, blue: 0.80).opacity(0.18), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Thinking Indicator

struct BereanConvThinkingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 28, height: 28)
                Text("B")
                    .font(AMENFont.semiBold(12))
                    .foregroundColor(.black)
            }

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == Double(i) ? 1.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { phase = 2 }
    }
}

// MARK: - Empty State

struct BereanConversationEmptyState: View {
    let starters = [
        "Explain Romans 5:3–5",
        "How does forgiveness work in the Bible?",
        "I'm struggling with anxiety — what does Scripture say?",
        "What does Proverbs say about wisdom?",
    ]

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Ask Berean")
                    .font(AMENFont.semiBold(22))
                    .foregroundColor(.primary)
                Text("A spiritually serious study companion")
                    .font(AMENFont.regular(14))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(starters, id: \.self) { starter in
                    Button {
                        // starter chips handled by parent view via onTap
                    } label: {
                        HStack {
                            Text(starter)
                                .font(AMENFont.regular(14))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BereanConversationView()
}

//
//  BereanLandingView.swift
//  AMENAPP
//
//  Premium Berean AI landing / idle state.
//  Presented when the user opens Berean with no active conversation.
//

import SwiftUI

// MARK: - Colour tokens (matches existing AMEN / Berean palette)

private extension Color {
    static let bereanBackground  = Color(red: 0.975, green: 0.972, blue: 0.968) // warm near-white
    static let bereanCard        = AmenTheme.Colors.surfaceCard
    static let bereanCardStroke  = Color(white: 0, opacity: 0.06)
    static let bereanCoral       = Color(red: 0.88, green: 0.38, blue: 0.28)
    static let bereanPrimary     = Color(white: 0.10)
    static let bereanSecondary   = Color(white: 0.46)
    static let bereanTertiary    = Color(white: 0.68)
    static let bereanDash        = Color(white: 0, opacity: 0.15)
}

// MARK: - Quick Action Model

struct BereanQuickAction: Identifiable {
    let id = UUID()
    let icon: String           // SF Symbol name
    let label: String
    let prompt: String         // Pre-fills the input when tapped
}

extension BereanQuickAction {
    static let defaults: [BereanQuickAction] = [
        BereanQuickAction(icon: "book.pages",       label: "Study Scripture",       prompt: "Help me study "),
        BereanQuickAction(icon: "sparkles",          label: "Get Wisdom",            prompt: "Give me biblical wisdom about "),
        BereanQuickAction(icon: "quote.opening",     label: "Explain a Verse",       prompt: "Explain this verse: "),
        BereanQuickAction(icon: "heart.text.square", label: "Help Me Pray",          prompt: "Help me pray through "),
        BereanQuickAction(icon: "briefcase",         label: "Faith & Work",          prompt: "What does Scripture say about "),
        BereanQuickAction(icon: "lightbulb",         label: "Help Me Discern",       prompt: "Help me discern "),
        BereanQuickAction(icon: "doc.plaintext",     label: "Summarize a Sermon",    prompt: "Help me summarize this sermon: "),
        BereanQuickAction(icon: "arrow.left.arrow.right", label: "Compare Translations", prompt: "Compare translations of "),
    ]
}

// MARK: - BereanLandingView

struct BereanLandingView: View {

    // Callbacks — wired to the parent Berean chat view
    var onInputSubmit: (String) -> Void = { _ in }
    var onVoiceTap: (() -> Void)?
    var hasPreviousConversation: Bool = false
    var onContinuePrevious: (() -> Void)?
    var onHistoryTap: (() -> Void)?
    /// Recent saved conversations for the continuity section (pass the last 2–3 from dataManager).
    var recentConversations: [BereanContinuityEntry] = []

    // Animation orchestration
    @State private var statusCardVisible = false

    // Input state
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var suggestionsVisible = false

    @State private var greeting: BereanGreeting = BereanGreetingManager.greeting()
    @State private var hasAnimatedThisSession = false

    // AI consent gate — mirrors BereanVoiceCompanionView:305 pattern
    @State private var hasAIConsent: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Quick-suggestion chips shown in the empty state — a single horizontal
    // scroll row that replaces the old BereanSuggestionPanel card, the
    // 3-chip sub-row, and the 4 floating context chips.
    private let quickChips: [(icon: String, label: String, prompt: String)] = [
        ("questionmark.bubble", "Ask a question",  "I have a question about "),
        ("book.pages",          "Study scripture", "Help me study "),
        ("sparkles",            "Explain simply",  "Explain this simply: "),
        ("magnifyingglass.circle", "Explore context", "Give me historical context for "),
        ("hands.sparkles",      "Build a prayer",  "Help me build a prayer about "),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Background ──────────────────────────────────────────────
            Color.bereanBackground.ignoresSafeArea()

            // ── Scrollable content ──────────────────────────────────────
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Push hero to true vertical center of the visible area.
                        Spacer().frame(height: max(24, geo.size.height * (suggestionsVisible ? 0.18 : 0.38)))

                        // (3) Hero greeting
                        BereanHeroGreetingView(
                            greeting: greeting,
                            shouldAnimate: !hasAnimatedThisSession,
                            onSequenceComplete: {
                                hasAnimatedThisSession = true
                            }
                        )

                        // Continuity cards — recent studies/prayers to resume.
                        // Only visible in empty state; slide down / out of the way
                        // when the composer is focused.
                        if !recentConversations.isEmpty && !suggestionsVisible {
                            BereanContinuitySection(
                                entries: recentConversations,
                                onTap: { entry in onInputSubmit(entry.resumePrompt) }
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                            .opacity(statusCardVisible ? 1 : 0)
                            .offset(y: statusCardVisible ? 0 : 10)
                            .animation(reduceMotion ? .none : .spring(response: 0.52, dampingFraction: 0.82), value: statusCardVisible)
                        } else if hasPreviousConversation && !suggestionsVisible {
                            // Fallback: generic "continue last conversation" card
                            BereanContinueCard(onTap: onContinuePrevious ?? {})
                                .padding(.horizontal, 20)
                                .padding(.top, 28)
                                .opacity(statusCardVisible ? 1 : 0)
                                .offset(y: statusCardVisible ? 0 : 12)
                        }

                        // Bottom padding for input bar + chip row clearance
                        Spacer().frame(height: suggestionsVisible ? 300 : 130)
                    }
                }
            }
            // Dismiss focus when tapping outside the composer
            .onTapGesture {
                if inputFocused {
                    withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78))) {
                        inputFocused = false
                        inputText = ""
                    }
                }
            }

            // ── Bottom chrome stack ─────────────────────────────────────
            VStack(spacing: 10) {

                // AI consent banner — shown when consent has not been granted
                if !hasAIConsent {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.systemScaled(13, weight: .medium))
                        Text("Enable AI features in Settings to use Berean.")
                            .font(.systemScaled(13, weight: .regular))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color(.secondaryLabel))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AmenTheme.Colors.glassFill))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
                    )
                    .padding(.horizontal, 16)
                    .accessibilityLabel("AI consent required. Enable AI features in Settings to use Berean.")
                }

                // (5) Suggestion chip row — always visible, fades on focus
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickChips, id: \.label) { chip in
                            Button {
                                guard hasAIConsent else { return }
                                onInputSubmit(chip.prompt)
                                inputText = ""
                                inputFocused = false
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: chip.icon)
                                        .font(.systemScaled(12, weight: .medium))
                                    Text(chip.label)
                                        .font(.systemScaled(13, weight: .medium))
                                }
                                .foregroundColor(Color(.label))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().fill(AmenTheme.Colors.glassFill))
                                        .overlay(Capsule().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
                                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .opacity(suggestionsVisible ? 0 : 1)
                .scaleEffect(suggestionsVisible ? 0.96 : 1.0, anchor: .bottom)
                .animation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78)), value: suggestionsVisible)

                // (6) Floating input bar ────────────────────────────────
                BereanInputBar(
                    text: $inputText,
                    isFocused: $inputFocused,
                    onSubmit: {
                        guard hasAIConsent else { return }
                        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onInputSubmit(inputText)
                        inputText = ""
                    },
                    onVoiceTap: hasAIConsent ? onVoiceTap : nil,
                    onFocusChange: { focused in
                        withAnimation(Motion.adaptive(.spring(response: 0.48, dampingFraction: 0.82))) {
                            suggestionsVisible = focused
                        }
                    }
                )
                .disabled(!hasAIConsent)
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            greeting = BereanGreetingManager.greeting()
            hasAIConsent = AmenAIConsentStore.shared.hasConsent(for: .bereanQuickAnswer)
            if reduceMotion {
                hasAnimatedThisSession = true
                statusCardVisible = true
            } else {
                revealCards()
            }
        }
    }

    private func revealCards() {
        guard !reduceMotion else { return }
        withAnimation(Motion.adaptive(.spring(response: 0.55, dampingFraction: 0.82)).delay(0.05)) {
            statusCardVisible = true
        }
    }
}

// MARK: - BereanContinuityEntry

/// Lightweight model for a recent study or prayer thread the user can resume.
struct BereanContinuityEntry: Identifiable {
    let id: String
    let icon: String        // SF Symbol
    let title: String       // e.g. "Continue your study in Romans"
    let subtitle: String    // e.g. "Yesterday · 4 messages"
    let resumePrompt: String // sent to Berean when tapped

    /// Build entries from the last N saved conversations.
    static func from(_ conversations: [SavedConversation], limit: Int = 2) -> [BereanContinuityEntry] {
        conversations.prefix(limit).compactMap { conv in
            guard let first = conv.messages.first(where: { !$0.isFromUser }) else { return nil }
            let preview = String(first.content.prefix(60))
            let ago = relativeDate(conv.date)
            return BereanContinuityEntry(
                id: conv.id.uuidString,
                icon: topicIcon(for: conv.title),
                title: "Continue: \(conv.title)",
                subtitle: "\(ago) · \(conv.messages.count) messages",
                resumePrompt: "Let's continue where we left off. My last question was: \(preview)"
            )
        }
    }

    private static func topicIcon(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("prayer") || lower.contains("pray") { return "hands.sparkles" }
        if lower.contains("psalm") || lower.contains("verse") || lower.contains("scripture") { return "book.pages" }
        if lower.contains("note") || lower.contains("sermon") { return "doc.plaintext" }
        if lower.contains("wisdom") || lower.contains("faith") { return "lightbulb" }
        return "bubble.left.and.bubble.right"
    }

    private static func relativeDate(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}

// MARK: - BereanContinuitySection

/// Compact row of cards showing recent studies/prayers the user can resume with one tap.
struct BereanContinuitySection: View {
    let entries: [BereanContinuityEntry]
    var onTap: (BereanContinuityEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PICK UP WHERE YOU LEFT OFF")
                .font(.systemScaled(10, weight: .semibold))
                .kerning(1.2)
                .foregroundColor(.bereanTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    BereanContinuityCard(entry: entry, onTap: { onTap(entry) })
                }
            }
        }
    }
}

// MARK: - BereanContinuityCard

private struct BereanContinuityCard: View {
    let entry: BereanContinuityEntry
    var onTap: () -> Void
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bereanPrimary.opacity(0.06))
                        .frame(width: 38, height: 38)
                    Image(systemName: entry.icon)
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundColor(.bereanPrimary)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundColor(.bereanPrimary)
                        .lineLimit(1)
                    Text(entry.subtitle)
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundColor(.bereanSecondary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(.bereanTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AmenTheme.Colors.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 4)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - BereanContinueCard

/// Soft card shown when a previous conversation exists.
struct BereanContinueCard: View {
    var onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon in soft rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bereanPrimary.opacity(0.06))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundColor(.bereanPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue last conversation")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundColor(.bereanPrimary)
                    Text("Pick up where you left off")
                        .font(.systemScaled(13, weight: .regular))
                        .foregroundColor(.bereanSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundColor(.bereanTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AmenTheme.Colors.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 4)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - BereanQuickActionSection

struct BereanQuickActionSection: View {
    let actions: [BereanQuickAction]
    var isVisible: Bool
    var onActionTap: (BereanQuickAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Quick actions")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundColor(.bereanTertiary)
                .kerning(0.8)
                .textCase(.uppercase)
                .padding(.horizontal, 24)
                .opacity(isVisible ? 1 : 0)

            // 2-column card grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    BereanActionCard(action: action) {
                        onActionTap(action)
                    }
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 14)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.80)
                            .delay(isVisible ? Double(index) * 0.04 : 0),
                        value: isVisible
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - BereanActionCard

struct BereanActionCard: View {
    let action: BereanQuickAction
    var onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Icon
                Image(systemName: action.icon)
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundColor(.bereanPrimary)
                    .frame(width: 32, height: 32)

                // Label
                Text(action.label)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundColor(.bereanPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AmenTheme.Colors.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(isPressed ? 0.03 : 0.06),
                            radius: isPressed ? 6 : 14, x: 0, y: isPressed ? 2 : 4)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - BereanInputBar

struct BereanInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onVoiceTap: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)? = nil
    var placeholder: String = "Ask Berean about Scripture, prayer, wisdom…"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let focused = isFocused.wrappedValue
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        HStack(spacing: 10) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(15, weight: .medium))
                .foregroundColor(focused ? Color(.label) : Color(.tertiaryLabel))
                .scaleEffect(focused ? 1.06 : 1.0)
                .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: focused)
                .padding(.leading, 14)

            // Text field
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.systemScaled(15))
                .foregroundColor(Color(.label))
                .lineLimit(1...5)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(onSubmit)
                .padding(.vertical, 13)

            HStack(spacing: 6) {
                // Voice button (if provided and not typing)
                if let voiceTap = onVoiceTap, !hasText {
                    Button(action: voiceTap) {
                        Image(systemName: "mic")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundColor(Color(.secondaryLabel))
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("Voice input")
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                // Send button
                Button(action: onSubmit) {
                    ZStack {
                        Circle()
                            .fill(hasText ? Color.bereanPrimary : Color(.tertiarySystemFill))
                            .frame(width: 34, height: 34)
                        Image(systemName: "arrow.up")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundColor(hasText ? .white : Color(.tertiaryLabel))
                    }
                }
                .accessibilityLabel("Send message")
                .buttonStyle(.plain)
                .disabled(!hasText)
                .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: hasText)
            }
            .padding(.trailing, 10)

            // Cancel — slides in from trailing edge when focused
            if focused {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78))) {
                        text = ""
                        isFocused.wrappedValue = false
                    }
                } label: {
                    Text("Cancel")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundColor(Color(.secondaryLabel))
                        .padding(.trailing, 4)
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(AmenTheme.Colors.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            focused
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.black.opacity(0.14), Color.black.opacity(0.10)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                  ))
                                : AnyShapeStyle(AmenTheme.Colors.glassStroke),
                            lineWidth: focused ? 1.0 : 0.75
                        )
                )
                .shadow(
                    color: .black.opacity(focused ? 0.10 : 0.06),
                    radius: focused ? 22 : 16, x: 0, y: focused ? 6 : 4
                )
        )
        .offset(y: focused ? -4 : 0)
        .animation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.80), value: focused)
        .onChange(of: focused) { _, newValue in
            onFocusChange?(newValue)
        }
    }
}

// BereanSuggestionPanel and bereanSuggestedPrompts / bereanCategoryChips were
// removed as part of the empty-state consolidation (Agent D, 2026-05-28).
// Quick-action chips are now rendered inline in BereanLandingView.body as the
// `quickChips` property; see the (5) Suggestion chip row section.

// MARK: - BereanStatusCard  (AI thinking / processing state)

/// Shows while Berean is processing. Replace the standard spinner with this.
struct BereanStatusCard: View {
    let message: String
    var isVisible: Bool = true

    @State private var rotationDegrees: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            // Minimal ring progress indicator
            ZStack {
                Circle()
                    .stroke(Color.bereanPrimary.opacity(0.10), lineWidth: 2)
                    .frame(width: 26, height: 26)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(Color.bereanPrimary.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(rotationDegrees))
                    .onAppear {
                        if !reduceMotion {
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                rotationDegrees = 360
                            }
                        }
                    }
            }

            Text(message)
                .font(.systemScaled(14, weight: .medium))
                .foregroundColor(.bereanSecondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AmenTheme.Colors.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 3)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.97)
        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.82), value: isVisible)
    }
}

// MARK: - BereanWorkspaceCard  (editorial section container)

/// A structured editorial card for organizing Berean response sections
/// (Summary, Biblical Lens, Key Verses, Practical Wisdom, etc.)
struct BereanWorkspaceCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    var isDashed: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card header
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundColor(.bereanSecondary)
                }
                Text(title)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundColor(.bereanSecondary)
                    .kerning(0.3)
                Spacer()
            }

            Divider()
                .overlay(Color.bereanCardStroke)

            content()
        }
        .padding(16)
        .background {
            if isDashed {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.bereanBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.bereanDash, style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                    )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AmenTheme.Colors.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 3)
            }
        }
    }
}

// MARK: - BereanInsightCard  (compact, context-aware status panel)

/// Small modular card for short contextual messages on the landing screen.
struct BereanInsightCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var accentColor: Color = .bereanPrimary
    var onTap: (() -> Void)? = nil

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cardContent = HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundColor(.bereanPrimary)
                Text(subtitle)
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundColor(.bereanSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(.bereanTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AmenTheme.Colors.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(isPressed ? 0.03 : 0.05), radius: isPressed ? 6 : 12, x: 0, y: isPressed ? 1 : 3)
        )
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.8), value: isPressed)

        if let tap = onTap {
            Button(action: tap) { cardContent }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPressed = true }
                        .onEnded { _ in isPressed = false }
                )
        } else {
            cardContent
        }
    }
}

// MARK: - Preview

// MARK: - BereanLandingEmbedded
// Drop-in replacement for BereanEmptyState inside AIBibleStudyView.
// Renders hero block (3) + subtitle (4) + suggestion chip row (5).
// The host view (AIBibleStudyView) owns the composer (6) at the bottom.

struct BereanLandingEmbedded: View {
    /// Called when the user taps a suggestion chip — pre-fills the parent input.
    var onActionTap: (String) -> Void = { _ in }

    @State private var hasAnimatedThisSession = false
    @State private var greeting: BereanGreeting = BereanGreetingManager.greeting()
    @State private var chipsVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Suggestion chips — same set as BereanLandingView for consistency.
    private let quickChips: [(icon: String, label: String, prompt: String)] = [
        ("questionmark.bubble",    "Ask a question",   "I have a question about "),
        ("book.pages",             "Study scripture",  "Help me study "),
        ("sparkles",               "Explain simply",   "Explain this simply: "),
        ("magnifyingglass.circle", "Explore context",  "Give me historical context for "),
        ("hands.sparkles",         "Build a prayer",   "Help me build a prayer about "),
    ]

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Push hero to true vertical center of the available space.
                Spacer().frame(height: max(32, geo.size.height * 0.30))

                // (3) Hero block
                BereanHeroGreetingView(
                    greeting: greeting,
                    shouldAnimate: !hasAnimatedThisSession,
                    onSequenceComplete: {
                        hasAnimatedThisSession = true
                        withAnimation(Motion.adaptive(.spring(response: 0.48, dampingFraction: 0.82)).delay(0.12)) {
                            chipsVisible = true
                        }
                    }
                )

                Spacer().frame(height: 36)

                // (5) Suggestion chip row — single horizontal scroll of 4–5 short pills.
                // Fades in after the hero typing animation completes.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(quickChips.enumerated()), id: \.offset) { index, chip in
                            Button {
                                HapticManager.selection()
                                onActionTap(chip.prompt)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: chip.icon)
                                        .font(.systemScaled(12, weight: .medium))
                                    Text(chip.label)
                                        .font(.systemScaled(13, weight: .medium))
                                }
                                .foregroundColor(Color(white: 0.22))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                                )
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .opacity(chipsVisible ? 1 : 0)
                            .offset(y: chipsVisible ? 0 : 8)
                            .animation(
                                Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.82))
                                    .delay(reduceMotion ? 0 : Double(index) * 0.05),
                                value: chipsVisible
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer().frame(height: 24)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            greeting = BereanGreetingManager.greeting()
            if reduceMotion {
                hasAnimatedThisSession = true
                chipsVisible = true
            }
        }
    }
}

#if DEBUG
#Preview("Landing — morning") {
    NavigationStack {
        BereanLandingView(
            onInputSubmit: { _ in },
            hasPreviousConversation: true,
            onContinuePrevious: {}
        )
        .navigationTitle("Berean")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Status Card") {
    VStack(spacing: 12) {
        BereanStatusCard(message: "Searching scripture and context…", isVisible: true)
        BereanStatusCard(message: "Preparing a biblical lens…", isVisible: true)
        BereanStatusCard(message: "Comparing translations…", isVisible: true)
    }
    .padding()
    .background(Color.bereanBackground)
}

#Preview("Workspace Card") {
    VStack(spacing: 12) {
        BereanWorkspaceCard(title: "Biblical Lens", icon: "book.pages") {
            Text("This passage from Proverbs speaks to the nature of wisdom as a gift granted to those who seek God with humility.")
                .font(.systemScaled(14))
                .foregroundColor(Color(.label))
        }
        BereanWorkspaceCard(title: "Suggested Next Step", icon: "lightbulb", isDashed: true) {
            Text("Continue your study by exploring Romans 12:2 alongside this passage.")
                .font(.systemScaled(14))
                .foregroundColor(Color(.secondaryLabel))
        }
    }
    .padding()
    .background(Color.bereanBackground)
}

#Preview("Insight Card") {
    VStack(spacing: 8) {
        BereanInsightCard(icon: "bookmark.fill", title: "Today's Reflection",
                          subtitle: "Proverbs 3:5–6 · Added yesterday", onTap: {})
        BereanInsightCard(icon: "folder", title: "Saved Studies",
                          subtitle: "3 folders · Last opened today", onTap: {})
    }
    .padding()
    .background(Color.bereanBackground)
}
#endif

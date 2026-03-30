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
    static let bereanBackground  = Color(red: 0.97, green: 0.97, blue: 0.97)   // near-white
    static let bereanCard        = Color.white
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

    // Animation orchestration
    @State private var heroComplete = false
    @State private var statusCardVisible = false

    // Input state
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    @State private var greeting: BereanGreeting = BereanGreetingManager.greeting()
    @State private var hasAnimatedThisSession = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Background ──────────────────────────────────────────────
            Color.bereanBackground.ignoresSafeArea()

            // ── Scrollable content ──────────────────────────────────────
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Push hero to true vertical center of the visible area.
                        // With no cards below, ~38% from top sits it at the
                        // optical midpoint above the floating input bar.
                        Spacer().frame(height: max(24, geo.size.height * 0.38))

                        // Hero greeting
                        BereanHeroGreetingView(
                            greeting: greeting,
                            shouldAnimate: !hasAnimatedThisSession,
                            onSequenceComplete: {
                                hasAnimatedThisSession = true
                            }
                        )

                        // Status / context card (only if has previous session)
                        if hasPreviousConversation {
                            BereanContinueCard(onTap: onContinuePrevious ?? {})
                                .padding(.horizontal, 20)
                                .padding(.top, 32)
                                .opacity(statusCardVisible ? 1 : 0)
                                .offset(y: statusCardVisible ? 0 : 12)
                        }

                        // Bottom padding for input bar clearance
                        Spacer().frame(height: 110)
                    }
                }
            }

            // ── Floating input bar ──────────────────────────────────────
            BereanInputBar(
                text: $inputText,
                isFocused: $inputFocused,
                onSubmit: {
                    guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onInputSubmit(inputText)
                    inputText = ""
                },
                onVoiceTap: onVoiceTap
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .onAppear {
            greeting = BereanGreetingManager.greeting()
            if reduceMotion {
                hasAnimatedThisSession = true
                statusCardVisible = true
            }
        }
    }

    private func revealCards() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.05)) {
            statusCardVisible = true
        }
    }
}

// MARK: - BereanContinueCard

/// Soft card shown when a previous conversation exists.
struct BereanContinueCard: View {
    var onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon in soft rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bereanPrimary.opacity(0.06))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.bereanPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue last conversation")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.bereanPrimary)
                    Text("Pick up where you left off")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.bereanSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.bereanTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.bereanCard)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.bereanCardStroke, lineWidth: 0.5)
                    )
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Quick actions")
                .font(.system(size: 12, weight: .semibold))
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
                        .spring(response: 0.5, dampingFraction: 0.80)
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

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Icon
                Image(systemName: action.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.bereanPrimary)
                    .frame(width: 32, height: 32)

                // Label
                Text(action.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.bereanPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.bereanCard)
                    .shadow(color: Color.black.opacity(isPressed ? 0.02 : 0.05),
                            radius: isPressed ? 4 : 10, x: 0, y: isPressed ? 1 : 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.bereanCardStroke, lineWidth: 0.5)
                    )
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isPressed)
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
    var placeholder: String = "Ask Berean anything…"

    @State private var barHeight: CGFloat = 50

    var body: some View {
        HStack(spacing: 10) {
            // Text field
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.system(size: 15))
                .foregroundColor(Color(.label))
                .lineLimit(1...5)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(onSubmit)
                .padding(.leading, 16)
                .padding(.vertical, 13)

            HStack(spacing: 6) {
                // Voice button (if provided)
                if let voiceTap = onVoiceTap {
                    Button(action: voiceTap) {
                        Image(systemName: "mic")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(.secondaryLabel))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }

                // Send button
                Button(action: onSubmit) {
                    let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ZStack {
                        Circle()
                            .fill(hasText ? Color.bereanPrimary : Color(.tertiarySystemFill))
                            .frame(width: 34, height: 34)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(hasText ? .white : Color(.tertiaryLabel))
                    }
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .animation(.spring(response: 0.3, dampingFraction: 0.8),
                           value: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.trailing, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.07), radius: 16, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.bereanCardStroke, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - BereanStatusCard  (AI thinking / processing state)

/// Shows while Berean is processing. Replace the standard spinner with this.
struct BereanStatusCard: View {
    let message: String
    var isVisible: Bool = true

    @State private var rotationDegrees: Double = 0
    @State private var pulseScale: CGFloat = 1.0

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
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                            rotationDegrees = 360
                        }
                    }
            }

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.bereanSecondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bereanCard)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.bereanCardStroke, lineWidth: 0.5)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.97)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isVisible)
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.bereanSecondary)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.bereanSecondary)
                    .kerning(0.3)
                Spacer()
            }

            Divider()
                .overlay(Color.bereanCardStroke)

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isDashed ? Color.bereanBackground : Color.bereanCard)
                .shadow(color: isDashed ? .clear : Color.black.opacity(0.04),
                        radius: 10, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isDashed ? Color.bereanDash : Color.bereanCardStroke,
                            style: isDashed
                                ? StrokeStyle(lineWidth: 1.2, dash: [5, 5])
                                : StrokeStyle(lineWidth: 0.5)
                        )
                )
        )
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

    var body: some View {
        let cardContent = HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.bereanPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.bereanSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.bereanTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bereanCard)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.bereanCardStroke, lineWidth: 0.5)
                )
        )
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isPressed)

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
// Renders only hero + cards — the host view owns the input bar.

struct BereanLandingEmbedded: View {
    var onActionTap: (String) -> Void = { _ in }

    @State private var hasAnimatedThisSession = false
    @State private var greeting: BereanGreeting = BereanGreetingManager.greeting()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Push hero to true vertical center of the available space.
                Spacer().frame(height: max(32, geo.size.height * 0.38))

                BereanHeroGreetingView(
                    greeting: greeting,
                    shouldAnimate: !hasAnimatedThisSession,
                    onSequenceComplete: {
                        hasAnimatedThisSession = true
                    }
                )

                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            greeting = BereanGreetingManager.greeting()
            if reduceMotion {
                hasAnimatedThisSession = true
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
                .font(.system(size: 14))
                .foregroundColor(Color(.label))
        }
        BereanWorkspaceCard(title: "Suggested Next Step", icon: "lightbulb", isDashed: true) {
            Text("Continue your study by exploring Romans 12:2 alongside this passage.")
                .font(.system(size: 14))
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

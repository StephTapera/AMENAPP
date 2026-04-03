// BereanDesignSystem.swift
// AMEN App — Berean AI shared design tokens, modifiers, and reusable components.
// White Liquid Glass design language. Import this file for consistent styling
// across all Berean screens.

import SwiftUI
import Foundation

// MARK: - Colors

enum BereanColor {
    static let background      = Color.white
    static let textPrimary     = Color.black
    static let textSecondary   = Color(white: 0.45)
    static let textTertiary    = Color(white: 0.65)
    static let separator       = Color(white: 0.88)
    static let glassFill       = Color.white.opacity(0.72)
    static let glassBorder     = Color.white.opacity(0.55)
    static let glassStroke     = Color(white: 0.88).opacity(0.5)
    static let userBubbleBg    = Color(white: 0.94)
    static let aiBubbleBg      = Color.white
    static let shadowColor     = Color.black.opacity(0.07)
    static let divider         = Color(white: 0.90)
}

// MARK: - Typography

enum BereanType {
    /// 32pt bold — hero / splash title
    static func displayTitle() -> Font {
        AMENFont.bold(32)
    }
    /// 24pt bold — section / screen title
    static func sectionTitle() -> Font {
        AMENFont.bold(24)
    }
    /// 20pt semibold — card title / navigation title
    static func title() -> Font {
        AMENFont.semiBold(20)
    }
    /// 17pt semibold — list row headline
    static func headline() -> Font {
        AMENFont.semiBold(17)
    }
    /// 16pt regular — message body
    static func body() -> Font {
        AMENFont.regular(16)
    }
    /// 15pt regular — card subtitle / row label
    static func subheadline() -> Font {
        AMENFont.regular(15)
    }
    /// 13pt regular — caption / chip text
    static func caption() -> Font {
        AMENFont.regular(13)
    }
    /// 12pt regular — timestamps / metadata
    static func micro() -> Font {
        AMENFont.regular(12)
    }
}

// MARK: - Glass Modifiers

/// Full liquid glass card: .ultraThinMaterial + white overlay + hairline border + soft shadow.
struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var shadowRadius: CGFloat = 16
    var shadowY: CGFloat      = 5

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.80), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(0.07), radius: shadowRadius, x: 0, y: shadowY)
    }
}

/// Input bar glass modifier — tighter shadow, used for bottom composers.
struct LiquidGlassInputBarModifier: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.80))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(white: 0.82), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.09), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func bereanGlassCard(cornerRadius: CGFloat = 18, shadowRadius: CGFloat = 16, shadowY: CGFloat = 5) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, shadowRadius: shadowRadius, shadowY: shadowY))
    }
    func bereanGlassInputBar(cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidGlassInputBarModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - BereanPersonalityPill

/// Inline pill showing the currently active personality mode.
/// Used in Berean navigation bars and mode selectors.
struct BereanPersonalityPill: View {
    let mode: BereanPersonalityMode
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mode.icon)
                .font(.systemScaled(compact ? 9 : 11, weight: .medium))
            if !compact {
                Text(mode.rawValue)
                    .font(BereanType.caption())
            }
        }
        .foregroundColor(BereanColor.textSecondary)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.60)))
                .overlay(Capsule().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5))
        )
    }
}

// MARK: - BereanSuggestionChip

/// Horizontal scrollable prompt suggestion chip.
struct BereanSuggestionChip: View {
    let text: String
    var icon: String = "sparkles"
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(BereanColor.textSecondary)
                Text(text)
                    .font(BereanType.caption())
                    .foregroundColor(BereanColor.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BereanMessageBubble

/// Chat message bubble — user (right, gray bg) or AI (left, white/glass bg).
struct BereanMessageBubble: View {
    let content: String
    let isUser: Bool
    var isStreaming: Bool = false

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 52) }

            if !isUser {
                avatarDot
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                bubbleContent
            }

            if !isUser { Spacer(minLength: 52) }
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : (isUser ? 8 : -8))
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.40, dampingFraction: 0.72))) {
                appeared = true
            }
        }
    }

    private var avatarDot: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
                .frame(width: 26, height: 26)
            Text("B")
                .font(.systemScaled(10, weight: .bold))
                .foregroundColor(Color(red: 0.788, green: 0.659, blue: 0.298))
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        Text(content.isEmpty && isStreaming ? "▌" : content)
            .font(BereanType.body())
            .foregroundColor(isUser ? Color.white : BereanColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

// MARK: - BereanThinkingIndicator

/// Animated 3-dot thinking indicator with breathing scale animation.
struct BereanThinkingIndicator: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Berean avatar
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
                    .frame(width: 26, height: 26)
                Text("B")
                    .font(.systemScaled(10, weight: .bold))
                    .foregroundColor(Color(red: 0.788, green: 0.659, blue: 0.298))
            }

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(BereanColor.textTertiary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(dotScale(index: i))
                        .animation(
                            .easeInOut(duration: 0.55)
                                .repeatForever()
                                .delay(Double(i) * 0.18),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.88))
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )

            Spacer(minLength: 52)
        }
        .onAppear { phase = 1 }
    }

    private func dotScale(index: Int) -> CGFloat {
        phase == 0 ? 1.0 : (index % 2 == 0 ? 1.35 : 0.80)
    }
}

// MARK: - BereanInputBar (Design System)

/// Shared bottom input composer used across Berean chat views.
/// The hosting view provides bindings for text and callbacks for actions.
struct BereanInputComposer: View {
    @Binding var text: String
    var isStreaming: Bool = false
    var placeholder: String = "Ask Berean..."
    var onSend: () -> Void
    var onVoice: (() -> Void)? = nil
    var onAttach: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Attach icon
            if let attachAction = onAttach {
                Button(action: attachAction) {
                    Image(systemName: "plus.circle")
                        .font(.systemScaled(20, weight: .light))
                        .foregroundColor(BereanColor.textSecondary)
                }
                .padding(.bottom, 10)
            }

            // Text field
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(BereanType.body())
                        .foregroundColor(BereanColor.textTertiary)
                        .padding(.horizontal, 4)
                }
                TextField("", text: $text, axis: .vertical)
                    .font(BereanType.body())
                    .foregroundColor(BereanColor.textPrimary)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 4)
            }
            .padding(.vertical, 10)

            // Voice + Send
            HStack(spacing: 6) {
                if let voiceAction = onVoice, text.isEmpty {
                    Button(action: voiceAction) {
                        Image(systemName: "mic")
                            .font(.systemScaled(16, weight: .medium))
                            .foregroundColor(BereanColor.textSecondary)
                    }
                }

                Button(action: {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !isStreaming else { return }
                    onSend()
                }) {
                    ZStack {
                        Circle()
                            .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming
                                  ? Color(white: 0.85) : Color.black)
                            .frame(width: 34, height: 34)
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                            .font(.systemScaled(13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .bereanGlassInputBar()
    }
}

// MARK: - Preview Provider

struct BereanDesignSystem_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Suggestion chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        BereanSuggestionChip(text: "Explain John 3:16")
                        BereanSuggestionChip(text: "Help me pray", icon: "hands.sparkles")
                        BereanSuggestionChip(text: "Study Romans 8", icon: "book")
                    }
                    .padding(.horizontal, 16)
                }

                // Message bubbles
                VStack(spacing: 12) {
                    BereanMessageBubble(content: "What does Proverbs say about wisdom?", isUser: true)
                    BereanMessageBubble(content: "Proverbs teaches that wisdom begins with the fear of the Lord.", isUser: false)
                }
                .padding(.horizontal, 16)

                // Thinking indicator
                BereanThinkingIndicator()
                    .padding(.horizontal, 16)

                // Input composer
                BereanInputComposer(text: .constant(""), onSend: {})
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 20)
        }
        .background(BereanColor.background)
    }
}

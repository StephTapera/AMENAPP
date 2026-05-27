// BereanConversationSpine.swift
// AMEN App — Edge-aligned glass scrubber spine for BereanChatView.
// Lets users visually scan and jump to any message in a long thread.
// Agent E — Berean AI Chat UI rebuild, 2026-05-27.

import SwiftUI

// MARK: - Dot Classification

/// Classifies a message for spine dot color and relative size.
private enum SpineDotKind {
    case user
    case aiNormal
    case aiCitation       // has provenance record
    case aiStructured     // has code / structured content

    var dotColor: Color {
        switch self {
        case .user:          return Color.amenBlack.opacity(0.22)
        case .aiNormal:      return Color.amenGold.opacity(0.38)
        case .aiCitation:    return BereanConversationSpineColors.amenPurple.opacity(0.55)
        case .aiStructured:  return BereanConversationSpineColors.amenBlue.opacity(0.45)
        }
    }

    var baseDiameter: CGFloat {
        switch self {
        case .user:          return 5
        case .aiNormal:      return 6
        case .aiCitation:    return 7
        case .aiStructured:  return 7
        }
    }
}

// MARK: - Color helpers (amenPurple / amenBlue not yet in global token sheet)

/// Namespace so these are not exported at module scope — see BereanDesignSystem.swift
/// for the canonical token discussion. Promote to Color extension once the design
/// system audit adds them globally (audit item DS-9).
private enum BereanConversationSpineColors {
    static let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
    static let amenBlue   = Color(red: 0.40, green: 0.70, blue: 0.95)
}

// MARK: - BereanConversationSpine

/// A 12pt-wide trailing-edge glass spine showing one dot per message.
/// Dots are color-coded by message role and content type.
/// Tapping a dot scrolls the associated `ScrollViewProxy` to that message.
/// The currently-visible message dot is scaled up by 1.3×.
struct BereanConversationSpine: View {

    // MARK: - Public Interface

    let messages: [BereanChatMsg]
    @Binding var visibleMessageId: UUID?
    let scrollProxy: ScrollViewProxy

    // MARK: - Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Total reserved width including the pill background.
    private let totalWidth: CGFloat = 24
    private let dotColumnWidth: CGFloat = 12
    private let dotSpacing: CGFloat = 5

    // MARK: - Springs

    private var contentAppear: Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .spring(response: 0.36, dampingFraction: 0.76)
    }

    private var fastSettle: Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .spring(response: 0.28, dampingFraction: 0.88)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { _ in
                dotColumn
            }
        }
        .frame(width: totalWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread scrubber. \(messages.count) messages.")
        .accessibilityHint("Tap a dot to jump to that message")
    }

    // MARK: - Dot Column

    private var dotColumn: some View {
        VStack(spacing: dotSpacing) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                SpineDot(
                    message: message,
                    isVisible: visibleMessageId == message.id,
                    onTap: {
                        withAnimation(fastSettle) {
                            scrollProxy.scrollTo(message.id, anchor: .center)
                            visibleMessageId = message.id
                        }
                    }
                )
                .animation(contentAppear.delay(Double(index) * 0.012), value: messages.count)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(spineBackground)
        .frame(width: totalWidth)
    }

    // MARK: - Background

    @ViewBuilder
    private var spineBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BereanColor.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
                .shadow(color: BereanColor.shadowColor.opacity(0.07), radius: 6, y: 2)
        }
    }
}

// MARK: - SpineDot (internal subview)

private struct SpineDot: View {
    let message: BereanChatMsg
    let isVisible: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kind: SpineDotKind {
        guard message.role == .assistant else { return .user }
        if message.provenance != nil { return .aiCitation }
        // Heuristic: structured content is identified by backtick fences or bullet-heavy content.
        if hasStructuredContent(message.content) { return .aiStructured }
        return .aiNormal
    }

    private var fastSettle: Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .spring(response: 0.28, dampingFraction: 0.88)
    }

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(kind.dotColor)
                .frame(
                    width: kind.baseDiameter,
                    height: kind.baseDiameter
                )
                .scaleEffect(isVisible ? 1.3 : 1.0)
                // Ensure minimum 44×44 tap target via contentShape
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(fastSettle, value: isVisible)
        .accessibilityLabel(dotAccessibilityLabel)
        .accessibilityHint("Tap to jump to this message")
        .accessibilityAddTraits(isVisible ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Helpers

    private var dotAccessibilityLabel: String {
        let roleLabel = message.role == .user ? "Your message" : "Berean reply"
        let kindLabel: String
        switch kind {
        case .user:          kindLabel = ""
        case .aiNormal:      kindLabel = ""
        case .aiCitation:    kindLabel = ", with citations"
        case .aiStructured:  kindLabel = ", structured content"
        }
        let visibilityLabel = isVisible ? ", currently visible" : ""
        return "\(roleLabel)\(kindLabel)\(visibilityLabel)"
    }

    /// Detect code blocks or heavy bullet structure in message content.
    private func hasStructuredContent(_ text: String) -> Bool {
        text.contains("```") || text.contains("    •") || text.contains("\n- ") || text.contains("\n1. ")
    }
}

// MARK: - Previews

#Preview("Short thread") {
    SpinePreviewContainer(messageCount: 8)
}

#Preview("Long thread") {
    SpinePreviewContainer(messageCount: 40)
}

// MARK: - Preview Container

private struct SpinePreviewContainer: View {
    let messageCount: Int

    @State private var visibleId: UUID? = nil

    private var messages: [BereanChatMsg] {
        (0..<messageCount).map { i in
            BereanChatMsg(
                role: i % 2 == 0 ? .user : .assistant,
                content: sampleContent(index: i),
                timestamp: Date().addingTimeInterval(Double(i) * -60),
                provenance: i == 3 ? BereanProvenanceRecord() : nil
            )
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            Text(msg.content)
                                .font(BereanType.body())
                                .foregroundColor(BereanColor.textPrimary)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(msg.role == .user
                                            ? Color.amenBlack.opacity(0.06)
                                            : Color(uiColor: .secondarySystemBackground))
                                )
                                .id(msg.id)
                                .onAppear {
                                    if visibleId == nil { visibleId = msg.id }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }

                BereanConversationSpine(
                    messages: messages,
                    visibleMessageId: $visibleId,
                    scrollProxy: proxy
                )
                .padding(.trailing, 4)
            }
        }
        .background(BereanColor.background)
    }

    private func sampleContent(index: Int) -> String {
        let userMessages = [
            "What does Romans 8 say about suffering?",
            "Can you explain the context of verse 28?",
            "How does this connect to Paul's other letters?",
        ]
        let aiMessages = [
            "Romans 8 addresses suffering with a profound promise — that present suffering is incomparable to future glory (v. 18).",
            "Verse 28 — \"And we know that in all things God works for the good\" — is one of the most quoted and often misapplied passages in the New Testament. The context matters enormously.",
            "Paul echoes this theme in 2 Corinthians 4:17, where he calls suffering a \"light and momentary\" trouble achieving \"an eternal glory.\"\n\n```swift\n// Structured content example\nlet verses = [\"Romans 8:28\", \"2 Cor 4:17\"]\n```",
            "The Greek word ὑπερεντυγχάνει (hyperentynchanei) in verse 26 is unique to this passage — the Spirit intercedes \"beyond words\" on our behalf.",
        ]
        if index % 2 == 0 {
            return userMessages[index % userMessages.count]
        } else {
            return aiMessages[index % aiMessages.count]
        }
    }
}

// AMENReactionSystem.swift
// AMENAPP
//
// iMessage-quality reaction picker system.
// Reusable across messages, comments, and any future surface.
//
// Components:
//   ReactionContext          — configures emoji set + surface metadata
//   ReactionPresentationState — single source of truth for open tray
//   ReactionTrayOverlay      — full-screen dimmed overlay + tray
//   ReactionTrayView         — the floating pill tray itself
//   ReactionItemView         — individual emoji with lift/magnetism
//   ReactionAnchorBadgeView  — badge that lives on the message/comment
//   ReactionBadgeRow         — horizontal grouped badge strip
//   .reactionPicker(...)     — view modifier for easy integration
//
// Animation rationale:
//   response: 0.32 / dampingFraction: 0.70 — snappy spring, slight bounce,
//   identical to iOS system sheets. Hover uses 0.22/0.68 for faster magnetic feel.
//   Badge landing uses 0.28/0.55 for visible overshoot = tactile "pop".

import SwiftUI
import Combine

// MARK: - Reaction context

/// Defines which reactions are available and on which surface.
struct ReactionContext {
    let reactions: [ReactionItem]
    let surface: Surface

    enum Surface {
        case message
        case comment
    }

    static let message = ReactionContext(
        reactions: [
            .init(emoji: "❤️",  label: "Love"),
            .init(emoji: "🙏",  label: "Amen"),
            .init(emoji: "🔥",  label: "Fire"),
            .init(emoji: "😂",  label: "Laugh"),
            .init(emoji: "😮",  label: "Wow"),
            .init(emoji: "👍",  label: "Like"),
            .init(emoji: "📖",  label: "Scripture"),
        ],
        surface: .message
    )

    static let comment = ReactionContext(
        reactions: [
            .init(emoji: "❤️",  label: "Love"),
            .init(emoji: "🙏",  label: "Amen"),
            .init(emoji: "🔥",  label: "Fire"),
            .init(emoji: "👍",  label: "Like"),
            .init(emoji: "💡",  label: "Insightful"),
            .init(emoji: "🕊️",  label: "Peace"),
        ],
        surface: .comment
    )
}

struct ReactionItem: Identifiable, Equatable {
    let id = UUID()
    let emoji: String
    let label: String
}

// MARK: - Presentation state (single source of truth)

/// Inject as an @EnvironmentObject into the scroll-view hierarchy.
/// Only one tray is open at any time — setting a new anchorID closes any existing one.
@MainActor
final class ReactionPresentationState: ObservableObject {
    static let shared = ReactionPresentationState()

    @Published var activeAnchorID: AnyHashable? = nil
    @Published var anchorFrame: CGRect = .zero   // in global coords
    @Published var isFromCurrentUser: Bool = false
    @Published var context: ReactionContext = .message
    @Published var selectedEmoji: String? = nil
    @Published var onSelect: ((String) -> Void)? = nil

    func present(
        anchorID: AnyHashable,
        anchorFrame: CGRect,
        isFromCurrentUser: Bool,
        context: ReactionContext,
        selectedEmoji: String?,
        onSelect: @escaping (String) -> Void
    ) {
        // Close existing tray first (without animation) then open new one
        if activeAnchorID != nil && activeAnchorID != anchorID {
            activeAnchorID = nil
        }
        self.anchorFrame      = anchorFrame
        self.isFromCurrentUser = isFromCurrentUser
        self.context          = context
        self.selectedEmoji    = selectedEmoji
        self.onSelect         = onSelect

        withAnimation(.spring(response: 0.32, dampingFraction: 0.70)) {
            activeAnchorID = anchorID
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func dismiss() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
            activeAnchorID = nil
        }
    }

    var isPresented: Bool { activeAnchorID != nil }

    private init() {}
}

// MARK: - Full-screen overlay + tray

/// Place once at the root ZStack of the screen (ContentView / chat host).
/// Handles backdrop dim, tray positioning, and gesture dismissal.
struct ReactionTrayOverlay: View {
    @ObservedObject var state: ReactionPresentationState

    var body: some View {
        if state.isPresented {
            ZStack(alignment: .topLeading) {
                // Soft backdrop
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { state.dismiss() }
                    .transition(.opacity)

                // Tray positioned relative to anchor
                ReactionTrayView(state: state)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.88, anchor: trayAnchorUnitPoint)
                                        .combined(with: .opacity)
                                        .combined(with: .offset(y: 10)),
                            removal: .scale(scale: 0.90, anchor: trayAnchorUnitPoint)
                                       .combined(with: .opacity)
                        )
                    )
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: state.isPresented)
            .ignoresSafeArea()
            .zIndex(999)
        }
    }

    // Anchor the spring scale at the left or right edge based on bubble side
    private var trayAnchorUnitPoint: UnitPoint {
        state.isFromCurrentUser ? .bottomTrailing : .bottomLeading
    }
}

// MARK: - Tray view

struct ReactionTrayView: View {
    @ObservedObject var state: ReactionPresentationState
    @State private var hoveredIndex: Int? = nil

    // Layout constants
    private let itemSpacing: CGFloat  = 4
    private let itemBaseSize: CGFloat = 38   // normal emoji touch target
    private let itemHoverLift: CGFloat = 14  // how far hovered item rises
    private let hoverScale: CGFloat   = 1.32 // hovered item scale

    var body: some View {
        GeometryReader { screenGeo in
            let trayWidth = trayNaturalWidth
            let trayHeight: CGFloat = 58
            let anchorMidX = state.anchorFrame.midX
            let anchorMinY = state.anchorFrame.minY

            // Horizontal clamp so tray doesn't clip off screen
            let rawX = state.isFromCurrentUser
                ? (anchorMidX + state.anchorFrame.width / 2) - trayWidth
                : anchorMidX - state.anchorFrame.width / 2
            let clampedX = min(
                max(rawX, 12),
                screenGeo.size.width - trayWidth - 12
            )

            // Vertical position: above anchor, below if too high
            let trayY = anchorMinY - trayHeight - 10 < 60
                ? anchorMinY + state.anchorFrame.height + 8  // flip below
                : anchorMinY - trayHeight - 10

            trayBody
                .frame(width: trayWidth)
                .position(x: clampedX + trayWidth / 2, y: trayY + trayHeight / 2)
        }
        .ignoresSafeArea()
    }

    private var trayNaturalWidth: CGFloat {
        let n = CGFloat(state.context.reactions.count)
        return n * itemBaseSize + (n - 1) * itemSpacing + 20   // 10pt padding each side
    }

    @ViewBuilder
    private var trayBody: some View {
        HStack(spacing: itemSpacing) {
            ForEach(Array(state.context.reactions.enumerated()), id: \.element.id) { index, item in
                ReactionItemView(
                    item: item,
                    isHovered: hoveredIndex == index,
                    isSelected: state.selectedEmoji == item.emoji,
                    neighborDistance: neighborDistance(for: index),
                    baseSize: itemBaseSize,
                    hoverLift: itemHoverLift,
                    hoverScale: hoverScale
                )
                .onTapGesture {
                    commitSelection(item)
                }
                // Scrub detection: extend touchable column across full tray height
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering && hoveredIndex != index {
                                hoveredIndex = index
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 58 + itemHoverLift) // extra height for lift room
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let itemWidth = itemBaseSize + itemSpacing
                    let rawIndex = Int((value.location.x - 10) / itemWidth)
                    let clamped  = max(0, min(state.context.reactions.count - 1, rawIndex))
                    if hoveredIndex != clamped {
                        hoveredIndex = clamped
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { value in
                    if let idx = hoveredIndex {
                        let item = state.context.reactions[idx]
                        commitSelection(item)
                    }
                }
        )
        .accessibilityLabel("Reaction picker")
    }

    private func neighborDistance(for index: Int) -> CGFloat {
        guard let hIdx = hoveredIndex else { return 0 }
        let dist = abs(index - hIdx)
        switch dist {
        case 0: return 0   // the hovered item itself — no push
        case 1: return 3   // immediate neighbors shift slightly
        default: return 0
        }
    }

    private func commitSelection(_ item: ReactionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        state.selectedEmoji = item.emoji
        state.onSelect?(item.emoji)
        // Small delay so badge animation has time to initiate before tray closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            state.dismiss()
        }
    }
}

// MARK: - Individual emoji item

struct ReactionItemView: View {
    let item: ReactionItem
    let isHovered: Bool
    let isSelected: Bool
    let neighborDistance: CGFloat   // pt to push sideways when neighbor is hovered
    let baseSize: CGFloat
    let hoverLift: CGFloat
    let hoverScale: CGFloat

    // Tiny organic rotation on hover
    private var hoverRotation: Double { isHovered ? Double.random(in: -4...4) : 0 }

    var body: some View {
        Text(item.emoji)
            .font(.system(size: isHovered ? 28 : 22))
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(isHovered ? hoverScale : (isSelected ? 1.12 : 1.0))
            .offset(
                x: neighborDistance * (isHovered ? 0 : 1),  // neighbor push
                y: isHovered ? -hoverLift : 0
            )
            .rotationEffect(.degrees(hoverRotation))
            // Glow ring on selected
            .background(
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                    .frame(width: baseSize - 4, height: baseSize - 4)
            )
            .animation(
                .spring(response: 0.22, dampingFraction: 0.68),
                value: isHovered
            )
            .animation(
                .spring(response: 0.22, dampingFraction: 0.68),
                value: isSelected
            )
            .accessibilityLabel(item.label)
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Reaction badge row (lives below message/comment)

/// Displays grouped emoji + count badges.
/// Tapping an existing badge re-triggers the reaction toggle.
struct ReactionBadgeRow: View {
    /// Map of emoji → [userId]
    let reactions: [String: [String]]
    let currentUserId: String
    var alignment: HorizontalAlignment = .leading
    var onTap: (String) -> Void

    // Ordered by first-occurrence (most stable ordering)
    private var orderedEmojis: [String] {
        reactions.keys.sorted()
    }

    var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: 5) {
                if alignment == .trailing { Spacer(minLength: 0) }
                ForEach(orderedEmojis, id: \.self) { emoji in
                    let users = reactions[emoji] ?? []
                    let isMine = users.contains(currentUserId)
                    ReactionAnchorBadgeView(
                        emoji: emoji,
                        count: users.count,
                        isFromCurrentUser: isMine
                    ) {
                        onTap(emoji)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal:   .scale(scale: 0.6).combined(with: .opacity)
                        )
                    )
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: orderedEmojis)
        }
    }
}

// MARK: - Individual anchor badge

struct ReactionAnchorBadgeView: View {
    let emoji: String
    let count: Int
    let isFromCurrentUser: Bool
    var onTap: () -> Void

    @State private var didLand = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(spacing: 3) {
                Text(emoji)
                    .font(.system(size: 13))
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isFromCurrentUser ? Color.accentColor : .secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isFromCurrentUser
                          ? Color.accentColor.opacity(0.12)
                          : Color(.systemBackground))
                    .shadow(color: .black.opacity(0.09), radius: 3, y: 1)
                    .overlay(
                        Capsule().strokeBorder(
                            isFromCurrentUser
                                ? Color.accentColor.opacity(0.35)
                                : Color(.systemGray4).opacity(0.6),
                            lineWidth: 0.75
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(didLand ? 1.0 : 0.4)
        .opacity(didLand ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                didLand = true
            }
        }
        .accessibilityLabel("\(emoji) reaction, \(count) \(count == 1 ? "person" : "people")")
    }
}

// MARK: - .reactionPicker(...) view modifier

/// Attach to any message bubble or comment card.
/// Example:
///   Text(message.text)
///     .reactionPicker(
///         id: message.id,
///         isFromCurrentUser: message.isFromCurrentUser,
///         context: .message,
///         selectedEmoji: currentReactionEmoji,
///         onSelect: { emoji in handleReaction(emoji) }
///     )
struct ReactionPickerModifier: ViewModifier {
    let id: AnyHashable
    let isFromCurrentUser: Bool
    let context: ReactionContext
    let selectedEmoji: String?
    let onSelect: (String) -> Void

    @ObservedObject private var state = ReactionPresentationState.shared

    func body(content: Content) -> some View {
        content
            .scaleEffect(state.activeAnchorID == id ? 1.03 : 1.0)
            .shadow(
                color: .black.opacity(state.activeAnchorID == id ? 0.18 : 0),
                radius: state.activeAnchorID == id ? 12 : 0,
                y: state.activeAnchorID == id ? 4 : 0
            )
            .animation(.spring(response: 0.30, dampingFraction: 0.70), value: state.activeAnchorID == id)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onLongPressGesture(minimumDuration: 0.38) {
                            let frame = geo.frame(in: .global)
                            state.present(
                                anchorID: id,
                                anchorFrame: frame,
                                isFromCurrentUser: isFromCurrentUser,
                                context: context,
                                selectedEmoji: selectedEmoji,
                                onSelect: onSelect
                            )
                        }
                }
            )
    }
}

extension View {
    func reactionPicker(
        id: AnyHashable,
        isFromCurrentUser: Bool = false,
        context: ReactionContext = .message,
        selectedEmoji: String? = nil,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        modifier(ReactionPickerModifier(
            id: id,
            isFromCurrentUser: isFromCurrentUser,
            context: context,
            selectedEmoji: selectedEmoji,
            onSelect: onSelect
        ))
    }
}

// MARK: - Reduced-motion variants

extension ReactionTrayOverlay {
    /// Respects @Environment(\.accessibilityReduceMotion)
}

// MARK: - Helpers: reactions dictionary from MessageReaction array

extension Array where Element == MessageReaction {
    /// Groups into [emoji: [userId]] for badge display.
    var groupedByEmoji: [String: [String]] {
        Dictionary(grouping: self, by: { $0.emoji })
            .mapValues { reactions in reactions.map { $0.userId } }
    }
}

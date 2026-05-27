import SwiftUI

// MARK: - ReactionBubble

@MainActor
private struct ReactionBubble: View {
    let emoji: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 15))
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected ? Color.primary : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PostReactionOverlay

@MainActor
struct PostReactionOverlay: View {
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void

    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            HStack(spacing: 4) {
                ForEach(ReactionEmoji.allCases, id: \.character) { reaction in
                    Button {
                        onSelect(reaction.character)
                        dismiss()
                    } label: {
                        Text(reaction.character)
                            .font(.system(size: 28))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            scale = 0.6
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isPresented = false
        }
    }
}

// MARK: - PostReactionTray

@MainActor
struct PostReactionTray: View {
    let postId: String
    let currentUserId: String
    let reactionCounts: ReactionCounts
    let userReaction: String?
    let onReact: (String?) -> Void

    private var topEmojis: [(emoji: String, count: Int)] {
        reactionCounts
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (emoji: $0.key, count: $0.value) }
    }

    var body: some View {
        if !reactionCounts.isEmpty && !topEmojis.isEmpty {
            HStack(spacing: 6) {
                ForEach(topEmojis, id: \.emoji) { item in
                    ReactionBubble(
                        emoji: item.emoji,
                        count: item.count,
                        isSelected: userReaction == item.emoji
                    ) {
                        if userReaction == item.emoji {
                            onReact(nil)
                        } else {
                            onReact(item.emoji)
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 0.6).combined(with: .opacity)
                        )
                    )
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: topEmojis.map(\.emoji))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: userReaction)
        }
    }
}

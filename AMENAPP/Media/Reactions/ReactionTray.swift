import SwiftUI

// MARK: - ReactionTray
// Bottom-anchored floating tray containing all six MediaReactionType emoji buttons.
// Long-press (0.3 s) on a trigger view expands the GlassTray.
// Respects Reduce Motion and Reduce Transparency.

@MainActor
struct ReactionTray: View {
    @Binding var isPresented: Bool
    @Binding var selectedReaction: MediaReactionType?
    var onReactionSelected: (MediaReactionType) -> Void

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Haptic generators — instantiated once per render cycle.
    private let softGenerator   = UIImpactFeedbackGenerator(style: .soft)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notifGenerator  = UINotificationFeedbackGenerator()

    var body: some View {
        GlassTray(isVisible: $isPresented) {
            HStack(spacing: 4) {
                ForEach(MediaReactionType.allCases, id: \.self) { reaction in
                    reactionButton(for: reaction)
                }
            }
        }
    }

    // MARK: - Per-reaction button

    @ViewBuilder
    private func reactionButton(for reaction: MediaReactionType) -> some View {
        let isPrayer = reaction == .prayer
        let isSelected = selectedReaction == reaction

        Button {
            handleTap(reaction)
        } label: {
            Text(emoji(for: reaction))
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background {
                    if isPrayer {
                        Circle()
                            .strokeBorder(Color.amenGold, lineWidth: 2)
                    }
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .fill(Color.amenGold.opacity(0.22))
                    }
                }
                .scaleEffect(isSelected ? (reduceMotion ? 1 : 1.15) : 1)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: LiquidGlassTokens.motionFast)
                        : .spring(response: 0.35, dampingFraction: 0.75),
                    value: isSelected
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: reaction))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Actions

    private func handleTap(_ reaction: MediaReactionType) {
        if reaction == .prayer {
            notifGenerator.notificationOccurred(.success)
        } else {
            softGenerator.impactOccurred()
        }

        withAnimation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: 0.35, dampingFraction: 0.75)
        ) {
            selectedReaction = reaction
        }

        onReactionSelected(reaction)

        // Dismiss tray after a short delay so user sees the selection.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation {
                isPresented = false
            }
        }
    }

    // MARK: - Long-press trigger modifier

    /// Attach to any view to make it a long-press trigger for the tray.
    func longPressTrigger() -> some View {
        LongPressTriggerWrapper(isPresented: $isPresented) {
            self
        }
    }

    // MARK: - Helpers

    private func emoji(for type: MediaReactionType) -> String {
        switch type {
        case .heart:   return "❤️"
        case .laugh:   return "😂"
        case .prayer:  return "🙏"
        case .fire:    return "🔥"
        case .cross:   return "✝️"
        case .custom:  return "😊"
        }
    }

    private func accessibilityLabel(for type: MediaReactionType) -> String {
        switch type {
        case .heart:   return "Heart reaction"
        case .laugh:   return "Laugh reaction"
        case .prayer:  return "Prayer reaction"
        case .fire:    return "Fire reaction"
        case .cross:   return "Cross reaction"
        case .custom:  return "Custom reaction"
        }
    }
}

// MARK: - LongPressTriggerWrapper
// Wraps a content view so a 0.3 s long press opens the ReactionTray.

@MainActor
private struct LongPressTriggerWrapper<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        content()
            .onLongPressGesture(minimumDuration: 0.3) {
                mediumGenerator.impactOccurred()
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: LiquidGlassTokens.motionFast)
                        : .spring(response: 0.35, dampingFraction: 0.75)
                ) {
                    isPresented = true
                }
            }
    }
}

// MARK: - View extension for convenient attach

extension View {
    /// Makes this view a long-press trigger for a ReactionTray.
    func reactionTrayTrigger(isPresented: Binding<Bool>) -> some View {
        LongPressTriggerWrapper(isPresented: isPresented) { self }
    }
}

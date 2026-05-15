import SwiftUI

struct AmenContextualReactionButton: View {
    let icon: String
    let activeIcon: String?
    let isActive: Bool
    let accessibilityLabel: String
    let longPressAccessibilityLabel: String
    let contentText: String
    let contentType: AmenContentType
    var longPressReactions: [AmenReactionKind] = AmenReactionKind.allCases
    let action: () -> Void
    var onReactionSelected: ((AmenReactionKind) -> Void)? = nil
    var onPresentationChanged: ((AmenContextualReactionPresentation?) -> Void)? = nil

    @State private var showRing = false
    @State private var presentation: AmenContextualReactionPresentation?

    var body: some View {
        ZStack {
            Button {
                action()
                triggerPrimaryReaction()
            } label: {
                AmenReactionMorphIcon(
                    systemImage: icon,
                    fallbackSystemImage: activeIcon ?? icon,
                    isActive: isActive,
                    presentation: presentation
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    HapticManager.impact(style: .light)
                    showRing = true
                    let ringResult = AmenContextualReactionEngine.shared.reactionRingResult()
                    updatePresentation(AmenContextualReactionPresentation(result: ringResult))
                }
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(longPressAccessibilityLabel)

            if showRing {
                AmenHiddenReactionRing(reactions: longPressReactions) { reaction in
                    showRing = false
                    onReactionSelected?(reaction)
                    let result = AmenContextualReactionResult(
                        id: "ring-\(reaction.rawValue)",
                        triggerType: .longPress,
                        effectType: reaction == .heart ? .heartMorph : .amenPulse,
                        title: reaction.title,
                        microcopy: reaction.title,
                        priority: 90,
                        durationMs: 900,
                        shouldReturnToNormalState: true
                    )
                    updatePresentation(AmenContextualReactionPresentation(result: result))
                } onDismiss: {
                    showRing = false
                    clearPresentation(after: 0.1)
                }
                .offset(y: -54)
                .zIndex(10)
            }
        }
    }

    private func triggerPrimaryReaction() {
        guard let result = AmenContextualReactionEngine.shared.reactionForLike(
            contentText: contentText,
            contentType: contentType
        ) else { return }

        let morphIcon: String?
        switch result.effectType {
        case .heartMorph:
            morphIcon = "hands.sparkles"
        case .seasonalIconMorph:
            morphIcon = AmenSeasonalReactionTheme.current(for: Date())?.morphSystemImage
        default:
            morphIcon = nil
        }

        updatePresentation(
            AmenContextualReactionPresentation(
                result: result,
                morphSystemImage: morphIcon
            )
        )
    }

    private func updatePresentation(_ newPresentation: AmenContextualReactionPresentation?) {
        presentation = newPresentation
        onPresentationChanged?(newPresentation)
        guard let result = newPresentation?.result else { return }
        clearPresentation(after: Double(result.durationMs) / 1000)
    }

    private func clearPresentation(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !showRing {
                presentation = nil
                onPresentationChanged?(nil)
            }
        }
    }
}

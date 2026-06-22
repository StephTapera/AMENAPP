import SwiftUI

struct AmenInlineObjectHubActionCluster: View {
    let model: AmenObjectHubPreviewPillModel
    let actions: [AmenInlineObjectHubAction]
    let onAction: (AmenInlineObjectHubAction) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmenInlineObjectHubPill(model: model, onTap: {})
                .allowsHitTesting(false)

            actionRow
        }
        .transition(.opacity)
    }

    // MARK: - Action Row

    @ViewBuilder
    private var actionRow: some View {
        if reduceTransparency {
            solidActionRow
        } else {
            glassActionRow
        }
    }

    /// iOS 26 glass: individual glass capsule per action, linked via GlassEffectContainer so
    /// neighbouring buttons share a single refractive slab and morph between each other.
    private var glassActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.self) { action in
                        actionButton(for: action)
                            .amenGlassEffect(in: Capsule())  // must be last modifier on each button
                    }
                }
            }
        }
    }

    /// Reduce-transparency fallback: solid system-background capsule per button, no glass.
    private var solidActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    actionButton(for: action)
                        .background(Color(.systemBackground), in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.8))
                }
            }
        }
    }

    // MARK: - Individual Button

    private func actionButton(for action: AmenInlineObjectHubAction) -> some View {
        Button(actionLabel(for: action)) {
            onAction(action)
        }
        .buttonStyle(AmenHubGlassButtonStyle(reduceMotion: reduceMotion))
        .font(.systemScaled(14, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .accessibilityLabel(actionLabel(for: action))
    }

    // MARK: - Labels

    private func actionLabel(for action: AmenInlineObjectHubAction) -> String {
        switch action {
        case .openHub: return "Open Hub"
        case .openProvider: return AmenObjectHubInlineActionRanker.providerLabel(for: model.objectType)
        case .save: return "Save"
        case .discuss: return "Discuss"
        }
    }
}

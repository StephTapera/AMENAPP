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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.self) { action in
                        actionButton(action)
                    }
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func actionButton(_ action: AmenInlineObjectHubAction) -> some View {
        let label = actionLabel(for: action)
        let bg: AnyShapeStyle = reduceTransparency ? AnyShapeStyle(Color.white.opacity(0.92)) : AnyShapeStyle(.thinMaterial)
        Button(label) { onAction(action) }
            .buttonStyle(AmenHubGlassButtonStyle(reduceMotion: reduceMotion))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(bg, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
            .foregroundStyle(.black.opacity(0.86))
            .accessibilityLabel(label)
    }

    private func actionLabel(for action: AmenInlineObjectHubAction) -> String {
        switch action {
        case .openHub: return "Open Hub"
        case .openProvider: return AmenObjectHubInlineActionRanker.providerLabel(for: model.objectType)
        case .save: return "Save"
        case .discuss: return "Discuss"
        }
    }
}

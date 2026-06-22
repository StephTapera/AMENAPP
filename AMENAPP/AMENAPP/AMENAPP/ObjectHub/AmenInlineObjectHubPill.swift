import SwiftUI

struct AmenInlineObjectHubPill: View {
    let model: AmenObjectHubPreviewPillModel
    let onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: model.iconName)
                    .font(.systemScaled(12, weight: .semibold))

                Text(model.aggregateText)
                    .font(.systemScaled(12.5, weight: .medium))
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(.black.opacity(0.35))

                Text(model.actionText)
                    .font(.systemScaled(12.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.black.opacity(contrast == .increased ? 0.95 : 0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(backgroundFill, in: Capsule())
            .overlay(Capsule().stroke(borderColor, lineWidth: 1))
            .overlay(specularOverlay)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AmenHubGlassButtonStyle(reduceMotion: reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityHint("Opens public activity around this.")
    }

    private var backgroundFill: some ShapeStyle {
        if reduceTransparency || contrast == .increased {
            AnyShapeStyle(Color.white.opacity(0.92))
        } else {
            AnyShapeStyle(.thinMaterial)
        }
    }

    private var borderColor: Color {
        if reduceTransparency || contrast == .increased {
            return Color.black.opacity(0.14)
        }
        return Color.white.opacity(0.55)
    }

    private var specularOverlay: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.04), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .allowsHitTesting(false)
    }
}

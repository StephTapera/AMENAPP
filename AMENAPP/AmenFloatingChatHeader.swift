import SwiftUI

struct AmenChatStatusChip: View {
    let text: String
    let systemImage: String
    let accessibilityDescription: String
    let isInteractive: Bool
    let action: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    var body: some View {
        Group {
            if let action, isInteractive {
                Button(action: action) { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens details")
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var content: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.systemScaled(9, weight: .semibold))
            Text(text)
                .font(.systemScaled(11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.primary.opacity(0.72))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(accessibilityContrast == .increased ? 0.22 : 0.08), lineWidth: accessibilityContrast == .increased ? 1.2 : 0.8)
        )
    }
}

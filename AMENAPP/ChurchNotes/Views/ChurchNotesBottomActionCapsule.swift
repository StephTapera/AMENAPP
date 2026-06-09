import SwiftUI

struct ChurchNotesBottomActionCapsule: View {
    struct Action: Identifiable {
        let id: String
        let label: String
        let icon: String
        let handler: () -> Void
    }

    let actions: [Action]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(actions) { action in
                    Button(action: action.handler) {
                        ViewThatFits(in: .horizontal) {
                            Label(action.label, systemImage: action.icon)
                                .font(.systemScaled(12, weight: .medium))
                                .labelStyle(.titleAndIcon)

                            Image(systemName: action.icon)
                                .font(.systemScaled(16, weight: .medium))
                                .frame(width: 34, height: 34)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(.primary.opacity(0.74))
                        .frame(minWidth: 58)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.label)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color(.systemBackground).opacity(0.68)))
                .overlay(Capsule().strokeBorder(ChurchNotesDesignTokens.Colors.neutralBorder, lineWidth: 0.5))
        )
    }
}

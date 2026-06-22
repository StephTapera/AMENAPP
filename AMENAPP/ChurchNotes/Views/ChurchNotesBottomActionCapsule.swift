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
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    Button(action: action.handler) {
                        ViewThatFits(in: .horizontal) {
                            Label(action.label, systemImage: action.icon)
                                .font(.systemScaled(13, weight: .semibold))
                                .labelStyle(.titleAndIcon)

                            Image(systemName: action.icon)
                                .font(.systemScaled(17, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(.primary.opacity(0.78))
                        .frame(minWidth: 64)
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .amenLiquidGlassCapsuleSurface(isSelected: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.label)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .amenLiquidGlassCapsuleSurface(isSelected: false)
    }
}

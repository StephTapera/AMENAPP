import SwiftUI

struct SmartMessageActionTray: View {
    let actions: [SmartMessageAction]
    var onAction: (SmartMessageAction) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if AMENFeatureFlags.shared.smartMessageIntelligenceEnabled && !actions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions.prefix(6)) { action in
                        Button {
                            AmenSmartMessageIntelligenceService.shared.trackActionTapped(action)
                            onAction(action)
                        } label: {
                            Image(systemName: action.iconSystemName)
                                .font(.body.weight(.semibold))
                                .frame(width: 42, height: 42)
                                .background(background, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.title)
                        .accessibilityHint(action.subtitle)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
        }
    }

    private var background: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.regularMaterial)
    }
}

import SwiftUI

struct AmenDiscoverTopicRail: View {
    let filters: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Button {
                        HapticManager.impact(style: .light)
                        onSelect(filter)
                    } label: {
                        Text(filter)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected == filter ? Color(.label) : Color(.secondaryLabel))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selected == filter
                                    ? AnyView(
                                        Capsule(style: .continuous)
                                            .fill(Color(.systemBackground))
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                                            )
                                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                                      )
                                    : AnyView(AmenLiquidGlassPill(intensity: .light) { Color.clear })
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter \(filter)")
                    .accessibilityAddTraits(selected == filter ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

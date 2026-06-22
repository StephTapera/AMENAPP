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
                            .foregroundStyle(selected == filter ? .black : .black.opacity(0.72))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AmenLiquidGlassPill(intensity: selected == filter ? .prominent : .light) { Color.clear })
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter \(filter)")
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

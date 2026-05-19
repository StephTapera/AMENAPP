import SwiftUI

struct AmenDiscoverGlassTabBar: View {
    @Binding var selected: String
    let tabs: [String]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    HapticManager.impact(style: .light)
                    selected = tab
                } label: {
                    Text(tab)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected == tab ? .black : .black.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selected == tab {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .matchedGeometryEffect(id: "discover_tab_highlight", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.65), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
    }
}

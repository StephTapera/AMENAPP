import SwiftUI

struct AmenDiscoverSearchCapsule: View {
    @Binding var text: String
    let compactProgress: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.black.opacity(0.65))
            TextField("Search churches, testimonies, scripture", text: $text)
                .textInputAutocapitalization(.never)
                .font(.body)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AmenLiquidGlassPill(intensity: .light) { Color.clear })
        .scaleEffect(1 - (compactProgress * 0.04), anchor: .top)
        .accessibilityLabel("Discover search")
    }
}

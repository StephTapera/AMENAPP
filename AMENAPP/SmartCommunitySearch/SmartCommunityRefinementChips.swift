import SwiftUI

struct SmartCommunityRefinementChips: View {
    let chips: [String]
    let onChipTapped: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        onChipTapped(chip)
                    } label: {
                        Text(chip)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 1))
                    }
                    .accessibilityLabel("Refine search: \(chip)")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityLabel("Search refinements")
    }
}

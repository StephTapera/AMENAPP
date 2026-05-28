import SwiftUI

struct MoodTagBadge: View {
    var tags: [MoodTag]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(2)) { tag in
                GlassBadge(
                    icon: "",
                    label: "\(tag.emoji) \(tag.label)",
                    tint: .white
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tags.prefix(2).map { "\($0.label)" }.joined(separator: ", "))
    }
}

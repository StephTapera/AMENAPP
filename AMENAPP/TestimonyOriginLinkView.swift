import SwiftUI

/// Compact prayer origin link shown on answered-prayer testimony posts.
struct TestimonyOriginLinkView: View {
    let post: Post
    var onTapOrigin: (() -> Void)? = nil

    private let charcoal   = Color(red: 0.110, green: 0.110, blue: 0.102) // #1c1c1a
    private let originBg   = Color(red: 0.102, green: 0.039, blue: 0.016) // #1a0a04

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Answered prayer badge
            HStack(spacing: 5) {
                Circle()
                    .fill(originBg)
                    .frame(width: 7, height: 7)
                Text("Answered prayer")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }

            // Origin link row
            if let prayerText = post.linkedPrayerText {
                Button(action: { onTapOrigin?() }) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(originBg)
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("THIS ANSWERED")
                                .font(.systemScaled(9, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .kerning(0.5)
                            Text(prayerText)
                                .font(.systemScaled(11).italic())
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

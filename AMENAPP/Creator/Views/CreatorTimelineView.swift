import SwiftUI

struct CreatorTimelineView: View {
    let items: [CreatorTimelineItem]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                CreatorGlassCard {
                    Text(item.title)
                        .font(AMENFont.medium(13))
                        .foregroundStyle(Color.black.opacity(0.7))
                }
            }
        }
    }
}

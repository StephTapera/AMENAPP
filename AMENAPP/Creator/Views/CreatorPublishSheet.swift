import SwiftUI

struct CreatorPublishSheet: View {
    let targets: [CreatorPublishTarget]

    var body: some View {
        VStack(spacing: 12) {
            CreatorTopBar(title: "Publish", subtitle: "Choose a destination")

            ForEach(targets, id: \.self) { target in
                CreatorGlassCard {
                    Text(target.rawValue)
                        .font(AMENFont.semiBold(14))
                }
            }
        }
        .padding(20)
        .background(Color.white)
    }
}

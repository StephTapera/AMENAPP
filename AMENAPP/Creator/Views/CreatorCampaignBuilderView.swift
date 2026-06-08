import SwiftUI

struct CreatorCampaignBuilderView: View {
    @State private var eventName: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CreatorTopBar(title: "Campaign Kit", subtitle: "Guided build")

                CreatorGlassCard {
                    TextField("Event name", text: $eventName)
                        .font(AMENFont.medium(14))
                }

                CreatorBottomRail(
                    primaryActionTitle: "Generate",
                    secondaryActionTitle: "Save draft",
                    primaryAction: {},
                    secondaryAction: {}
                )
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
    }
}

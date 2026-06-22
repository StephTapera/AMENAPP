import SwiftUI

struct CreatorCampaignBuilderView: View {
    @State private var eventName: String = ""
    @State private var isGenerating: Bool = false
    @State private var savedToastVisible: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CreatorTopBar(title: "Campaign Kit", subtitle: "Guided build")

                CreatorGlassCard {
                    TextField("Event name", text: $eventName)
                        .font(AMENFont.medium(14))
                }

                if savedToastVisible {
                    Text("Draft saved")
                        .font(AMENFont.medium(13))
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                CreatorBottomRail(
                    primaryActionTitle: isGenerating ? "Generating…" : "Generate",
                    secondaryActionTitle: "Save draft",
                    primaryAction: {
                        guard !eventName.trimmingCharacters(in: .whitespaces).isEmpty, !isGenerating else { return }
                        isGenerating = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            await MainActor.run { isGenerating = false }
                            NotificationCenter.default.post(name: Notification.Name("amenGenerateCampaign"), object: eventName)
                        }
                    },
                    secondaryAction: {
                        withAnimation { savedToastVisible = true }
                        NotificationCenter.default.post(name: Notification.Name("amenSaveCampaignDraft"), object: eventName)
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run { withAnimation { savedToastVisible = false } }
                        }
                    }
                )
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
    }
}

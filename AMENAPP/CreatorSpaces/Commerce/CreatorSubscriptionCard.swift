import SwiftUI

struct CreatorSubscriptionCard: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(width: 42, height: 42)
                .amenGlassSurface(shape: .rounded(14), background: .quiet, placement: .inline)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AMENFont.medium(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(isEnabled ? "Ready" : "Off")
                .font(AMENFont.semiBold(11))
                .foregroundStyle(isEnabled ? Color.green : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .amenGlassSurface(shape: .capsule, background: .quiet, placement: .inline)
        }
        .padding(14)
        .amenGlassSurface(shape: .rounded(22), background: .balanced, placement: .inline)
    }
}

struct CreatorCommerceOverviewView: View {
    @ObservedObject private var flags = CreatorSpacesFeatureFlags.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CreatorSpaceHeader(
                    title: "Creator Commerce",
                    subtitle: "Paid spaces, subscriptions, event passes, and resources stay gated by server entitlements."
                )
                CreatorSubscriptionCard(
                    title: "Creator subscriptions",
                    subtitle: "Connect-backed subscriptions for creators, churches, schools, ministries, and teams.",
                    isEnabled: flags.creatorSubscriptionsEnabled
                )
                CreatorSubscriptionCard(
                    title: "Premium resources",
                    subtitle: "Media packs, classes, studies, event passes, and workshops share one entitlement model.",
                    isEnabled: flags.creatorSubscriptionsEnabled
                )
            }
            .padding(20)
        }
        .navigationTitle("Commerce")
    }
}

import SwiftUI

struct IntelligenceTierHeaderView: View {
    let tier: IntelligenceTier

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tier.displayName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(tierDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(tier.displayName). \(tierDescription)")
    }

    private var tierDescription: String {
        switch tier {
        case .spiritual:
            return "What the Spirit may be inviting you into today."
        case .community:
            return "What your local church family is carrying."
        case .family:
            return "For your household and those closest to you."
        case .local:
            return "Opportunities to serve and connect near you."
        case .global:
            return "How the Body of Christ is moving in the world."
        }
    }
}

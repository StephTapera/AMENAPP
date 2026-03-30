import SwiftUI

struct TwoFourTwoSubscriptionView: View {
    @Binding var currentTier: AMENSubscriptionTier
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    private let tiers: [(AMENSubscriptionTier, String, [String])] = [
        (.grow,       "For personal growth",
         ["Sermon Library search", "Mentorship matching", "Intercessors Network", "Covenant Academy", "Living Memory (full access)"]),
        (.lead,       "For church & ministry leaders",
         ["Everything in Grow", "Flock Intelligence briefings", "Covenant Metrics", "Prayer Wall elder tools", "Pastoral care dashboard"]),
        (.enterprise, "For organizations",
         ["Everything in Lead", "Multi-campus support", "API access", "Dedicated onboarding", "Custom integrations"]),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.18)).frame(width: 36, height: 4).padding(.top, 12).padding(.bottom, 20)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        VStack(spacing: 8) {
                            Text("242 Resources").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
                            Text("Unlock the full depth of Acts 2:42")
                                .font(.system(size: 14, design: .rounded)).foregroundColor(.white.opacity(0.45)).multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 28).padding(.bottom, 28)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)

                        // Free tier note
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(Color(red: 0.20, green: 0.72, blue: 0.44))
                            Text("Core features are always free").font(.system(size: 13, design: .rounded)).foregroundColor(.white.opacity(0.55))
                        }
                        .padding(.bottom, 24)
                        .opacity(appeared ? 1 : 0)

                        // Tier cards
                        VStack(spacing: 12) {
                            ForEach(Array(tiers.enumerated()), id: \.offset) { index, item in
                                let (tier, subtitle, features) = item
                                TierCard(tier: tier, subtitle: subtitle, features: features, isCurrent: currentTier == tier) {
                                    if tier == .enterprise {
                                        if let url = URL(string: "mailto:amenappmarketing@gmail.com?subject=Enterprise%20Inquiry") {
                                            UIApplication.shared.open(url)
                                        }
                                    } else {
                                        currentTier = tier
                                        dismiss()
                                    }
                                }
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.08 + 0.15), value: appeared)
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 40)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true } }
    }
}

private struct TierCard: View {
    let tier: AMENSubscriptionTier
    let subtitle: String
    let features: [String]
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(tier.displayName).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundColor(.white)
                        if isCurrent {
                            Text("current").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(tier.badgeColor)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(tier.badgeColor.opacity(0.15)))
                        }
                    }
                    Text(subtitle).font(.system(size: 12, design: .rounded)).foregroundColor(.white.opacity(0.40))
                }
                Spacer()
                Text(tier.price).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(tier.badgeColor)
            }
            Divider().background(Color.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 7) {
                ForEach(features, id: \.self) { f in
                    HStack(spacing: 8) {
                        Circle().fill(tier.badgeColor).frame(width: 4, height: 4)
                        Text(f).font(.system(size: 12, design: .rounded)).foregroundColor(.white.opacity(0.60))
                    }
                }
            }
            Button(action: action) {
                Text(tier.isContactSales ? "Contact Sales" : isCurrent ? "Current Plan" : "Unlock \(tier.displayName)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(isCurrent ? .white.opacity(0.40) : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isCurrent ? Color.white.opacity(0.06) : tier.badgeColor.opacity(0.85)))
            }
            .disabled(isCurrent)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 1, opacity: 0.04))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isCurrent ? tier.badgeColor.opacity(0.40) : Color.white.opacity(0.08), lineWidth: isCurrent ? 1 : 0.5))
        )
    }
}

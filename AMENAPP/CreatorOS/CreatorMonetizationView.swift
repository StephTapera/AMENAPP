// CreatorMonetizationView.swift
// AMENAPP — CreatorOS
// Subscription tiers, donations, and exclusive content management for creators.

import SwiftUI

// MARK: - Tier Model

struct CreatorTier: Identifiable {
    let id: String
    var name: String
    var monthlyPrice: Double
    var description: String
    var perks: [String]
    var subscriberCount: Int
    var isActive: Bool

    static let previews: [CreatorTier] = [
        CreatorTier(id: "t1", name: "Community", monthlyPrice: 4.99,
                    description: "Support the ministry and join exclusive discussions",
                    perks: ["Exclusive weekly devotionals", "Members-only Space", "Early access to events"],
                    subscriberCount: 34, isActive: true),
        CreatorTier(id: "t2", name: "Partner", monthlyPrice: 14.99,
                    description: "Go deeper with direct mentoring access",
                    perks: ["Everything in Community", "Monthly group mentoring session", "Exclusive study guides", "Prayer request priority"],
                    subscriberCount: 11, isActive: true),
        CreatorTier(id: "t3", name: "Covenant", monthlyPrice: 29.99,
                    description: "Full access including 1:1 mentoring",
                    perks: ["Everything in Partner", "Quarterly 1:1 mentoring call", "Personalized growth plan", "Co-creator opportunities"],
                    subscriberCount: 3, isActive: false)
    ]
}

// MARK: - Monetization View

struct CreatorMonetizationView: View {
    @State private var tiers: [CreatorTier] = CreatorTier.previews
    @State private var showNewTierSheet = false
    @State private var donationsEnabled = true
    @State private var suggestedDonation = "10"

    var totalMonthlyRevenue: Double {
        tiers.filter(\.isActive).reduce(0.0) { $0 + ($1.monthlyPrice * Double($1.subscriberCount)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Revenue summary
                revenueCard

                // Tiers
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Subscription Tiers")
                            .font(.headline)
                        Spacer()
                        Button {
                            showNewTierSheet = true
                        } label: {
                            Label("Add Tier", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(tiers) { tier in
                        TierCard(tier: tier) { updatedTier in
                            if let idx = tiers.firstIndex(where: { $0.id == updatedTier.id }) {
                                tiers[idx] = updatedTier
                            }
                        }
                    }
                }

                // Donations
                VStack(alignment: .leading, spacing: 12) {
                    Text("One-Time Donations")
                        .font(.headline)

                    Toggle("Accept Donations", isOn: $donationsEnabled)
                        .font(.subheadline)

                    if donationsEnabled {
                        HStack {
                            Text("Suggested Amount")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("$")
                                    .foregroundStyle(.secondary)
                                TextField("10", text: $suggestedDonation)
                                    .keyboardType(.numberPad)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Platform note
                VStack(alignment: .leading, spacing: 6) {
                    Label("About Payments", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Subscriptions and donations are processed via Stripe. AMEN takes 0% platform fee — 100% goes to your ministry minus Stripe's standard processing fee.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .navigationTitle("Monetization")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Revenue Card

    private var revenueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Revenue")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("$\(String(format: "%.2f", totalMonthlyRevenue))")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.accentColor)
            Text("From \(tiers.filter(\.isActive).reduce(0) { $0 + $1.subscriberCount }) active subscribers")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Tier Card

private struct TierCard: View {
    let tier: CreatorTier
    let onUpdate: (CreatorTier) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(tier.name)
                                .font(.subheadline.weight(.semibold))
                            if !tier.isActive {
                                Text("Inactive")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        Text("$\(String(format: "%.2f", tier.monthlyPrice))/mo · \(tier.subscriberCount) subscribers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.3).padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Perks").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(tier.perks, id: \.self) { perk in
                        Label(perk, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    // Activate/deactivate
                    Button {
                        var updated = tier
                        updated.isActive.toggle()
                        onUpdate(updated)
                    } label: {
                        Text(tier.isActive ? "Deactivate Tier" : "Activate Tier")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tier.isActive ? .red : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CreatorMonetizationView()
    }
}

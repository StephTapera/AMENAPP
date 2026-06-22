import SwiftUI

// MARK: - Covenant Paywall View
// Context-aware paywall — shown when a user taps locked content.
// Never uses dark-pattern language. Shows what unlocks, why it matters,
// creator message, tier comparison, trust badges, and free preview.

struct AmenCovenantPaywallView: View {
    let covenant: Covenant
    let context: PaywallContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTier: CovenantTier?
    @ObservedObject private var checkoutService = AmenCovenantCheckoutService.shared

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f
    }()

    enum PaywallContext {
        case lockedRoom(roomName: String)
        case lockedEvent(eventTitle: String)
        case premiumDigestItem(creatorName: String)
        case general

        var headline: String {
            switch self {
            case .lockedRoom(let name):        return "Unlock \(name)"
            case .lockedEvent(let title):      return "Join: \(title)"
            case .premiumDigestItem(let name): return "Support \(name)"
            case .general:                     return "Join This Community"
            }
        }

        var contextExplanation: String {
            switch self {
            case .lockedRoom:        return "This room is available to paid members."
            case .lockedEvent:       return "This event is available to members with the right tier."
            case .premiumDigestItem: return "This content is part of a paid membership."
            case .general:           return "Membership unlocks the full community experience."
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                    contextBannerSection
                    creatorMessageSection
                    tierComparisonSection
                    previewSection
                    trustSection
                    ctaSection
                    Spacer(minLength: 32)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not Now") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            AsyncImage(url: URL(string: covenant.coverImageURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(
                    colors: [.purple.opacity(0.4), .indigo.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, Color(uiColor: .systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            HStack(spacing: 12) {
                AsyncImage(url: URL(string: covenant.avatarURL ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.purple.opacity(0.2)
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .offset(y: -26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(covenant.name)
                        .font(.title3.weight(.bold))
                    Text(covenant.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, -26)

            AmenTrustBadgeRow(badges: covenant.trustBadges, size: .standard)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Context Banner

    private var contextBannerSection: some View {
        VStack(spacing: 8) {
            Text(context.headline)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(context.contextExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    // MARK: - Creator Message

    private var creatorMessageSection: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: URL(string: covenant.avatarURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: { Color.purple.opacity(0.2) }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("\"\(covenant.description)\"")
                    .font(.subheadline.italic())
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                Text("— \(covenant.name) Creator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.purple.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Tier Comparison

    private var tierComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Access")
                .font(.headline)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(covenant.tiers) { tier in
                        TierCard(
                            tier: tier,
                            isSelected: selectedTier?.id == tier.id
                        ) {
                            selectedTier = tier
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Free Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Free Preview")
                .font(.headline)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(["Welcome post from the creator", "Community guidelines", "One featured teaching"], id: \.self) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "lock.open.fill")
                            .font(.systemScaled(14))
                            .foregroundStyle(.green)
                            .frame(width: 28)
                        Text(item)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    Divider().padding(.leading, 56)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Trust Section

    private var trustSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                trustPill(icon: "person.2.fill", label: "\(covenant.paidMemberCount) members")
                trustPill(icon: "heart.fill",   label: "Active community")
                trustPill(icon: "xmark.circle", label: "Cancel anytime")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func trustPill(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            if let tier = selectedTier ?? covenant.tiers.first {
                Button {
                    guard !checkoutService.isLoading else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        await checkoutService.startCheckout(
                            covenantId: covenant.id ?? "",
                            tierId: tier.id
                        )
                    }
                } label: {
                    HStack {
                        if checkoutService.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Join for \(formattedPrice(tier))")
                                .font(.headline)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.purple.opacity(checkoutService.isLoading ? 0.6 : 1.0))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .disabled(checkoutService.isLoading)

                if case .failed(let err) = checkoutService.checkoutState {
                    Text(err.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Text("Cancel anytime. No dark-pattern pressure here — just a real community that matters to you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private func formattedPrice(_ tier: CovenantTier) -> String {
        let formatter = Self.currencyFormatter
        formatter.currencyCode = tier.currency
        let priceStr = formatter.string(from: NSNumber(value: tier.price)) ?? "\(tier.price)"
        return "\(priceStr)\(tier.billingPeriod.displayLabel)"
    }
}

// MARK: - Tier Card

private struct TierCard: View {
    let tier: CovenantTier
    let isSelected: Bool
    let onSelect: () -> Void

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f
    }()

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tier.name)
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    if tier.isPopular {
                        Text("Popular")
                            .font(.systemScaled(9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.purple))
                    }
                }

                Text(tier.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tier.perks.prefix(4), id: \.self) { perk in
                        Label(perk, systemImage: "checkmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(formatPrice(tier))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.purple)
            }
            .padding(16)
            .frame(width: 200, height: 240)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func formatPrice(_ tier: CovenantTier) -> String {
        let formatter = Self.currencyFormatter
        formatter.currencyCode = tier.currency
        let s = formatter.string(from: NSNumber(value: tier.price)) ?? "\(tier.price)"
        return "\(s)\(tier.billingPeriod.displayLabel)"
    }
}

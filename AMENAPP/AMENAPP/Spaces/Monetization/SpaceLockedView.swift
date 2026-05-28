// SpaceLockedView.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Paywall / locked-preview for paid Spaces.
//
// Layout:
//   - Blurred teaser background + 3 placeholder message bubbles
//   - Glass card overlay: avatar, title, pricing, [Unlock Space] gold button,
//     [Restore Purchase] link (one-time only)
//   - Grace banner at top when state == .grace
//   - Spring dissolve: glass card fades + scales when state becomes .active
//
// Import into Agent C's SpaceDetailView:
//   SpaceLockedView(space: space, viewModel: vm)
//
// Parameters:
//   space:     AmenSpace — the paid space being gated
//   viewModel: SpaceEntitlementViewModel — shared with parent detail view

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - SpaceLockedView

struct SpaceLockedView: View {

    let space: AmenSpace
    @ObservedObject var viewModel: SpaceEntitlementViewModel

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        ZStack {
            teaserBackground

            VStack(spacing: 0) {
                Spacer()
                glassCard
                    .padding(.horizontal, 24)
                    .opacity(viewModel.state == .active ? 0 : 1)
                    .scaleEffect(viewModel.state == .active ? 0.92 : 1)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.18)
                            : .spring(response: 0.44, dampingFraction: 0.72),
                        value: viewModel.state == .active
                    )
                Spacer()
            }

            if viewModel.state == .grace {
                VStack {
                    graceBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(Motion.liquidSpringAdaptive, value: viewModel.state == .grace)
            }
        }
        .task { await viewModel.check(space: space) }
        .onDisappear {
            if let spaceId = space.id { viewModel.stopListening(spaceId: spaceId) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Locked Space: \(space.title). \(pricingAccessibilityLabel)")
    }

    // MARK: - Teaser Background

    @ViewBuilder
    private var teaserBackground: some View {
        if let avatarURL = space.avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .blur(radius: 24)
                        .overlay(Color.black.opacity(0.50))
                default:
                    gradientBackground
                }
            }
            .ignoresSafeArea()
        } else {
            gradientBackground.ignoresSafeArea()
        }

        VStack(alignment: .leading, spacing: 0) {
            teaserMessages
                .padding(.horizontal, 16)
                .padding(.top, 44)
                .blur(radius: 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Spacer()
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: [
                AmenTheme.Colors.amenBlack,
                AmenTheme.Colors.amenPurple.opacity(0.25),
                AmenTheme.Colors.amenBlack
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Teaser Message Bubbles

    private var teaserMessages: some View {
        VStack(alignment: .leading, spacing: 12) {
            teaserBubble(text: "Join us as we dive deeper into this week's passage…", leading: true)
            teaserBubble(text: "There's so much richness here — unlock to see the full discussion.", leading: false)
            teaserBubble(text: "Looking forward to exploring this together!", leading: true)
        }
    }

    private func teaserBubble(text: String, leading: Bool) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.80))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial).opacity(0.6)
            }
            .frame(maxWidth: 280, alignment: leading ? .leading : .trailing)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    // MARK: - Glass Card

    private var glassCard: some View {
        VStack(spacing: 20) {
            spaceAvatarHeader
            pricingSection
            purchaseButtons
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundSecondary)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 10)
    }

    // MARK: - Avatar + Title

    private var spaceAvatarHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 68, height: 68)
                    .overlay { Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.5) }

                if let avatarURL = space.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(width: 68, height: 68).clipShape(Circle())
                        default: spaceTypeIcon
                        }
                    }
                } else {
                    spaceTypeIcon
                }
            }
            .accessibilityHidden(true)

            Text(space.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Community Space")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
    }

    private var spaceTypeIcon: some View {
        Image(systemName: spaceSystemImage)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(AmenTheme.Colors.amenGold)
    }

    private var spaceSystemImage: String {
        switch space.type {
        case .chat:         return "bubble.left.and.bubble.right.fill"
        case .bibleStudy:   return "books.vertical.fill"
        case .group:        return "person.3.fill"
        case .announcement: return "megaphone.fill"
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: 6) {
            Text(pricingLabel)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityLabel("Price: \(pricingLabel)")
            Text(intervalLabel)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            if let config = space.priceConfig {
                Text(SpacesFeeCalculatorE.feePreviewString(
                    grossCents: config.amountCents,
                    currency: config.currency
                ))
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Buttons

    private var purchaseButtons: some View {
        VStack(spacing: 12) {
            // [Unlock Space] — amenGold
            Button {
                Task { await viewModel.purchase(space: space) }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "lock.open.fill")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    Text(viewModel.isPurchasing ? "Processing…" : "Unlock Space")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(AmenTheme.Colors.amenGold,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: AmenTheme.Colors.amenGold.opacity(0.35), radius: 10, x: 0, y: 4)
            }
            .disabled(viewModel.isPurchasing)
            .accessibilityLabel(viewModel.isPurchasing ? "Processing purchase" : "Unlock Space")
            .accessibilityHint(viewModel.isPurchasing ? "" : "Double-tap to purchase access")

            if let error = viewModel.purchaseError {
                Text(error.localizedDescription)
                    .font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error: \(error.localizedDescription)")
            }

            // Restore — one-time spaces only
            if space.accessPolicy == .oneTime {
                Button {
                    Task { await viewModel.restore(space: space) }
                } label: {
                    Text("Restore Purchase")
                        .font(.footnote)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restore Purchase")
                .accessibilityHint("Double-tap if you have already purchased access")
            }
        }
    }

    // MARK: - Grace Banner

    private var graceBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .accessibilityHidden(true)
            Text("Your payment is processing — you still have access.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundSecondary)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AmenTheme.Colors.amenGold.opacity(0.08))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AmenTheme.Colors.amenGold.opacity(0.30), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your payment is processing. You still have access.")
    }

    // MARK: - Labels

    private var pricingLabel: String {
        guard let config = space.priceConfig else { return "Free" }
        let dollars = Double(config.amountCents) / 100.0
        let base = String(format: "$%.2f", dollars)
        switch config.interval?.lowercased() {
        case "month": return "\(base)/month"
        case "year":  return "\(base)/year"
        default:      return "\(base) one-time"
        }
    }

    private var intervalLabel: String {
        guard let config = space.priceConfig else { return "" }
        switch config.interval?.lowercased() {
        case "month": return "Monthly subscription"
        case "year":  return "Yearly subscription"
        default:      return "One-time access"
        }
    }

    private var pricingAccessibilityLabel: String {
        "\(pricingLabel). \(intervalLabel). Double-tap Unlock Space to purchase."
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SpaceLockedView — oneTime") {
    let space = AmenSpace(
        communityId: "com1",
        type: .bibleStudy,
        title: "Deep Dive: Romans",
        description: "A weekly study of Paul's letter to the Romans.",
        avatarURL: nil,
        createdBy: "user1",
        createdAt: Timestamp(date: Date()),
        accessPolicy: .oneTime,
        priceConfig: SpacePriceConfig(amountCents: 999, currency: "usd", interval: nil),
        sharedWith: []
    )
    SpaceLockedView(space: space, viewModel: SpaceEntitlementViewModel())
}

#Preview("SpaceLockedView — recurring") {
    let space = AmenSpace(
        communityId: "com1",
        type: .chat,
        title: "Community Chat",
        description: nil,
        avatarURL: nil,
        createdBy: "user1",
        createdAt: Timestamp(date: Date()),
        accessPolicy: .recurring,
        priceConfig: SpacePriceConfig(amountCents: 499, currency: "usd", interval: "month"),
        sharedWith: []
    )
    SpaceLockedView(space: space, viewModel: SpaceEntitlementViewModel())
}
#endif

// LockedPreviewShell.swift
// AMENAPP — Spaces v2 Shared Components (Agent C)
//
// Glass paywall teaser rendered when a Space is gated and the user has no entitlement.
// Purchase action is wired by Agent E — this shell provides the hook via onUnlock.
// Import this — never re-implement. See CONTRACT_C.md for full API.

import SwiftUI

/// Glass paywall teaser rendered when a Space is gated and user has no entitlement.
/// Purchase action is wired by Agent E — this shell provides the hook via onUnlock.
struct LockedPreviewShell: View {

    let space: AmenSpaceExtended
    /// Agent E wires this to its SpacesPurchaseSheet presentation.
    /// This view calls onUnlock; caller owns the sheet state.
    let onUnlock: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var priceText: String? {
        guard let price = space.priceConfig else { return nil }
        let dollars = Double(price.amountCents) / 100.0
        let formatted = String(format: "$%.2f", dollars)
        if let interval = price.interval, !interval.isEmpty {
            return "\(formatted) / \(interval)"
        }
        return "\(formatted) one-time"
    }

    var body: some View {
        ZStack {
            lockBackground

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .accessibilityHidden(true)

                Text(space.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let desc = space.description, !desc.isEmpty {
                    Text(desc)
                        .font(.body)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 32)
                }

                // Price chip
                if let priceLabel = priceText {
                    Text(priceLabel)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            Capsule(style: .continuous)
                                .fill(AmenTheme.Colors.amenGold.opacity(0.12))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(AmenTheme.Colors.amenGold.opacity(0.38), lineWidth: 0.8)
                                }
                        }
                        .accessibilityLabel("Price: \(priceLabel)")
                }

                // Unlock CTA — Agent E wires onUnlock to SpacesPurchaseSheet
                AmenLiquidGlassPillButton(
                    title: "Unlock Space",
                    systemImage: "lock.open",
                    isLoading: false,
                    isDisabled: false,
                    hint: "Opens the purchase flow for this Space.",
                    action: onUnlock
                )
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.vertical, 24)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                        .fill(AmenTheme.Colors.backgroundSecondary)
                } else {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                        .fill(LiquidGlassTokens.blurThin)
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Locked Space: \(space.title). Double-tap to unlock.")
        .accessibilityAction(named: "Unlock") {
            onUnlock()
        }
    }

    // MARK: - Lock background

    @ViewBuilder
    private var lockBackground: some View {
        if let avatarURL = space.avatarURL, !avatarURL.isEmpty {
            CachedAsyncImage(url: URL(string: avatarURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                    .overlay(Color.black.opacity(0.45))
            } placeholder: {
                gradientBackground
            }
            .ignoresSafeArea()
        } else {
            gradientBackground
                .ignoresSafeArea()
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: [
                AmenTheme.Colors.amenBlack,
                AmenTheme.Colors.amenPurple.opacity(0.30),
                AmenTheme.Colors.amenBlack
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#if DEBUG
#Preview("LockedPreviewShell") {
    let space = AmenSpaceExtended(
        communityId: "community_1",
        type: .bibleStudy,
        title: "Deep Dive: Romans",
        description: "A weekly study of Paul's letter to the Romans, exploring grace, faith, and transformation.",
        avatarURL: nil,
        createdBy: "user_1",
        createdAt: Date(),
        accessPolicy: .recurring,
        priceConfig: PriceConfig(amountCents: 999, currency: "usd", interval: "month"),
        sharedWith: [],
        isDeleted: false
    )

    LockedPreviewShell(space: space) {
        print("Unlock tapped")
    }
}
#endif

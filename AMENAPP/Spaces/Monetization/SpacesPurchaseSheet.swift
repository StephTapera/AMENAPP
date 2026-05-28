// SpacesPurchaseSheet.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Glass purchase sheet rendered when a user taps unlock on a paid Space.
//
// Wiring into LockedPreviewShell (Agent C):
//   C's LockedPreviewShell calls onUnlock -> caller sets isPurchaseSheetPresented = true
//   -> SpacesPurchaseSheet is presented as a sheet.
//   See CONTRACT_E.md "LockedPreviewShell Wiring" for the full pattern.
//
// If C's LockedPreviewShell is not yet available, use SpacePurchasePresenting (below).

import SwiftUI

// MARK: - SpacePurchasePresenting (bridge protocol for Agent C)
//
// TODO(Agent C): LockedPreviewShell should conform to or wrap this protocol.
// C's LockedPreviewShell passes `onUnlock` to SpacesPurchaseSheet's presenter.
// Once C's concrete type is available, callers can remove this protocol and
// import LockedPreviewShell directly.

protocol SpacePurchasePresenting {
    /// Called when the user triggers unlock. Presenter sets `isPresented = true`.
    var onUnlock: () -> Void { get }
}

// MARK: - Purchase Sheet

struct SpacesPurchaseSheet: View {

    let space: AmenSpaceExtended
    let userId: String
    @Binding var isPresented: Bool

    @StateObject private var service = SpacesPurchaseService()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        AmenLiquidGlassBottomSheet(
            title: space.title,
            subtitle: nil,
            aiDisclosure: nil,
            content: {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.bottom, 20)

                    priceSection
                        .padding(.bottom, 16)

                    benefitsSection
                        .padding(.bottom, 20)

                    if let errorMessage = service.purchaseError {
                        errorView(message: errorMessage)
                            .padding(.bottom, 12)
                    }
                }
            },
            footer: {
                ctaButton
                    .padding(.bottom, 4)
            }
        )
        .onAppear {
            service.startObservingEntitlement(userId: userId, spaceId: space.id ?? "")
        }
        .onDisappear {
            service.stopObserving()
        }
        .onChange(of: service.entitlement) { _, newValue in
            if newValue?.status == .active {
                isPresented = false
            }
        }
    }

    // MARK: - Header Section
    // Hero-profile style: avatar left, title + community name right/below.

    private var headerSection: some View {
        HStack(spacing: 14) {
            avatarView
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(space.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                Text("Community Space")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(space.title), Community Space")
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = space.avatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                case .failure, .empty:
                    fallbackAvatar
                @unknown default:
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                }
                .overlay {
                    Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                }
                .frame(width: 60, height: 60)

            Image(systemName: space.type.systemImageName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.amenGold)
        }
    }

    // MARK: - Price Section

    private var priceSection: some View {
        VStack(spacing: 6) {
            if let config = space.priceConfig {
                Text(SpacesFeeCalculator.priceLabel(config: config))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityLabel("Price: \(SpacesFeeCalculator.priceLabel(config: config))")

                Text(SpacesFeeCalculator.intervalDescription(config: config))
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                Text(SpacesFeeCalculator.payoutLabel(amountCents: config.amountCents))
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.top, 2)
            } else {
                Text("Free")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(Color(.systemBackground))
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                            style: .continuous
                        )
                        .fill(Color.white.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                            style: .continuous
                        )
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                    }
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you get")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityAddTraits(.isHeader)

            benefitRow(icon: "lock.open.fill", label: "Full access to all threads and content")
            benefitRow(icon: "message.fill",   label: "Unlimited messages")

            if space.type == .bibleStudy {
                benefitRow(icon: "books.vertical.fill", label: "Study blocks and materials")
            }
        }
        .padding(.horizontal, 4)
    }

    private func benefitRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 4)
        .accessibilityLabel("Error: \(message)")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        AmenLiquidGlassPillButton(
            title: "Get Access",
            systemImage: "lock.open.fill",
            isLoading: service.isPurchasing,
            isDisabled: service.isPurchasing || space.priceConfig == nil,
            hint: "Double-tap to purchase access"
        ) {
            guard let spaceId = space.id, !spaceId.isEmpty else { return }
            _ = spaceId // suppress unused warning; spaceId validated inside purchaseSpace
            Task {
                do {
                    try await service.purchaseSpace(space, userId: userId)
                } catch {
                    // Error is set on service.purchaseError; UI reflects it automatically.
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

import SwiftUI

// MARK: - ContextualExperienceFeedBanner

/// Top-of-feed contextual banner. Shown when ExperienceResolverService returns an active experience.
struct ContextualExperienceFeedBanner: View {

    let resolved: ResolvedExperience
    let onTap: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var appeared = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mainRow
            if !resolved.secondaryExperiences.isEmpty {
                moreChip
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bannerBackground)
        .overlay(bannerStroke)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.32, dampingFraction: 0.78)
            ) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(resolved.activeBannerTitle ?? ""). \(resolved.activeBannerSubtitle ?? "")"
        )
        .accessibilityHint("Tap to open experience details")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: 10) {
            accentLine

            VStack(alignment: .leading, spacing: 2) {
                Text(resolved.activeBannerTitle ?? "")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text(resolved.activeBannerSubtitle ?? "")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            viewButton
            dismissButton
        }
    }

    // MARK: - Accent line

    private var accentLine: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(accentColor)
            .frame(width: 3, height: 40)
            .accessibilityHidden(true)
    }

    // MARK: - View button

    private var viewButton: some View {
        Button {
            HapticManager.impact(style: .light)
            onTap()
        } label: {
            HStack(spacing: 3) {
                Text("View")
                    .font(AMENFont.semiBold(12))
                Image(systemName: "arrow.right")
                    .imageScale(.small)
            }
            .foregroundStyle(accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View experience")
        .accessibilityHint("Opens the experience detail screen")
    }

    // MARK: - Dismiss button

    private var dismissButton: some View {
        Button {
            HapticManager.impact(style: .light)
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .imageScale(.small)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss banner")
        .accessibilityHint("Hides this experience banner")
    }

    // MARK: - More chip

    private var moreChip: some View {
        Text("+\(resolved.secondaryExperiences.count) more happening now")
            .font(AMENFont.regular(11))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.surfaceChip)
            )
            .padding(.leading, 13)
            .accessibilityLabel(
                "\(resolved.secondaryExperiences.count) more experiences happening now"
            )
    }

    // MARK: - Background

    @ViewBuilder
    private var bannerBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.3))
            }
        }
    }

    private var bannerStroke: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
    }

    // MARK: - Accent color

    private var accentColor: Color {
        // themeTokens is optional; fall back to amenGold when absent
        guard let hex = resolved.themeTokens?.accentColorHex else {
            return Color(hex: "#C9A84C")
        }
        return Color(hex: hex)
    }
}

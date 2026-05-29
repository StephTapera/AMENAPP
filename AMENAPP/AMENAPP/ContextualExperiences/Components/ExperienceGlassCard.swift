import SwiftUI

// MARK: - ContextualExperienceCard

/// Liquid Glass card for displaying a ContextualExperience in lists and discovery.
struct ContextualExperienceCard: View {

    let experience: ContextualExperience
    let userRole: OrgMemberRole?
    let onJoin: () -> Void
    let onViewDetail: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeHeader
                .padding(.horizontal, 14)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(experience.title)
                    .font(AMENFont.bold(16))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text(experience.description)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer(minLength: 10)

            bottomBar
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(minHeight: 140)
        .background(cardBackground)
        .overlay(cardStroke)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            HapticManager.impact(style: .light)
            onViewDetail()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap to view details")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Type header

    private var typeHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: experience.type.icon)
                .imageScale(.small)
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            Text(experience.type.displayName)
                .font(AMENFont.semiBold(11))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(AmenTheme.Colors.surfaceChip)
                )

            Spacer(minLength: 0)

            statusBadge
        }
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        if experience.isKillSwitched {
            badgePill(label: "Paused", color: AmenTheme.Colors.statusWarning)
        } else {
            switch experience.status {
            case .published where experience.isActive:
                badgePill(label: "LIVE", color: AmenTheme.Colors.statusSuccess)
            case .published:
                badgePill(label: "UPCOMING", color: AmenTheme.Colors.statusInfo)
            case .draft:
                badgePill(label: "DRAFT", color: AmenTheme.Colors.textSecondary)
            case .archived, .deleted:
                badgePill(label: "ENDED", color: AmenTheme.Colors.textSecondary)
            }
        }
    }

    private func badgePill(label: String, color: Color) -> some View {
        Text(label)
            .font(AMENFont.bold(9))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.14))
            )
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            participantChip
            if experience.daysRemaining > 0 && experience.isActive {
                daysRemainingChip
                    .padding(.leading, 6)
            }
            Spacer(minLength: 0)
            actionButton
        }
    }

    private var participantChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .imageScale(.small)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("\(experience.participantCount)")
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
    }

    private var daysRemainingChip: some View {
        Text("\(experience.daysRemaining)d left")
            .font(AMENFont.regular(11))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(AmenTheme.Colors.surfaceChip)
            )
    }

    @ViewBuilder
    private var actionButton: some View {
        let isEnded = experience.status == .archived
            || experience.status == .deleted
            || experience.isKillSwitched

        if isEnded {
            Button {
                HapticManager.impact(style: .light)
                onViewDetail()
            } label: {
                Text("View")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AmenTheme.Colors.surfaceChip)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View experience")
            .disabled(true)
        } else {
            Button {
                HapticManager.impact(style: .light)
                onJoin()
            } label: {
                Text("Join")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AmenTheme.Colors.buttonPrimary)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Join \(experience.title)")
            .accessibilityHint("Joins this experience")
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var cardBackground: some View {
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

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = [experience.title, experience.type.displayName]
        if experience.isKillSwitched {
            parts.append("Paused")
        } else if experience.isActive {
            parts.append("Live, \(experience.daysRemaining) days remaining")
        }
        parts.append("\(experience.participantCount) participants")
        return parts.joined(separator: ". ")
    }
}

// MARK: - ContextualExperienceCard Skeleton

struct ContextualExperienceCardSkeleton: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                skeletonBar(width: 80, height: 14)
                Spacer()
                skeletonBar(width: 40, height: 14)
            }
            skeletonBar(width: 160, height: 18)
            skeletonBar(width: 220, height: 13)
            skeletonBar(width: 180, height: 13)
            HStack {
                skeletonBar(width: 50, height: 12)
                Spacer()
                skeletonBar(width: 60, height: 28)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
        )
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(width: width, height: height)
    }
}

// Color(hex:) is provided project-wide by Color+Hex.swift — no local extension needed.

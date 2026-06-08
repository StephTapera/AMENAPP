// AmenVerifiedHostBadgeView.swift
// AMEN Connect + Spaces — Verified Host Badge
// Built 2026-06-02

import SwiftUI

// MARK: - Badge helpers

private extension AmenHostBadgeVariant {
    var displayText: String {
        switch self {
        case .individual:    return "Verified Creator"
        case .church:        return "Verified Church"
        case .organization:  return "Verified Organization"
        case .nonprofit:     return "Verified Nonprofit"
        }
    }

    var explanation: String {
        switch self {
        case .individual:
            return "This creator has verified their identity with AMEN."
        case .church:
            return "This church has verified its legal registration and EIN with AMEN."
        case .organization:
            return "This organization has verified its legal registration with AMEN."
        case .nonprofit:
            return "This nonprofit has verified its 501(c)(3) status and EIN with AMEN."
        }
    }
}

private extension AmenHostVerificationStatus {
    var badgeTint: Color {
        switch self {
        case .verified:
            return Color(hex: "D9A441")
        case .suspended:
            return Color.red
        case .pending, .unverified:
            return Color.white.opacity(0.35)
        }
    }

    var displayLabel: String {
        switch self {
        case .verified:   return ""    // uses badgeVariant text
        case .pending:    return "Pending"
        case .unverified: return "Unverified"
        case .suspended:  return "Suspended"
        }
    }
}

// MARK: - Date formatter

private let badgeDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

// MARK: - Popover content

private struct BadgePopoverView: View {
    let profile: AmenVerifiedHostProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(badgeTitle)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(statusSubtitle)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }
            }

            Text(profile.badgeVariant.explanation)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let verifiedAt = profile.verifiedAt {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.systemScaled(12))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("Verified \(badgeDateFormatter.string(from: verifiedAt))")
                        .font(.systemScaled(12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private var badgeTitle: String {
        switch profile.verificationStatus {
        case .verified:   return profile.badgeVariant.displayText
        case .suspended:  return "Account Suspended"
        case .pending:    return "Verification Pending"
        case .unverified: return "Not Verified"
        }
    }

    private var statusSubtitle: String {
        switch profile.verificationStatus {
        case .verified:   return profile.displayName
        case .suspended:  return "This host has been suspended."
        case .pending:    return "Review is in progress."
        case .unverified: return "Identity not confirmed."
        }
    }

    private var statusIcon: some View {
        Group {
            switch profile.verificationStatus {
            case .verified:
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color(hex: "D9A441"))
            case .suspended:
                Image(systemName: "xmark.seal.fill")
                    .foregroundStyle(Color.red)
            case .pending:
                Image(systemName: "clock.badge")
                    .foregroundStyle(Color.white.opacity(0.45))
            case .unverified:
                Image(systemName: "seal")
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .font(.systemScaled(22))
        .accessibilityHidden(true)
    }
}

// MARK: - Badge view

struct AmenVerifiedHostBadgeView: View {
    let profile: AmenVerifiedHostProfile

    @State private var showPopover: Bool = false

    private var tint: Color { profile.verificationStatus.badgeTint }

    private var labelText: String {
        switch profile.verificationStatus {
        case .verified:   return profile.badgeVariant.displayText
        case .suspended:  return "Suspended"
        case .pending:    return "Pending"
        case .unverified: return "Unverified"
        }
    }

    private var iconName: String {
        switch profile.verificationStatus {
        case .verified:   return "checkmark.seal.fill"
        case .suspended:  return "xmark.seal.fill"
        case .pending:    return "clock"
        case .unverified: return "seal"
        }
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(labelText)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: 28)
            .background {
                Capsule().fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap for badge details")
        .popover(isPresented: $showPopover) {
            BadgePopoverView(profile: profile)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var accessibilityLabel: String {
        switch profile.verificationStatus {
        case .verified:
            return "\(profile.badgeVariant.displayText): \(profile.displayName)"
        case .suspended:
            return "Suspended host: \(profile.displayName)"
        case .pending:
            return "Verification pending for \(profile.displayName)"
        case .unverified:
            return "Unverified host: \(profile.displayName)"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AmenVerifiedHostBadgeView(profile: AmenVerifiedHostProfile(
            id: "s1", hostType: .church,
            verificationStatus: .verified,
            displayName: "Hillside Community Church",
            ein: "12-3456789",
            verifiedAt: Date().addingTimeInterval(-86400 * 30),
            badgeVariant: .church
        ))

        AmenVerifiedHostBadgeView(profile: AmenVerifiedHostProfile(
            id: "s2", hostType: .creator,
            verificationStatus: .verified,
            displayName: "Pastor James",
            ein: nil,
            verifiedAt: Date().addingTimeInterval(-86400 * 60),
            badgeVariant: .individual
        ))

        AmenVerifiedHostBadgeView(profile: AmenVerifiedHostProfile(
            id: "s3", hostType: .nonprofit,
            verificationStatus: .pending,
            displayName: "Kingdom Builders Foundation",
            ein: nil, verifiedAt: nil,
            badgeVariant: .nonprofit
        ))

        AmenVerifiedHostBadgeView(profile: AmenVerifiedHostProfile(
            id: "s4", hostType: .creator,
            verificationStatus: .suspended,
            displayName: "Removed Account",
            ein: nil, verifiedAt: nil,
            badgeVariant: .individual
        ))
    }
    .padding()
    .background(Color(hex: "0D0D0D"))
    .preferredColorScheme(.dark)
}

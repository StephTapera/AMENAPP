// RightsMonetizationService.swift
// AMENAPP/MusicContentLayer
//
// Rights enforcement, access policy checks, and monetization display helpers.

import SwiftUI

// MARK: - Access Result Types

enum ContentAccessResult: Sendable {
    case granted
    case denied(reason: ContentAccessDeniedReason)
}

enum ContentAccessDeniedReason: String, Sendable {
    case paidRequired
    case membershipRequired
    case childRestricted
    case pendingModeration
    case blocked
    case privateContent
    case adminOnly
    case regionRestricted

    var shortLabel: String {
        switch self {
        case .paidRequired:         return "Paid content"
        case .membershipRequired:   return "Members only"
        case .childRestricted:      return "Age restricted"
        case .pendingModeration:    return "Under review"
        case .blocked:              return "Blocked"
        case .privateContent:       return "Private"
        case .adminOnly:            return "Admins only"
        case .regionRestricted:     return "Not available in your region"
        }
    }

    var icon: String {
        switch self {
        case .paidRequired:         return "dollarsign.circle.fill"
        case .membershipRequired:   return "star.circle.fill"
        case .childRestricted:      return "shield.fill"
        case .pendingModeration:    return "clock.fill"
        case .blocked:              return "slash.circle.fill"
        case .privateContent:       return "lock.fill"
        case .adminOnly:            return "person.badge.shield.checkmark.fill"
        case .regionRestricted:     return "globe"
        }
    }
}

// MARK: - Rights Check Input

struct RightsCheckInput: Sendable {
    let contentID: String
    let rightsPolicy: String       // matches RightsPolicy raw values
    let visibilityPolicy: String
    let moderationStatus: String
    let isChildAccount: Bool
    let hasActiveMembership: Bool
    let hasPaidAccess: Bool
    let isAdmin: Bool
}

// MARK: - Policy Constants

private enum RightsPolicy: String {
    case free
    case paid
    case membersOnly
    case adminOnly
    case childRestricted
    case regionRestricted
}

private enum VisibilityPolicy: String {
    case `public`
    case `private`
    case membersOnly
    case communityOnly
}

private enum ModerationStatus: String {
    case approved
    case pendingReview
    case blocked
    case removed
}

// MARK: - Rights Monetization Service

// @unchecked Sendable is safe: RightsMonetizationService has no mutable stored state.
final class RightsMonetizationService: @unchecked Sendable {

    // MARK: - Access Check

    func checkAccess(_ input: RightsCheckInput) -> ContentAccessResult {
        let moderation = ModerationStatus(rawValue: input.moderationStatus) ?? .approved
        let rights = RightsPolicy(rawValue: input.rightsPolicy) ?? .free
        let visibility = VisibilityPolicy(rawValue: input.visibilityPolicy) ?? .public

        // 1. Blocked content — always denied, no exceptions
        if moderation == .blocked || moderation == .removed {
            return .denied(reason: .blocked)
        }

        // 2. Pending review — denied unless admin
        if moderation == .pendingReview, !input.isAdmin {
            return .denied(reason: .pendingModeration)
        }

        // 3. Admin-only rights policy — denied unless admin
        if rights == .adminOnly, !input.isAdmin {
            return .denied(reason: .adminOnly)
        }

        // 4. Private visibility — denied unless admin (admin as creator proxy)
        if visibility == .private, !input.isAdmin {
            return .denied(reason: .privateContent)
        }

        // 5. Members-only visibility — denied without membership
        if visibility == .membersOnly, !input.hasActiveMembership {
            return .denied(reason: .membershipRequired)
        }

        // 6. Paid rights policy — denied without paid access
        if rights == .paid, !input.hasPaidAccess {
            return .denied(reason: .paidRequired)
        }

        // 7. Members-only rights policy — denied without membership
        if rights == .membersOnly, !input.hasActiveMembership {
            return .denied(reason: .membershipRequired)
        }

        // 8. Child-restricted content — denied for child accounts
        if rights == .childRestricted, input.isChildAccount {
            return .denied(reason: .childRestricted)
        }

        // 9. Region-restricted content
        if rights == .regionRestricted {
            return .denied(reason: .regionRestricted)
        }

        return .granted
    }

    // MARK: - Visibility Badge

    func visibilityBadge(for policy: String) -> (label: String, color: Color, icon: String) {
        switch VisibilityPolicy(rawValue: policy) {
        case .public:
            return ("Public", Color.green, "globe")
        case .private:
            return ("Private", Color.secondary, "lock.fill")
        case .membersOnly:
            return ("Members", Color.purple, "star.fill")
        case .communityOnly:
            return ("Community", Color.blue, "person.3.fill")
        case .none:
            return ("Public", Color.green, "globe")
        }
    }

    // MARK: - Monetization Label

    func monetizationLabel(for policy: String) -> String {
        switch RightsPolicy(rawValue: policy) {
        case .free:             return "Free"
        case .paid:             return "Paid"
        case .membersOnly:      return "Members Only"
        case .adminOnly:        return "Admin Only"
        case .childRestricted:  return "Age Restricted"
        case .regionRestricted: return "Region Restricted"
        case .none:             return "Free"
        }
    }
}

// MARK: - Monetization Status Pill

struct MonetizationStatusPill: View {
    let policy: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let service = RightsMonetizationService()

    var body: some View {
        let badge = service.visibilityBadge(for: policy)
        HStack(spacing: 4) {
            Image(systemName: badge.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(badge.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(badge.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if reduceTransparency {
                Capsule()
                    .fill(badge.color.opacity(0.12))
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(badge.color.opacity(0.10))
                    .overlay(
                        Capsule()
                            .stroke(badge.color.opacity(0.25), lineWidth: 1)
                    )
            }
        }
        .shadow(color: badge.color.opacity(0.08), radius: 3, y: 1)
        .accessibilityLabel("Visibility: \(badge.label)")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Resource Access Badge

struct ResourceAccessBadge: View {
    let accessResult: ContentAccessResult

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch accessResult {
        case .granted:
            EmptyView()

        case .denied(let reason):
            HStack(spacing: 5) {
                Image(systemName: reason.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(reason.shortLabel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if reduceTransparency {
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.white.opacity(0.04))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            .accessibilityLabel("Access restricted: \(reason.shortLabel)")
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Preview

#Preview("Rights & Monetization") {
    let service = RightsMonetizationService()

    let testCases: [(label: String, input: RightsCheckInput)] = [
        ("Free + Public", RightsCheckInput(
            contentID: "c1", rightsPolicy: "free", visibilityPolicy: "public",
            moderationStatus: "approved", isChildAccount: false,
            hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Paid – no access", RightsCheckInput(
            contentID: "c2", rightsPolicy: "paid", visibilityPolicy: "public",
            moderationStatus: "approved", isChildAccount: false,
            hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Members only – no membership", RightsCheckInput(
            contentID: "c3", rightsPolicy: "membersOnly", visibilityPolicy: "membersOnly",
            moderationStatus: "approved", isChildAccount: false,
            hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Pending moderation", RightsCheckInput(
            contentID: "c4", rightsPolicy: "free", visibilityPolicy: "public",
            moderationStatus: "pendingReview", isChildAccount: false,
            hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Blocked", RightsCheckInput(
            contentID: "c5", rightsPolicy: "free", visibilityPolicy: "public",
            moderationStatus: "blocked", isChildAccount: false,
            hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Child restricted", RightsCheckInput(
            contentID: "c6", rightsPolicy: "childRestricted", visibilityPolicy: "public",
            moderationStatus: "approved", isChildAccount: true,
            hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Admin only – is admin", RightsCheckInput(
            contentID: "c7", rightsPolicy: "adminOnly", visibilityPolicy: "public",
            moderationStatus: "approved", isChildAccount: false,
            hasActiveMembership: false, hasPaidAccess: false, isAdmin: true)),
    ]

    return ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("Monetization Pills")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 8) {
                MonetizationStatusPill(policy: "public")
                MonetizationStatusPill(policy: "private")
                MonetizationStatusPill(policy: "membersOnly")
                MonetizationStatusPill(policy: "communityOnly")
            }
            .padding(.horizontal)

            Divider()

            Text("Access Badge Examples")
                .font(.headline)
                .padding(.horizontal)

            ForEach(testCases, id: \.label) { testCase in
                let result = service.checkAccess(testCase.input)
                HStack {
                    Text(testCase.label)
                        .font(.subheadline)
                    Spacer()
                    ResourceAccessBadge(accessResult: result)
                    if case .granted = result {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Access granted")
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 20)
    }
    .background(Color(.systemGroupedBackground))
}

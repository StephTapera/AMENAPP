// AmenTrustBadgeComponents.swift
// AMENAPP — Verification & Trust System
//
// All six verification badge types for the Amen platform.
// Design: Liquid Glass pill with per-type color accent.
// Accessibility: reduceTransparency + reduceMotion + VoiceOver labels.
// Tap-to-explain: each badge type shows a sheet with honest plain-language copy.

import SwiftUI

// MARK: - Private Sheet Wrapper

private struct BadgeExplanationSheet: View {
    let title: String
    let explanation: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(explanation)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - AmenTrustBadgeView
// Base, most-prominent badge. Shows icon + label in a glass pill.
// Tapping opens an explanation sheet with honest copy.

struct AmenTrustBadgeView: View {
    let type: VerificationBadgeType
    var subtitle: String? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var isPressed = false
    @State private var showExplanation = false

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(badgeBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(accentColor.opacity(contrast == .increased ? 0.6 : 0.25), lineWidth: contrast == .increased ? 1.5 : 0.75)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
            .scaleEffect((!reduceMotion && isPressed) ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(type.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to learn what this badge means")
        .sheet(isPresented: $showExplanation) {
            BadgeExplanationSheet(
                title: type.displayName,
                explanation: type.explanationCopy
            )
        }
    }

    private var accentColor: Color {
        switch type {
        case .identityVerified:     return .indigo
        case .organizationVerified: return .blue
        case .creatorVerified:      return .orange
        case .roleVerified:         return .green
        case .emailVerified:        return Color(.systemGray)
        case .phoneVerified:        return Color(.systemGray)
        case .safetyActive:         return .teal
        }
    }

    @ViewBuilder
    private var badgeBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .background(
                    Capsule().fill(accentColor.opacity(0.08))
                )
        }
    }
}

// MARK: - AmenVerificationPill
// Compact inline version. When compact=true shows icon-only with accessibility label.

struct AmenVerificationPill: View {
    let type: VerificationBadgeType
    var compact: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var showExplanation = false

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            HStack(spacing: compact ? 0 : 5) {
                Image(systemName: type.systemImage)
                    .font(.system(size: compact ? 12 : 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)

                if !compact {
                    Text(type.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 6 : 5)
            .frame(minWidth: 44, minHeight: 44)
            .background(pillBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(accentColor.opacity(0.2), lineWidth: 0.75)
            )
            .scaleEffect((!reduceMotion && isPressed) ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(type.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to learn what this verification means")
        .sheet(isPresented: $showExplanation) {
            BadgeExplanationSheet(
                title: type.displayName,
                explanation: type.explanationCopy
            )
        }
    }

    private var accentColor: Color {
        switch type {
        case .identityVerified:     return .indigo
        case .organizationVerified: return .blue
        case .creatorVerified:      return .orange
        case .roleVerified:         return .green
        case .emailVerified:        return Color(.systemGray)
        case .phoneVerified:        return Color(.systemGray)
        case .safetyActive:         return .teal
        }
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .background(Rectangle().fill(accentColor.opacity(0.06)))
        }
    }
}

// MARK: - AmenPublicTrustBadgeRow
// Compact public surface row. Uses only backend-controlled public summaries.

struct AmenPublicTrustBadgeRow: View {
    let summary: AmenPublicVerificationSummary
    var compact: Bool = true
    var limit: Int = 3

    private var badges: [VerificationBadgeType] {
        var resolved = summary.visibleBadges.compactMap(VerificationBadgeType.init(rawValue:))
        if summary.identityVerified && !resolved.contains(.identityVerified) {
            resolved.append(.identityVerified)
        }
        if summary.creatorVerified && !resolved.contains(.creatorVerified) {
            resolved.append(.creatorVerified)
        }
        if summary.emailVerified && !resolved.contains(.emailVerified) {
            resolved.append(.emailVerified)
        }
        if summary.phoneVerified && !resolved.contains(.phoneVerified) {
            resolved.append(.phoneVerified)
        }
        if summary.safetyStanding == .active && !resolved.contains(.safetyActive) {
            resolved.append(.safetyActive)
        }
        return Array(resolved.prefix(limit))
    }

    var body: some View {
        if AMENFeatureFlags.shared.publicTrustBadgesEnabled && !badges.isEmpty {
            HStack(spacing: 6) {
                ForEach(badges) { badge in
                    AmenVerificationPill(type: badge, compact: compact)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - AmenRoleBadge
// Shows a verified role within a specific organization and scope.
// Expired/revoked roles render in a muted style with an "Expired" label.

struct AmenRoleBadge: View {
    let role: AmenRoleVerification

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var showExplanation = false

    private var isActive: Bool { role.isActive }

    private var explanationText: String {
        let orgName = role.organizationName ?? role.organizationId
        return "This role was verified by \(orgName). It applies only in \(role.scope)."
    }

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? .green : .secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(role.role)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(isActive ? .primary : .secondary)

                        if !isActive {
                            Text("Expired")
                                .font(.custom("OpenSans-SemiBold", size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color(.systemGray5))
                                )
                        }
                    }

                    Text(role.organizationName ?? role.organizationId)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("Applies in \(role.scope)")
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(roleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isActive ? Color.green.opacity(0.25) : Color(.systemGray4),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
            .scaleEffect((!reduceMotion && isPressed) ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(
            isActive
                ? "Verified role: \(role.role) at \(role.organizationName ?? role.organizationId), applies in \(role.scope)"
                : "Expired verified role: \(role.role) at \(role.organizationName ?? role.organizationId)"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to learn about this role verification")
        .sheet(isPresented: $showExplanation) {
            BadgeExplanationSheet(
                title: "\(role.role) — \(role.organizationName ?? role.organizationId)",
                explanation: explanationText
            )
        }
    }

    @ViewBuilder
    private var roleBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }
}

// MARK: - AmenOrganizationBadge
// Shows a verified organization name + optional domain.

struct AmenOrganizationBadge: View {
    let summary: AmenOrganizationVerificationSummary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var showExplanation = false

    private var explanationText: String {
        let name = summary.verifiedName ?? "this organization"
        var text = "Amen verified this organization represents \(name)."
        if let domain = summary.verifiedDomain {
            text += " Domain: \(domain)."
        }
        return text
    }

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.verifiedName ?? "Verified Organization")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let domain = summary.verifiedDomain {
                        Text(domain)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(orgBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.blue.opacity(0.25), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
            .scaleEffect((!reduceMotion && isPressed) ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Verified organization: \(summary.verifiedName ?? "Verified Organization")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to learn about this organization verification")
        .sheet(isPresented: $showExplanation) {
            BadgeExplanationSheet(
                title: "Verified Organization",
                explanation: explanationText
            )
        }
    }

    @ViewBuilder
    private var orgBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .background(Capsule().fill(Color.blue.opacity(0.06)))
        }
    }
}

// MARK: - AmenCreatorBadge
// Shows only when verified=true. Returns EmptyView otherwise.

struct AmenCreatorBadge: View {
    let verified: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var showExplanation = false

    private let explanationText = "Amen verified this person meets creator community standards. This includes content quality, community engagement, and alignment with Amen's community covenant."

    var body: some View {
        if !verified {
            EmptyView()
        } else {
            Button {
                showExplanation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "star.bubble.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    Text("Creator verified")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 44, minHeight: 44)
                .background(creatorBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
                .scaleEffect((!reduceMotion && isPressed) ? 0.97 : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .accessibilityLabel("Creator verified")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double-tap to learn about creator verification")
            .sheet(isPresented: $showExplanation) {
                BadgeExplanationSheet(
                    title: "Creator Verified",
                    explanation: explanationText
                )
            }
        }
    }

    @ViewBuilder
    private var creatorBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .background(Capsule().fill(Color.orange.opacity(0.08)))
        }
    }
}

// MARK: - AmenSafetyStandingBadge
// Shown only when standing is NOT .active.
// Communicates limited visibility without leaking moderation details.

struct AmenSafetyStandingBadge: View {
    let standing: AmenSafetyStanding

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var showExplanation = false

    var body: some View {
        if standing == .active {
            EmptyView()
        } else {
            Button {
                showExplanation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(badgeColor)
                        .accessibilityHidden(true)

                    Text(badgeLabel)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(badgeColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 44, minHeight: 44)
                .background(standingBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(badgeColor.opacity(0.35), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
                .scaleEffect((!reduceMotion && isPressed) ? 0.97 : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .accessibilityLabel(accessibilityDescription)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double-tap to learn what this means")
            .sheet(isPresented: $showExplanation) {
                BadgeExplanationSheet(
                    title: badgeLabel,
                    explanation: explanationCopy
                )
            }
        }
    }

    private var badgeIcon: String {
        switch standing {
        case .limited:     return "exclamationmark.triangle.fill"
        case .underReview: return "clock.badge.exclamationmark.fill"
        case .suspended:   return "minus.circle.fill"
        case .active:      return "checkmark.circle.fill"
        }
    }

    private var badgeLabel: String {
        switch standing {
        case .limited:     return "Limited"
        case .underReview: return "Under Review"
        case .suspended:   return "Suspended"
        case .active:      return "Active"
        }
    }

    private var badgeColor: Color {
        switch standing {
        case .limited:     return .orange
        case .underReview: return .orange
        case .suspended:   return .red
        case .active:      return .green
        }
    }

    private var accessibilityDescription: String {
        switch standing {
        case .limited:     return "Account visibility limited"
        case .underReview: return "Account under review"
        case .suspended:   return "Account suspended"
        case .active:      return "Account active"
        }
    }

    private var explanationCopy: String {
        switch standing {
        case .limited:
            return "This account's visibility may be limited. Some content from this account may not appear in discovery or recommendations."
        case .underReview:
            return "This account is currently under review. Visibility may be limited while the review is in progress."
        case .suspended:
            return "This account has been suspended. Its content is not visible to other users."
        case .active:
            return "This account is in good standing."
        }
    }

    @ViewBuilder
    private var standingBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .background(Capsule().fill(badgeColor.opacity(0.08)))
        }
    }
}

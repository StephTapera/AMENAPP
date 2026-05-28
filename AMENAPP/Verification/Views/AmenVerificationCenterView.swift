// AmenVerificationCenterView.swift
// AMENAPP — Verification & Trust System
//
// Main verification center screen. Gated by AMENFeatureFlags.shared.verificationCenterEnabled.
// Shows all verification sections as Liquid Glass cards.
// Listens for real-time updates from AmenVerificationService.

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - AmenVerificationCenterView

struct AmenVerificationCenterView: View {

    @ObservedObject private var service = AmenVerificationService.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingFlow: AmenVerificationFlowCoordinator.VerificationType? = nil

    var body: some View {
        Group {
            if flags.verificationCenterEnabled {
                centerContent
            } else {
                featureUnavailableView
            }
        }
        .onAppear {
            AmenVerificationAnalytics.verificationCenterOpened()
        }
    }

    // MARK: - Main Content

    private var centerContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    subtitleHeader

                    // Section 1: Email — always shown
                    emailSection

                    // Section 2: Phone — phone OTP is always available
                    phoneSection

                    // Section 3: Identity (feature-gated)
                    if flags.identityVerificationEnabled {
                        identitySection
                    }

                    // Section 4: Organization (feature-gated)
                    if flags.organizationVerificationEnabled {
                        organizationSection
                    }

                    // Section 5: Role Badges (feature-gated)
                    if flags.roleVerificationEnabled {
                        roleSection
                    }

                    // Section 6: Creator (feature-gated)
                    if flags.creatorVerificationEnabled {
                        creatorSection
                    }

                    // Section 7: Safety Standing — always shown, read-only
                    safetyStandingSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $showingFlow) { flowType in
                AmenVerificationFlowCoordinator(type: flowType)
            }
        }
    }

    // MARK: - Subtitle Header

    private var subtitleHeader: some View {
        Text("Manage your verification status.")
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    // MARK: - Feature Unavailable

    private var featureUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Verification Center")
                .font(.custom("OpenSans-SemiBold", size: 20))
            Text("This feature is not available yet. Check back soon.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Helpers

    private func latestRequest(for type: AmenVerificationRequestType) -> AmenVerificationRequest? {
        service.requests
            .filter { $0.type == type }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .first
    }

    // MARK: - Email Section

    private var emailSection: some View {
        let isVerified = service.summary.emailVerified
        let request = latestRequest(for: .identity) // email uses Firebase Auth, no dedicated request type
        return VerificationSectionCard(
            icon: "envelope.badge.shield.half.filled",
            title: "Email Verified",
            iconColor: Color(.systemGray),
            isVerified: isVerified,
            pendingRequest: request,
            ctaLabel: isVerified ? "View Status" : "Verify Email",
            onCTA: { showingFlow = .email }
        )
    }

    // MARK: - Phone Section

    private var phoneSection: some View {
        let isVerified = service.summary.phoneVerified
        return VerificationSectionCard(
            icon: "iphone.badge.play",
            title: "Phone Verified",
            iconColor: Color(.systemGray),
            isVerified: isVerified,
            pendingRequest: nil,
            ctaLabel: isVerified ? "Reverify" : "Verify Phone",
            onCTA: { showingFlow = .phone }
        )
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        let isVerified = service.summary.identityVerified
        let request = latestRequest(for: .identity)
        return VerificationSectionCard(
            icon: "person.text.rectangle.fill",
            title: "Identity Verified",
            iconColor: .indigo,
            isVerified: isVerified,
            pendingRequest: request,
            ctaLabel: isVerified ? "Reverify" : (request?.status == .pending ? "Continue" : "Start Verification"),
            onCTA: { showingFlow = isVerified ? .reverify : .identity }
        )
    }

    // MARK: - Organization Section

    private var organizationSection: some View {
        let request = latestRequest(for: .organization)
        let isVerified = request?.status == .approved
        return VerificationSectionCard(
            icon: "building.2.crop.circle.fill",
            title: "Organization",
            iconColor: .blue,
            isVerified: isVerified,
            pendingRequest: request,
            ctaLabel: isVerified ? "View Status" : (request?.status == .pending ? "Under Review" : "Start Verification"),
            onCTA: { showingFlow = .organization }
        )
    }

    // MARK: - Role Badges Section

    private var roleSection: some View {
        let request = latestRequest(for: .role)
        let activeRoles = service.roles.filter { $0.isActive }
        return VerificationSectionCard(
            icon: "person.badge.shield.checkmark.fill",
            title: "Role Badges",
            iconColor: .green,
            isVerified: !activeRoles.isEmpty,
            pendingRequest: request,
            ctaLabel: "Add Role",
            supplementaryContent: {
                AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(activeRoles) { role in
                            AmenRoleBadge(role: role)
                        }
                    }
                )
            },
            onCTA: { showingFlow = .role }
        )
    }

    // MARK: - Creator Section

    private var creatorSection: some View {
        let isVerified = service.summary.creatorVerified
        let request = latestRequest(for: .creator)
        return VerificationSectionCard(
            icon: "star.bubble.fill",
            title: "Creator Verified",
            iconColor: .orange,
            isVerified: isVerified,
            pendingRequest: request,
            ctaLabel: isVerified ? "View Status" : (request?.status == .pending ? "Under Review" : "Apply"),
            onCTA: { showingFlow = .creator }
        )
    }

    // MARK: - Safety Standing Section

    private var safetyStandingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.teal)
                    .accessibilityHidden(true)

                Text("Safety Standing")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
            }

            let standing = service.summary.safetyStanding
            if standing == .active {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Your account is in good standing.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Your account is in good standing.")
            } else {
                AmenSafetyStandingBadge(standing: standing)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    // MARK: - Card Background Helper

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }
}

// MARK: - VerificationSectionCard

private struct VerificationSectionCard: View {
    let icon: String
    let title: String
    let iconColor: Color
    let isVerified: Bool
    let pendingRequest: AmenVerificationRequest?
    let ctaLabel: String
    var supplementaryContent: (() -> AnyView)? = nil
    let onCTA: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)

                Spacer()

                VerificationStatusPill(status: displayStatus)
            }

            // Expiration
            if let expiry = pendingRequest?.expiresAt,
               pendingRequest?.status == .approved {
                Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }

            // Status message
            if let request = pendingRequest {
                statusMessage(for: request)
            }

            // Supplementary content (e.g. role list)
            supplementaryContent?()

            // CTA Button — omit if pending (no double-tap action)
            let shouldShowCTA = pendingRequest?.status != .pending
            if shouldShowCTA {
                ctaButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private var displayStatus: String {
        if let request = pendingRequest {
            switch request.status {
            case .pending:       return "Under review"
            case .rejected:      return "Not approved"
            case .expired:       return "Expired"
            case .revoked:       return "Revoked"
            case .needsMoreInfo: return "More info needed"
            case .approved:      return isVerified ? "Verified" : "Not verified"
            }
        }
        return isVerified ? "Verified" : "Not verified"
    }

    @ViewBuilder
    private func statusMessage(for request: AmenVerificationRequest) -> some View {
        switch request.status {
        case .pending:
            Label("Under review — we'll notify you when complete", systemImage: "clock")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)

        case .rejected:
            let reason = request.safeUserReason ?? "Your request was not approved. You may reapply."
            Label(reason, systemImage: "xmark.circle")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.orange)

        case .expired:
            Label("Verification expired. Reverification is required.", systemImage: "calendar.badge.exclamationmark")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.orange)

        case .needsMoreInfo:
            Label("Additional information required. Check your notifications.", systemImage: "questionmark.circle")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.blue)

        default:
            EmptyView()
        }
    }

    private var ctaButton: some View {
        Button(action: onCTA) {
            Text(ctaLabel)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(iconColor))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ctaLabel)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }
}

// MARK: - VerificationStatusPill

private struct VerificationStatusPill: View {
    let status: String

    private var color: Color {
        switch status {
        case "Verified":           return .green
        case "Under review":       return .orange
        case "Expired", "Revoked": return .red
        case "Not approved":       return .orange
        default:                   return Color(.systemGray3)
        }
    }

    private var icon: String {
        switch status {
        case "Verified":           return "checkmark.circle.fill"
        case "Under review":       return "clock.fill"
        case "Expired", "Revoked": return "exclamationmark.circle.fill"
        case "Not approved":       return "xmark.circle.fill"
        default:                   return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(status)
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
        .accessibilityLabel("Status: \(status)")
    }
}

// MARK: - AmenVerificationFlowCoordinator.VerificationType: Identifiable

extension AmenVerificationFlowCoordinator.VerificationType: Identifiable {
    public var id: String { "\(self)" }
}

// MARK: - AmenVerificationService Extensions

extension AmenVerificationService {
    /// Refreshes the current user's verification status from Firestore.
    func refreshStatus() async {
        guard let uid = try? await FirebaseHelper.currentUID() else { return }
        startListening(uid: uid)
    }

    /// Calls an admin Firebase Function by name with the given params.
    func callAdminFunction(name: String, params: [String: Any]) async throws {
        let functions = Functions.functions()
        _ = try await functions.httpsCallable(name).call(params)
    }
}

// MARK: - FirebaseHelper (minimal UID helper)

private enum FirebaseHelper {
    static func currentUID() async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AmenVerificationError.notAuthenticated
        }
        return uid
    }
}

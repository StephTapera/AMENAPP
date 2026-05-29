// AmenOrgClaimSheet.swift
// AMEN App — Organization Claim Submission Sheet
//
// Bottom sheet for submitting an ownership claim on an AmenOrganizationProfile.
// Supports domain-match auto-verify path and manual review path.
// Presented from AmenOrgClaimSearchView when user taps "Claim" on a result.

import SwiftUI

struct AmenOrgClaimSheet: View {

    let organization: AmenOrganizationProfile

    @StateObject private var service = AmenOrgClaimService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var verificationEmail: String = ""
    @State private var domainMatchResult: DomainMatchResult = .unknown
    @FocusState private var emailFocused: Bool

    // MARK: - Domain match analysis

    private enum DomainMatchResult {
        case unknown
        case match      // email domain matches org website domain
        case noMatch    // email present but no domain match
        case noEmail    // field is empty
    }

    private var currentVerificationMethod: ClaimVerificationMethod {
        if domainMatchResult == .match {
            return .domainMatch(verificationEmail)
        }
        return .manualReview
    }

    private var ctaLabel: String {
        switch service.claimState {
        case .submitting:            return "Submitting…"
        case .submitted(true, _):   return "Auto-Verified!"
        case .submitted(false, _):  return "Claim Submitted"
        default:
            return domainMatchResult == .match ? "Submit & Auto-Verify" : "Submit Claim Request"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    orgSummaryCard
                    verificationSection

                    switch service.claimState {
                    case .idle, .submitting:
                        submitButton
                    case .submitted(let autoVerified, _):
                        successCard(autoVerified: autoVerified)
                    case .error(let msg):
                        errorCard(message: msg)
                        submitButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Claim Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(service.claimState == .submitted(autoVerified: false, claimId: "") ? "Done" : "Cancel") {
                        service.resetClaimState()
                        dismiss()
                    }
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                }
            }
        }
        .onDisappear { service.resetClaimState() }
    }

    // MARK: - Org Summary Card

    private var orgSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AmenTheme.Colors.amenGold.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(organization.name)
                        .font(AMENFont.semiBold(17))
                        .foregroundStyle(Color.primary)
                    Text(organization.type.displayName)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            if let city = organization.address.city, let state = organization.address.state {
                Label("\(city), \(state)", systemImage: "mappin")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            }

            if let website = organization.website, !website.isEmpty {
                Label(website, systemImage: "globe")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(glassBackground(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Verification Section

    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Verify Ownership")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(Color.primary)

            // Email option
            VStack(alignment: .leading, spacing: 8) {
                Text("Work email (optional — speeds up review)")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    TextField("yourname@orgdomain.org", text: $verificationEmail)
                        .font(AMENFont.regular(15))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                        .onChange(of: verificationEmail) { _, v in
                            evaluateDomainMatch(email: v)
                        }

                    if domainMatchResult == .match {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                            .font(.system(size: 16))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    domainMatchResult == .match
                                        ? Color.green.opacity(0.6)
                                        : Color.primary.opacity(0.10),
                                    lineWidth: 1
                                )
                        )
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: domainMatchResult)

                // Domain match feedback label
                domainMatchFeedback
            }

            // Manual review notice when no match
            if domainMatchResult == .noMatch || domainMatchResult == .noEmail {
                manualReviewNotice
            }
        }
    }

    @ViewBuilder
    private var domainMatchFeedback: some View {
        switch domainMatchResult {
        case .match:
            Label("Domain match — will auto-verify", systemImage: "bolt.fill")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(Color.green)
                .transition(.opacity)
        case .noMatch where !verificationEmail.isEmpty:
            Label("No domain match — queued for manual review", systemImage: "clock")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        default:
            EmptyView()
        }
    }

    private var manualReviewNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.badge.clock")
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.amenBlue)

            Text("Your request will be reviewed manually. We typically respond within 48 hours.")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.amenBlue.opacity(0.07))
        )
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            guard service.claimState != .submitting else { return }
            emailFocused = false
            Task { await submit() }
        } label: {
            HStack(spacing: 10) {
                if service.claimState == .submitting {
                    ProgressView()
                        .tint(Color(.systemBackground))
                        .scaleEffect(0.9)
                }
                Text(ctaLabel)
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(Color(.systemBackground))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        service.claimState == .submitting
                            ? AmenTheme.Colors.amenGold.opacity(0.6)
                            : AmenTheme.Colors.amenGold
                    )
                    .shadow(color: AmenTheme.Colors.amenGold.opacity(0.35),
                            radius: 12, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
        .disabled(service.claimState == .submitting)
        .accessibilityLabel(ctaLabel)
    }

    // MARK: - Success Card

    private func successCard(autoVerified: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: autoVerified ? "checkmark.seal.fill" : "clock.badge.checkmark.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(autoVerified ? AmenTheme.Colors.amenGold : AmenTheme.Colors.amenBlue)
                .symbolEffect(.bounce, value: true)

            VStack(spacing: 6) {
                Text(autoVerified ? "Auto-Verified!" : "Claim Submitted!")
                    .font(AMENFont.semiBold(20))
                    .foregroundStyle(Color.primary)
                Text(
                    autoVerified
                        ? "Your email matched \(organization.name)'s domain. You now manage this profile."
                        : "We'll review your claim for \(organization.name) within 48 hours. You'll get a notification when it's approved."
                )
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button("Done") {
                service.resetClaimState()
                dismiss()
            }
            .font(AMENFont.semiBold(15))
            .foregroundStyle(AmenTheme.Colors.amenGold)
        }
        .padding(20)
        .background(glassBackground(cornerRadius: 18))
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: service.claimState)
    }

    // MARK: - Error Card

    private func errorCard(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(.red)
            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.22), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Logic

    private func submit() async {
        do {
            try await service.requestClaim(
                orgId: organization.id,
                verificationMethod: currentVerificationMethod
            )
        } catch {
            // claimState is already set to .error inside service
        }
    }

    /// Checks whether the email's domain matches the org's website domain.
    /// Both are lowercased and stripped of `www.` for comparison.
    private func evaluateDomainMatch(email: String) {
        guard !email.isEmpty else {
            withAnimation { domainMatchResult = .noEmail }
            return
        }

        guard let emailDomain = extractDomain(fromEmail: email) else {
            withAnimation { domainMatchResult = .noMatch }
            return
        }

        guard let website = organization.website,
              let orgDomain = extractDomain(fromURL: website) else {
            withAnimation { domainMatchResult = .noMatch }
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            domainMatchResult = (emailDomain == orgDomain) ? .match : .noMatch
        }
    }

    private func extractDomain(fromEmail email: String) -> String? {
        let parts = email.lowercased().split(separator: "@")
        guard parts.count == 2 else { return nil }
        return normalizeDomain(String(parts[1]))
    }

    private func extractDomain(fromURL urlString: String) -> String? {
        var cleaned = urlString.lowercased()
        if !cleaned.hasPrefix("http") { cleaned = "https://" + cleaned }
        guard let url = URL(string: cleaned), let host = url.host else { return nil }
        return normalizeDomain(host)
    }

    private func normalizeDomain(_ domain: String) -> String {
        var d = domain.trimmingCharacters(in: .whitespaces)
        if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
        return d
    }

    // MARK: - Background helper

    @ViewBuilder
    private func glassBackground(cornerRadius: CGFloat) -> some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        }
    }
}

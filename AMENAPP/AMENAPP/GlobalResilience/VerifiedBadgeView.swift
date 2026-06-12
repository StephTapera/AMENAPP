// VerifiedBadgeView.swift
// AMEN — Global Resilience System
//
// Renders a tappable verification badge whose appearance is determined by the
// user's VerificationTier.  The badge CANNOT be suppressed: if tier != .none
// and tier != .unverified the badge always renders.  A tap opens a sheet with
// human-readable verification details.
//
// Usage:
//   VerifiedBadgeView(tier: profile.identityTier, verifiedAt: profile.verifiedAt)

import SwiftUI

// MARK: - VerifiedBadgeView

struct VerifiedBadgeView: View {

    let tier: VerificationTier
    var verifiedAt: Date? = nil

    @State private var showDetail: Bool = false

    // MARK: Body

    var body: some View {
        if tier == .none {
            EmptyView()
        } else {
            Button {
                showDetail = true
            } label: {
                badgeLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint("Double tap to see verification details.")
            .sheet(isPresented: $showDetail) {
                BadgeDetailSheet(tier: tier, verifiedAt: verifiedAt)
            }
        }
    }

    // MARK: Badge label

    @ViewBuilder
    private var badgeLabel: some View {
        switch tier {
        case .none:
            EmptyView()

        case .person:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.blue)
                .imageScale(.medium)

        case .leader:
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.blue)
                    .imageScale(.medium)
                Image(systemName: "cross.fill")
                    .foregroundStyle(.white)
                    .imageScale(.small)
                    .offset(x: 4, y: 4)
            }

        case .churchLinked:
            Image(systemName: "building.columns.fill")
                .foregroundStyle(.green)
                .imageScale(.medium)

        case .ministry:
            Image(systemName: "star.seal.fill")
                .foregroundStyle(.purple)
                .imageScale(.medium)

        case .charityDonation:
            Image(systemName: "heart.badge.checkmark")
                .foregroundStyle(.orange)
                .imageScale(.medium)

        case .eventHost:
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(.teal)
                .imageScale(.medium)
        }
    }

    // MARK: Accessibility

    private var accessibilityDescription: String {
        "AMEN verified: \(tier.tierDescription)"
    }
}

// MARK: - BadgeDetailSheet

private struct BadgeDetailSheet: View {

    let tier: VerificationTier
    let verifiedAt: Date?

    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Badge icon (large display size)
                Group {
                    switch tier {
                    case .none:
                        EmptyView()
                    case .person:
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                    case .leader:
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                            Image(systemName: "cross.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 18, weight: .bold))
                                .offset(x: 8, y: 8)
                        }
                    case .churchLinked:
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(.green)
                    case .ministry:
                        Image(systemName: "star.seal.fill")
                            .foregroundStyle(.purple)
                    case .charityDonation:
                        Image(systemName: "heart.badge.checkmark")
                            .foregroundStyle(.orange)
                    case .eventHost:
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundStyle(.teal)
                    }
                }
                .font(.system(size: 64))

                // Verification headline
                Text("Verified by AMEN as \(tier.tierDescription)")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Date line
                if let date = verifiedAt {
                    Text("Verified on \(Self.dateFormatter.string(from: date))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Explanatory body
                Text(tier.verificationExplanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - VerificationTier helpers

extension VerificationTier {

    /// Human-readable label used in "Verified by AMEN as {tierDescription}".
    var tierDescription: String {
        switch self {
        case .none:              return "Unverified"
        case .person:            return "Verified Person"
        case .leader:            return "Verified Faith Leader"
        case .churchLinked:      return "Church-Linked Organization"
        case .ministry:          return "Verified Ministry"
        case .charityDonation:   return "Verified Charity"
        case .eventHost:         return "Verified Event Host"
        }
    }

    /// One-sentence explanation shown in the detail sheet.
    var verificationExplanation: String {
        switch self {
        case .none:
            return "This account has not been verified."
        case .person:
            return "AMEN has confirmed the identity of the person behind this account."
        case .leader:
            return "AMEN has confirmed this account belongs to a verified faith leader or pastor."
        case .churchLinked:
            return "This account is officially linked to a verified church or house of worship."
        case .ministry:
            return "AMEN has reviewed and verified this ministry organization."
        case .charityDonation:
            return "This account belongs to a verified charitable organization that accepts donations through AMEN."
        case .eventHost:
            return "AMEN has verified this account as an authorized host of community or faith events."
        }
    }
}

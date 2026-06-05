//
//  CreatorTrustBadgeView.swift
//  AMENAPP
//
//  Inline verified / pending badge shown on creator profiles and the Creator Studio toolbar.
//

import SwiftUI

// MARK: - CreatorTrustBadgeView

struct CreatorTrustBadgeView: View {

    // Support both (score:status:) and (trustScore:verificationStatus:) call-sites
    var score: Double
    var status: CreatorProfile.VerificationStatus
    var showLabel: Bool

    init(score: Double, status: CreatorProfile.VerificationStatus, showLabel: Bool = false) {
        self.score = score; self.status = status; self.showLabel = showLabel
    }

    init(trustScore: Double, verificationStatus: CreatorProfile.VerificationStatus, showLabel: Bool = false) {
        self.score = trustScore; self.status = verificationStatus; self.showLabel = showLabel
    }

    // ── Internal state ────────────────────────────────────────────────
    @State private var sparkleScale:   CGFloat = 0.8
    @State private var sparkleOpacity: Double  = 0.0
    @State private var showBadgeInfo           = false

    private let Color.accentColor = Color(red: 0.96, green: 0.62, blue: 0.04)

    var body: some View {
        switch status {
        case .verified where score >= 0.8:
            verifiedBadge
        case .pending:
            pendingPill
        default:
            // Fallback compact badge (unverified / low-trust)
            compactBadge
        }
    }

    // MARK: - Verified Badge (gold, animated sparkle)

    private var verifiedBadge: some View {
        Button { showBadgeInfo = true } label: {
            HStack(spacing: 5) {
                ZStack {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(10, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(sparkleScale)
                        .opacity(sparkleOpacity)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.systemScaled(showLabel ? 14 : 12, weight: .semibold))
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(Color.accentColor)
                }

                if showLabel {
                    Text("Verified Creator")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, showLabel ? 10 : 7)
            .padding(.vertical, showLabel ? 5 : 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            )
        }
        .buttonStyle(CoCreationPressStyle())
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.65)).delay(0.2)) {
                sparkleScale   = 1.4
                sparkleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
                sparkleScale   = 1.0
                sparkleOpacity = 0.0
            }
        }
        .alert("Verified Creator", isPresented: $showBadgeInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("""
            This creator has been verified by AMEN for authentic, faith-aligned content.

            Trust Score: \(Int(score * 100))%

            Verification considers content quality, community engagement, and alignment with AMEN's community covenant.
            """)
        }
    }

    // MARK: - Pending Pill

    private var pendingPill: some View {
        Button { showBadgeInfo = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock.fill")
                    .font(.systemScaled(11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.45))
                if showLabel {
                    Text("Verification Pending")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, showLabel ? 10 : 7)
            .padding(.vertical, showLabel ? 5 : 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            )
        }
        .buttonStyle(CoCreationPressStyle())
        .alert("Verification In Progress", isPresented: $showBadgeInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your creator account is under review. Verified badges are awarded to creators with authentic, faith-aligned content and strong community trust. You'll be notified when verification is complete.")
        }
    }

    // MARK: - Compact fallback badge

    private var compactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeIcon)
                .font(.systemScaled(showLabel ? 13 : 12))
                .foregroundStyle(badgeColor)
            if showLabel {
                Text(badgeLabel)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(badgeColor)
            }
        }
        .padding(.horizontal, showLabel ? 10 : 7)
        .padding(.vertical, showLabel ? 5 : 4)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.15))
                .overlay(Capsule().stroke(badgeColor.opacity(0.3), lineWidth: 0.5))
        )
    }

    private var badgeIcon: String {
        switch status {
        case .verified:   return "checkmark.seal.fill"
        case .pending:    return "clock.badge.checkmark.fill"
        case .unverified: return "person.crop.circle.badge.questionmark.fill"
        }
    }

    private var badgeLabel: String {
        switch status {
        case .verified:   return "Verified"
        case .pending:    return "Pending"
        case .unverified: return score >= 0.7 ? "Trusted" : "New Creator"
        }
    }

    private var badgeColor: Color {
        switch status {
        case .verified:   return Color.accentColor
        case .pending:    return Color(red: 0.02, green: 0.71, blue: 0.83)
        case .unverified: return score >= 0.7 ? Color(red: 0.06, green: 0.73, blue: 0.51) : Color.white.opacity(0.4)
        }
    }
}

// MARK: - CreatorSubscriptionBadge (compact inline, unchanged)

struct CreatorSubscriptionBadge: View {
    let isSubscribed: Bool

    private let Color.accentColor = Color(red: 0.96, green: 0.62, blue: 0.04)

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isSubscribed ? "star.fill" : "star")
                .font(.systemScaled(11))
            Text(isSubscribed ? "Subscribed" : "Subscribe")
                .font(AMENFont.semiBold(11))
        }
        .foregroundStyle(isSubscribed ? Color.accentColor : .white.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isSubscribed ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.08))
                .overlay(
                    Capsule().stroke(
                        isSubscribed ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.12),
                        lineWidth: 0.5
                    )
                )
        )
    }
}

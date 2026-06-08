// GivingRequestsView.swift
// AMENAPP
//
// Verified benevolence requests — peer-to-peer giving, church-anchored.
// Anonymous by default. Strongly moderated. No GoFundMe energy.
// No donor leaderboards. No social proof. No urgency manipulation.

import SwiftUI

struct GivingRequestsView: View {
    let requests: [BenevolenceRequest]
    let isLoading: Bool

    var body: some View {
        LazyVStack(spacing: 16) {
            // Moderation transparency header
            moderationHeader

            if isLoading {
                ForEach(0..<3, id: \.self) { _ in skeletonCard }
            } else if requests.isEmpty {
                emptyView
            } else {
                ForEach(requests) { request in
                    RequestCard(
                        request: request,
                        onGive: { /* open give flow */ },
                        onPray: { /* open prayer flow */ }
                    )
                }
            }

            // Policy note
            policyNote
        }
    }

    // MARK: - Moderation Header

    private var moderationHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Acts 2 Benevolence", systemImage: "person.3.fill")
                .font(.systemScaled(11, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(AmenTheme.Colors.textTertiary)

            Text("These requests are from verified church members with pastoral or benevolence team attestation. Every request passes Guardian AI review before appearing here.")
                .font(.systemScaled(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineSpacing(2)

            // Guarantees row
            HStack(spacing: 16) {
                guaranteeChip("Guardian cleared", icon: "checkmark.shield.fill")
                guaranteeChip("Anonymous giving", icon: "eye.slash.fill")
                guaranteeChip("1 per person", icon: "person.badge.shield.checkmark")
            }
        }
        .padding(16)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .amenShadow(radius: 8, y: 2)
    }

    private func guaranteeChip(_ label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.systemScaled(14))
                .foregroundStyle(AmenTheme.Colors.statusSuccess)
            Text(label)
                .font(.systemScaled(9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.systemScaled(36))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No active requests right now")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Verified requests will appear here when approved by church verification and Guardian review.")
                .font(.systemScaled(14))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Policy Note

    private var policyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How this works")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            ForEach(policyPoints, id: \.self) { point in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.systemScaled(4))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .padding(.top, 6)
                    Text(point)
                        .font(.systemScaled(12))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .lineSpacing(2)
                }
            }
        }
        .padding(14)
        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private let policyPoints = [
        "Every request requires church admin, pastoral, or benevolence team verification.",
        "Requests pass Guardian AI fraud and manipulation review before appearing.",
        "Giving is anonymous by default — donors are never shown to requesters or others.",
        "One active request per person at a time. Hard caps by category.",
        "Outcome follow-up is required after fulfillment.",
    ]

    // MARK: - Skeleton

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(AmenTheme.Colors.shimmerBase).frame(width: 80, height: 10)
            Capsule().fill(AmenTheme.Colors.shimmerBase).frame(height: 16)
            Capsule().fill(AmenTheme.Colors.shimmerBase).frame(width: 180, height: 12)
            Capsule().fill(AmenTheme.Colors.shimmerBase).frame(height: 12)
        }
        .padding(16)
        .amenCard(cornerRadius: 22, shadow: false)
        .amenSkeleton()
    }
}

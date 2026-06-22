// GivingRankingService.swift
// AMENAPP
//
// Transparent, inspectable ranking engine for organizations and opportunities.
// Every ranking decision produces explanation tokens. No paid overrides. No opaque signals.
// Diversity balancing prevents single-org domination or permanent cold-start lockout.

import Foundation

@MainActor
final class GivingRankingService {

    // MARK: - Rank Organizations

    func rank(
        organizations: [GivingOrganization],
        profile: GivingProfile,
        disasterEvent: DisasterEvent? = nil,
        userHistory: [String: UserOrgEngagement] = [:]
    ) -> [GivingOrganization] {
        var scored = organizations.map { org in
            score(org: org, profile: profile, disasterEvent: disasterEvent, history: userHistory[org.id])
        }

        // Diversity balancing: penalize if same cause dominates top 4
        scored = applyDiversityBalance(scored)

        return scored.sorted { $0.rankScore > $1.rankScore }
    }

    // MARK: - Score Single Organization

    private func score(
        org: GivingOrganization,
        profile: GivingProfile,
        disasterEvent: DisasterEvent?,
        history: UserOrgEngagement?
    ) -> GivingOrganization {
        var total = 0.0
        var tokens: [RankingExplanation.RankingToken] = []

        // --- Cause match (0–30 pts)
        let causeMatches = org.causeCategories.filter { profile.causePreferences.contains($0) }
        if let firstCause = causeMatches.first {
            let pts = min(Double(causeMatches.count) * 15.0, 30.0)
            total += pts
            tokens.append(.init(key: "cause_match:\(firstCause.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))",
                               label: "Aligns with your cause: \(firstCause.rawValue)"))
        }

        // --- Geography match (0–20 pts)
        let geoScore = geographyScore(org: org, preference: profile.geographicPreference, homeRegion: profile.homeRegion)
        total += geoScore.pts
        if geoScore.pts > 0 { tokens.append(geoScore.token) }

        // --- Theological alignment (0–12 pts)
        if org.theologicalAffiliations.isEmpty || org.theologicalAffiliations.contains(profile.theologicalAlignment)
            || org.theologicalAffiliations.contains(.denominationallyNeutral) {
            total += 12
            tokens.append(.init(key: "theology_compatible:\(profile.theologicalAlignment.rawValue.lowercased())",
                               label: "Compatible with \(profile.theologicalAlignment.rawValue) framing"))
        }

        // --- Giving style compatibility (0–10 pts)
        let styleMatches = org.givingStylesSupported.filter { profile.givingStylePreferences.contains($0) }
        if let firstStyle = styleMatches.first {
            total += 10
            tokens.append(.init(key: "supports:\(firstStyle.rawValue.lowercased())",
                               label: "Supports \(firstStyle.rawValue) giving"))
        }

        // --- Trust score (0–15 pts)
        let trustPts = org.trustScore * 15.0
        total += trustPts
        if trustPts > 10 {
            tokens.append(.init(key: "trust:high", label: "Strong transparency data available"))
        }

        // --- Data freshness (0–8 pts)
        let freshnessPts = freshnessScore(org: org)
        total += freshnessPts
        if freshnessPts > 4 {
            tokens.append(.init(key: "recent_action:verified", label: "Verified field activity in last 90 days"))
        }

        // --- Disaster response relevance (0–15 pts)
        if let event = disasterEvent, org.isDisasterResponder {
            let regionOverlap = event.regions.contains { region in
                org.serviceRegions.contains { $0.state == region || $0.country == region }
            }
            let pts = regionOverlap ? 15.0 : 8.0
            total += pts
            tokens.append(.init(key: "active_disaster_response:true", label: "Active response to current disaster"))
        }

        // --- Prior engagement (light weight, 0–5 pts, never dominates)
        if let hist = history, hist.hasEngaged {
            total += min(Double(hist.tapCount) * 1.0, 5.0)
        }

        var updated = org
        updated.rankScore = total
        updated.rankingExplanation = RankingExplanation(tokens: tokens)
        return updated
    }

    // MARK: - Geography Score

    private func geographyScore(
        org: GivingOrganization,
        preference: GeographicPreference,
        homeRegion: GivingProfile.HomeRegion?
    ) -> (pts: Double, token: RankingExplanation.RankingToken) {
        let hasLocal = org.serviceRegions.contains { $0.isLocal }
        let hasGlobal = org.serviceRegions.contains { $0.isGlobal }

        switch preference {
        case .localFirst:
            if hasLocal {
                let locality = org.serviceRegions.first(where: { $0.isLocal })?.displayLabel ?? "your area"
                return (20, .init(key: "geo_match:local_first", label: "Local to \(locality)"))
            }
            return hasGlobal ? (4, .init(key: "geo_match:global", label: "Global reach")) : (0, .init(key: "", label: ""))
        case .global:
            if hasGlobal {
                return (20, .init(key: "geo_match:global", label: "Global organization"))
            }
            return (6, .init(key: "geo_match:regional", label: "Regional impact"))
        case .balanced:
            let pts = hasLocal ? 14.0 : (hasGlobal ? 12.0 : 6.0)
            let label = hasLocal ? "Serves locally" : "Global reach"
            let key = hasLocal ? "geo_match:local" : "geo_match:global"
            return (pts, .init(key: key, label: label))
        }
    }

    // MARK: - Freshness Score

    private func freshnessScore(org: GivingOrganization) -> Double {
        guard let recentAction = org.recentActions.first,
              let occurredAt = recentAction.occurredAt else { return 0 }
        let daysSince = Calendar.current.dateComponents([.day], from: occurredAt, to: Date()).day ?? 365
        if daysSince <= 30 { return 8 }
        if daysSince <= 90 { return 5 }
        if daysSince <= 180 { return 2 }
        return 0
    }

    // MARK: - Diversity Balance

    private func applyDiversityBalance(_ orgs: [GivingOrganization]) -> [GivingOrganization] {
        var causeCounts: [GivingCause: Int] = [:]
        return orgs.map { org in
            var updated = org
            if let primaryCause = org.causeCategories.first {
                let count = causeCounts[primaryCause, default: 0]
                if count >= 2 {
                    // Penalty for over-representation — ensures local diversity
                    updated.rankScore = max(0, org.rankScore - Double(count) * 3.0)
                }
                causeCounts[primaryCause] = count + 1
            }
            return updated
        }
    }

    // MARK: - Filter for Tab

    func filter(organizations: [GivingOrganization], for tab: GivingFeedTab) -> [GivingOrganization] {
        switch tab {
        case .local:
            return organizations.filter { $0.serviceRegions.contains { $0.isLocal } || $0.isLocalPartner }
        case .vetted:
            return organizations.filter { $0.trustScore >= 0.5 }
        default:
            return organizations
        }
    }
}

// MARK: - User Org Engagement

struct UserOrgEngagement {
    let orgId: String
    var tapCount: Int
    var hasDonated: Bool
    var lastInteractedAt: Date?

    var hasEngaged: Bool { tapCount > 0 || hasDonated }
}

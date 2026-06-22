// BereanGivingService.swift
// AMENAPP
//
// Berean as giving counselor — not a conversion funnel.
// Returns calm, source-grounded, theologically careful recommendations.
// Never promises blessing, never pressures, never recommends without transparency data.

import Foundation
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class BereanGivingService: ObservableObject {

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    // MARK: - Get Counsel

    func getCounsel(
        prompt: String,
        budget: Int,               // cents
        profile: GivingProfile,
        candidates: [GivingOrganization]
    ) async -> BereanGivingResponse {
        // Build structured recommendation set from high-trust orgs matching profile
        let topCandidates = candidates
            .filter { $0.trustScore >= 0.6 }  // Only recommend with transparency data
            .sorted { $0.rankScore > $1.rankScore }
            .prefix(3)

        var recommendations: [BereanGivingRecommendation] = topCandidates.compactMap { org in
            buildRecommendation(org: org, budget: budget, profile: profile)
        }

        // Always offer a "reflect first" option
        recommendations.append(BereanGivingRecommendation(
            org: nil,
            request: nil,
            brief: nil,
            reason: "Taking time to discern before giving is wisdom, not indecision. The goal is generous faithfulness, not speed.",
            scriptureRef: "Matthew 6:3",
            scriptureText: "But when you give to the needy, do not let your left hand know what your right hand is doing.",
            fitLabel: "Discernment",
            actionLabel: "Reflect first",
            destinationType: .reflect
        ))

        let budgetFormatted = "$\(budget / 100)"
        return BereanGivingResponse(
            prompt: prompt,
            summary: buildSummary(prompt: prompt, budget: budgetFormatted, profile: profile, count: topCandidates.count),
            recommendations: recommendations,
            closingReflection: closingReflection(for: profile),
            generatedAt: Date()
        )
    }

    // MARK: - Build Recommendation

    private func buildRecommendation(
        org: GivingOrganization,
        budget: Int,
        profile: GivingProfile
    ) -> BereanGivingRecommendation? {
        guard let transparency = org.transparency,
              transparency.verificationStatus == .verified else {
            // Berean never recommends without transparency data
            return nil
        }

        let reason = buildReason(org: org, budget: budget, profile: profile)
        let scripture = scriptureForCause(org.causeCategories.first)
        let fitLabel = fitLabel(for: org, profile: profile)

        return BereanGivingRecommendation(
            org: org,
            request: nil,
            brief: nil,
            reason: reason,
            scriptureRef: scripture?.ref,
            scriptureText: scripture?.text,
            fitLabel: fitLabel,
            actionLabel: "Give to \(org.name)",
            destinationType: .organization
        )
    }

    private func buildReason(org: GivingOrganization, budget: Int, profile: GivingProfile) -> String {
        var parts: [String] = []

        if let transparency = org.transparency,
           let ratio = transparency.programExpenseRatio {
            let cents = Int(ratio * 100)
            parts.append("\(cents)¢ of every dollar goes to programs")
            if let year = transparency.fiscalYear, let provider = transparency.sourceProviders.first {
                parts.append("Source: \(provider) \(year)")
            }
        }

        if let action = org.recentActions.first {
            parts.append(action.summary)
        }

        let budgetDollars = budget / 100
        if let giftMatch = org.giftImpacts.first(where: { $0.amount <= budgetDollars }) {
            parts.append("$\(giftMatch.amount) = \(giftMatch.description)")
        }

        return parts.joined(separator: ". ")
    }

    private func fitLabel(for org: GivingOrganization, profile: GivingProfile) -> String {
        let causeMatch = org.causeCategories.first(where: { profile.causePreferences.contains($0) })
        if let cause = causeMatch { return "\(cause.rawValue) match" }
        if org.isLocalPartner { return "Local" }
        return "Trusted"
    }

    // MARK: - Scripture

    private func scriptureForCause(_ cause: GivingCause?) -> (ref: String, text: String)? {
        guard let cause else { return nil }
        switch cause {
        case .fosterCare, .pregnancyWomen:
            return ("Psalm 82:3", "Defend the weak and the fatherless.")
        case .persecutedChurch:
            return ("Hebrews 13:3", "Remember those in prison as if you were together with them.")
        case .homelessness:
            return ("Isaiah 58:7", "Share your food with the hungry and provide shelter for the wanderer.")
        case .disasterRelief:
            return ("Luke 10:33", "He saw him and had compassion.")
        case .antiTrafficking:
            return ("Proverbs 31:8", "Speak up for those who cannot speak for themselves.")
        case .prisonMinistry:
            return ("Matthew 25:36", "I was in prison and you came to visit me.")
        case .refugeeResettlement:
            return ("Leviticus 19:34", "The foreigner residing among you must be treated as your native-born.")
        default:
            return ("2 Corinthians 9:7", "Each one should give what he has decided in his heart to give.")
        }
    }

    // MARK: - Summary

    private func buildSummary(prompt: String, budget: String, profile: GivingProfile, count: Int) -> String {
        let causeLabel = profile.causePreferences.first?.rawValue ?? "your values"
        let geoLabel = profile.geographicPreference.rawValue.lowercased()
        return "Based on what you shared — \(budget) this month, a focus on \(causeLabel), \(geoLabel) reach — here are \(count) paths worth considering. Take your time."
    }

    private func closingReflection(for profile: GivingProfile) -> String {
        switch profile.givingStylePreferences.first {
        case .recurring:
            return "Consistent, recurring gifts provide organizations the stability to plan and serve faithfully."
        case .oneTime:
            return "A one-time gift at the right moment can meet urgent, specific needs with real impact."
        case .timeVolunteer:
            return "Your presence and time is a gift. Consider connecting directly with a local partner."
        default:
            return "Give from conviction, not compulsion. What you decide is between you and God."
        }
    }

    // MARK: - Save Session

    func saveBereanGivingSession(
        userId: String,
        prompt: String,
        profile: GivingProfile,
        recommendations: [BereanGivingRecommendation]
    ) async {
        let destIds = recommendations.compactMap { $0.org?.id ?? $0.request?.id }
        let data: [String: Any] = [
            "userId": userId,
            "prompt": prompt,
            "recommendedDestinationIds": destIds,
            "createdAt": FieldValue.serverTimestamp()
        ]
        _ = try? await db.collection("berean_giving_sessions").addDocument(data: data)
    }
}

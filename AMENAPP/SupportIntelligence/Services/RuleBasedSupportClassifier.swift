//
//  RuleBasedSupportClassifier.swift
//  AMENAPP
//
//  Deterministic first-pass classifier for the Resources Intelligence System.
//  This gives the app explainable support routing today while preserving a clean
//  swap point for future server or model-backed inference.
//

import Foundation

protocol SupportClassifying: AnyObject, Sendable {
    func classify(text: String, surface: SupportSurface) -> SupportClassification
}

final class RuleBasedSupportClassifier: SupportClassifying, @unchecked Sendable {
    private struct Rule {
        let phrases: [String]
        let domain: ResourceSupportDomain
        let theme: SupportTheme
        let reason: SupportReasonCode
        let score: Double
    }

    private let rules: [Rule] = [
        Rule(phrases: ["can't do this anymore", "done with everything", "want to disappear", "hurt myself", "end it all"],
             domain: .crisisImmediate, theme: .crisisIndicatorsStrong, reason: .activeSelfHarmPhrase, score: 0.95),
        Rule(phrases: ["nobody would miss me", "don't want to be here", "i'm done", "i can't go on"],
             domain: .depressionHopelessness, theme: .crisisIndicatorsSoft, reason: .hopelessnessWithRecency, score: 0.84),
        Rule(phrases: ["anxious", "panic", "overwhelmed", "can't calm down", "stressed out"],
             domain: .anxietyStress, theme: .anxiety, reason: .anxietyLanguage, score: 0.58),
        Rule(phrases: ["grief", "grieving", "miss them", "loss", "funeral"],
             domain: .griefLoss, theme: .grief, reason: .griefLanguage, score: 0.56),
        Rule(phrases: ["alone", "lonely", "no one", "need community", "new in town"],
             domain: .lonelinessCommunity, theme: .loneliness, reason: .communitySeekingPhrase, score: 0.54),
        Rule(phrases: ["church hurt", "hurt by church", "don't want to go to church", "spiritually exhausted"],
             domain: .churchHurt, theme: .spiritualExhaustion, reason: .churchHurtIntent, score: 0.52),
        Rule(phrases: ["counselor", "therapy", "therapist", "need counseling"],
             domain: .counselingTherapy, theme: .stress, reason: .counselingSeekingPhrase, score: 0.50),
        Rule(phrases: ["marriage", "husband", "wife", "relationship falling apart"],
             domain: .marriageRelationships, theme: .relationshipDistress, reason: .repeatedDistressLanguage, score: 0.48),
        Rule(phrases: ["relapse", "addiction", "sober", "recovery group"],
             domain: .addictionRecovery, theme: .addictionRecovery, reason: .repeatedDistressLanguage, score: 0.52),
        Rule(phrases: ["can't pay rent", "can't afford groceries", "need food", "need housing", "lost my job"],
             domain: .foodHousingNeed, theme: .financialHardship, reason: .foodHousingDistressPhrase, score: 0.60),
        Rule(phrases: ["can't afford", "money is tight", "financial stress", "behind on bills"],
             domain: .financialNeed, theme: .financialHardship, reason: .financialDistressPhrase, score: 0.50),
        Rule(phrases: ["pray for my anxiety", "pray for peace", "pray for strength", "need prayer badly"],
             domain: .prayerSupport, theme: .prayerForPeace, reason: .prayerForUrgentNeed, score: 0.42),
        Rule(phrases: ["my friend wants to disappear", "my husband is scaring me", "my daughter keeps saying she's done", "i'm worried about someone"],
             domain: .helpingSomeoneElse, theme: .helpingSomeoneElse, reason: .indirectConcernForOtherPerson, score: 0.72),
        Rule(phrases: ["looking for a church", "need a church", "find a church", "new church", "pastor nearby"],
             domain: .newcomerChurchDiscovery, theme: .loneliness, reason: .communitySeekingPhrase, score: 0.38),
        Rule(phrases: ["want to serve", "want to volunteer", "how can i help", "give back"],
             domain: .serviceVolunteer, theme: .healingProgress, reason: .hopefulLanguageDetected, score: 0.22),
        Rule(phrases: ["want to give", "donate", "nonprofit", "support this ministry"],
             domain: .givingNonprofits, theme: .gratitude, reason: .hopefulLanguageDetected, score: 0.18),
    ]

    func classify(text: String, surface: SupportSurface) -> SupportClassification {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .empty(surface: surface) }

        var matchedDomains: [ResourceSupportDomain: Double] = [:]
        var matchedThemes = Set<SupportTheme>()
        var matchedReasons: [SupportReasonCode] = []
        var helpingSomeoneElse = false

        for rule in rules where rule.phrases.contains(where: { normalized.contains($0) }) {
            matchedDomains[rule.domain] = max(matchedDomains[rule.domain] ?? 0, rule.score)
            matchedThemes.insert(rule.theme)
            matchedReasons.append(rule.reason)
            if rule.domain == .helpingSomeoneElse {
                helpingSomeoneElse = true
            }
        }

        if normalized.contains("late night") || normalized.contains("can't sleep") {
            matchedThemes.insert(.stress)
            matchedReasons.append(.repeatedLateNightUsage)
            matchedDomains[.emotionalWellness] = max(matchedDomains[.emotionalWellness] ?? 0, 0.20)
        }

        if normalized.contains("berean") || normalized.contains("scripture") || normalized.contains("verse") {
            matchedDomains[.bibleGuidance] = max(matchedDomains[.bibleGuidance] ?? 0, 0.18)
        }

        let topScore = matchedDomains.values.max() ?? 0
        let severity = SupportRiskTier.from(score: min(1.0, topScore))
        let confidence = min(0.96, max(0.18, Double(matchedDomains.count) * 0.18 + topScore * 0.55))
        let orderedDomains = matchedDomains.sorted { $0.value > $1.value }.map(\.key)
        let reasons = matchedReasons.isEmpty ? [.noSignalsSufficient] : Array(Set(matchedReasons))

        return SupportClassification(
            domains: orderedDomains,
            severity: severity,
            confidence: confidence,
            helpingSomeoneElse: helpingSomeoneElse,
            reasoningCodes: reasons,
            detectedThemes: Array(matchedThemes),
            sourceSurface: surface,
            createdAt: Date()
        )
    }
}

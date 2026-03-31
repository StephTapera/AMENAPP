// WellnessRiskLayer.swift
// AMENAPP
//
// AMEN Wellness & Crisis Support Intelligence System
//
// A graduated, pattern-based, privacy-aware wellness detection and
// intervention system. Does NOT diagnose mental illness. Detects signals
// of distress, hopelessness, isolation, financial desperation, comparison
// harm, and crisis risk — then responds with the minimum necessary
// compassionate action.
//
// Design philosophy:
//   Preventive, not reactive
//   Supportive, not punitive
//   Contextual, not keyword-based
//   Privacy-aware, not creepy
//   Graduated, not alarmist

import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - Part 1: Data Models

// MARK: SupportDomain

enum SupportDomain: String, CaseIterable, Identifiable {
    case emotionalSupport
    case crisisSupport
    case financialHelp
    case housingFoodAid
    case abuseSafety
    case lonelinessCommunity
    case prayerPastoralCare
    case therapyCounseling
    case addictionRecovery
    case harassmentSafety
    case faithShame

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emotionalSupport:    return "Emotional Support"
        case .crisisSupport:       return "Crisis Support"
        case .financialHelp:       return "Financial Help"
        case .housingFoodAid:      return "Housing & Food Aid"
        case .abuseSafety:         return "Abuse & Safety"
        case .lonelinessCommunity: return "Community & Connection"
        case .prayerPastoralCare:  return "Prayer & Pastoral Care"
        case .therapyCounseling:   return "Therapy & Counseling"
        case .addictionRecovery:   return "Addiction Recovery"
        case .harassmentSafety:    return "Harassment Safety"
        case .faithShame:          return "Faith & Shame"
        }
    }

    var icon: String {
        switch self {
        case .emotionalSupport:    return "heart.fill"
        case .crisisSupport:       return "phone.fill"
        case .financialHelp:       return "dollarsign.circle.fill"
        case .housingFoodAid:      return "house.fill"
        case .abuseSafety:         return "shield.fill"
        case .lonelinessCommunity: return "person.2.fill"
        case .prayerPastoralCare:  return "hands.and.sparkles.fill"
        case .therapyCounseling:   return "brain.head.profile"
        case .addictionRecovery:   return "figure.walk.circle.fill"
        case .harassmentSafety:    return "exclamationmark.shield.fill"
        case .faithShame:          return "book.closed.fill"
        }
    }

    var resourceTitle: String {
        switch self {
        case .emotionalSupport:    return "Talk to someone"
        case .crisisSupport:       return "Get crisis support now"
        case .financialHelp:       return "Get financial help"
        case .housingFoodAid:      return "Find housing & food resources"
        case .abuseSafety:         return "Get to safety"
        case .lonelinessCommunity: return "Find your people"
        case .prayerPastoralCare:  return "Talk to a pastor"
        case .therapyCounseling:   return "Find a counselor"
        case .addictionRecovery:   return "Recovery resources"
        case .harassmentSafety:    return "Report & protect yourself"
        case .faithShame:          return "Grace is real. You belong."
        }
    }

    var resourceSubtext: String {
        switch self {
        case .emotionalSupport:    return "A safe space to share what's on your heart"
        case .crisisSupport:       return "988 Suicide & Crisis Lifeline — call or text"
        case .financialHelp:       return "Local programs for bills, rent, and essentials"
        case .housingFoodAid:      return "Shelters, food banks, and emergency housing"
        case .abuseSafety:         return "Confidential help for dangerous situations"
        case .lonelinessCommunity: return "Connect with nearby believers and small groups"
        case .prayerPastoralCare:  return "Let someone pray with and for you"
        case .therapyCounseling:   return "Professional care from faith-aware counselors"
        case .addictionRecovery:   return "You don't have to fight this alone"
        case .harassmentSafety:    return "Tools and steps to protect your peace"
        case .faithShame:          return "Doubt and struggle don't disqualify you"
        }
    }
}

// MARK: WellnessIntervention

enum WellnessIntervention: Int, Comparable {
    case none              = 0
    case feedAdjustment    = 1   // invisible — no UI
    case softNudge         = 2   // optional gentle card
    case reflectionPrompt  = 3   // Church Notes / Berean
    case supportSheet      = 4   // category choices sheet
    case crisisSheet       = 5   // dedicated crisis support
    case urgentEscalation  = 6   // imminent danger only

    static func < (lhs: WellnessIntervention, rhs: WellnessIntervention) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: WellnessRiskLevel

enum WellnessRiskLevel: Int {
    case normal            = 0
    case mildStrain        = 1
    case moderateDistress  = 2
    case highConcern       = 3
    case imminentDanger    = 4
}

// MARK: WellnessRiskState

struct WellnessRiskState {
    var acuteRiskScore: Double          = 0.0   // 0–1, what's happening now
    var chronicDistressScore: Double    = 0.0   // 0–1, building over days
    var comparisonHarmScore: Double     = 0.0   // 0–1, identity-damaging content
    var financialNeedScore: Double      = 0.0   // 0–1, money/housing/food signals
    var abuseRiskScore: Double          = 0.0   // 0–1, coercion/abuse indicators
    var socialIsolationScore: Double    = 0.0   // 0–1, withdrawal signals
    var confidenceScore: Double         = 0.0   // 0–1, system confidence
    var recommendedIntervention: WellnessIntervention = .none
    var recommendedSupportDomains: [SupportDomain] = []
    var lastUpdated: Date = Date()

    var compositeRiskLevel: WellnessRiskLevel {
        let composite =
            acuteRiskScore          * 0.35
            + chronicDistressScore  * 0.25
            + abuseRiskScore        * 0.20
            + (financialNeedScore + socialIsolationScore) * 0.10
            + comparisonHarmScore   * 0.10

        switch composite {
        case ..<0.20:  return .normal
        case 0.20..<0.40: return .mildStrain
        case 0.40..<0.60: return .moderateDistress
        case 0.60..<0.80: return .highConcern
        default:          return .imminentDanger
        }
    }
}

// MARK: BehavioralSignal

enum WellnessBehavioralSignal: String {
    case lateNightScroll         // past 11 PM session > 30 min
    case sessionLengthSpike      // 2x normal session length
    case lowInteractionScroll    // heavy scroll, very few likes/reactions
    case repeatedSadContent      // repeated engagement with heavy content
    case comparisonPattern       // bouncing between high-status profiles
    case abandonedVulnerablePost // started and deleted vulnerable post
    case repeatedResourceVisit   // visited help/wellness resources 3+ times
    case socialWithdrawal        // drop in posting/interaction after prior activity
    case repeatedHeavySearch     // searched loneliness/money/sadness/rejection
}

struct BehavioralEvent {
    let signal: WellnessBehavioralSignal
    let timestamp: Date
    let weight: Double   // 0.0–1.0
}

// MARK: LanguageRiskCategory

enum LanguageRiskCategory: String {
    case hopelessness
    case burdensomeness
    case entrapment
    case socialWithdrawal
    case selfLoathing
    case financialDesperation
    case abuse
    case panicCrisis
    case passiveSuicidalIdeation
    case activeSuicidalIdeation
    case relapse
    case bodyComparisonDistress
    case harassmentVictim
    case faithShame
    case romanticRejectionSpiral

    var baseWeight: Double {
        switch self {
        case .activeSuicidalIdeation:   return 0.90
        case .passiveSuicidalIdeation:  return 0.75
        case .abuse:                    return 0.70
        case .panicCrisis:              return 0.65
        case .entrapment:               return 0.60
        case .burdensomeness:           return 0.55
        case .financialDesperation:     return 0.50
        case .hopelessness:             return 0.40
        case .selfLoathing:             return 0.40
        case .relapse:                  return 0.45
        case .harassmentVictim:         return 0.55
        case .faithShame:               return 0.35
        case .bodyComparisonDistress:   return 0.35
        case .socialWithdrawal:         return 0.30
        case .romanticRejectionSpiral:  return 0.30
        }
    }

    // Low-risk categories require a repeated pattern before elevating
    var requiresPatternConfirmation: Bool {
        switch self {
        case .activeSuicidalIdeation, .passiveSuicidalIdeation,
             .abuse, .panicCrisis:
            return false
        default:
            return true
        }
    }
}

struct LanguageRiskAssessment {
    let category: LanguageRiskCategory
    let confidence: Double          // 0–1
    let isQuoted: Bool              // quoted/reposted — lowers weight
    let isSelfReferential: Bool
    let contextualModifier: Double  // sarcasm/joke/scripture detected → reduces weight

    var effectiveWeight: Double {
        let base = category.baseWeight * confidence * contextualModifier
        return isQuoted ? base * 0.3 : base
    }
}

// MARK: WellnessDismissalFeedback

enum WellnessDismissalFeedback: String {
    case helpful
    case notHelpful
    case notRelevant
    case tooFrequent
}

// MARK: - Part 2: WellnessRiskService

@MainActor
final class WellnessRiskService: ObservableObject {

    static let shared = WellnessRiskService()

    @Published var currentRiskState = WellnessRiskState()
    @Published var pendingIntervention: WellnessIntervention = .none
    @Published var activeSupportDomains: [SupportDomain] = []

    // Internal rolling event window (7 days)
    private var behavioralEvents: [BehavioralEvent] = []
    // Language assessments in a 48h window for pattern confirmation
    private var recentLanguageAssessments: [LanguageRiskAssessment] = []
    // Suppressed interventions: type → soonest allowed Date
    private var suppressedUntil: [WellnessIntervention: Date] = [:]
    // Last nudge timestamp to enforce 24h throttle
    private var lastSoftNudgeDate: Date?

    private init() {}

    // MARK: recordBehavioralSignal

    func recordBehavioralSignal(_ signal: WellnessBehavioralSignal) {
        let weight = defaultWeight(for: signal)
        let event = BehavioralEvent(signal: signal, timestamp: Date(), weight: weight)
        behavioralEvents.append(event)
        pruneBehavioralWindow()
        recomputeBehavioralScores()
        evaluateAndIntervene()
    }

    private func defaultWeight(for signal: WellnessBehavioralSignal) -> Double {
        switch signal {
        case .lateNightScroll:          return 0.30
        case .sessionLengthSpike:       return 0.25
        case .lowInteractionScroll:     return 0.20
        case .repeatedSadContent:       return 0.40
        case .comparisonPattern:        return 0.35
        case .abandonedVulnerablePost:  return 0.45
        case .repeatedResourceVisit:    return 0.35
        case .socialWithdrawal:         return 0.40
        case .repeatedHeavySearch:      return 0.45
        }
    }

    private func pruneBehavioralWindow() {
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86400)
        behavioralEvents.removeAll { $0.timestamp < sevenDaysAgo }
    }

    private func recomputeBehavioralScores() {
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-48 * 3600)

        var acuteSum: Double = 0
        var chronicSum: Double = 0
        var comparisonSum: Double = 0
        var isolationSum: Double = 0

        for event in behavioralEvents {
            let age = now.timeIntervalSince(event.timestamp)
            // Decay: older than 48h → 50% weight
            let decayFactor: Double = event.timestamp < twoDaysAgo ? 0.5 : 1.0
            let adjusted = event.weight * decayFactor

            switch event.signal {
            case .repeatedSadContent, .abandonedVulnerablePost,
                 .repeatedHeavySearch:
                acuteSum += adjusted
                chronicSum += adjusted * 0.6

            case .lateNightScroll, .sessionLengthSpike,
                 .lowInteractionScroll:
                acuteSum += adjusted * 0.5
                chronicSum += adjusted * 0.3

            case .comparisonPattern:
                comparisonSum += adjusted

            case .socialWithdrawal, .repeatedResourceVisit:
                isolationSum += adjusted
                chronicSum += adjusted * 0.4
            }
            _ = age  // suppress unused warning
        }

        currentRiskState.acuteRiskScore        = min(acuteSum, 1.0)
        currentRiskState.chronicDistressScore   = min(chronicSum, 1.0)
        currentRiskState.comparisonHarmScore    = min(comparisonSum, 1.0)
        currentRiskState.socialIsolationScore   = min(isolationSum, 1.0)
        currentRiskState.lastUpdated            = Date()
    }

    // MARK: assessLanguageRisk

    func assessLanguageRisk(
        text: String,
        isQuoted: Bool,
        isPublicPost: Bool,
        context: String
    ) -> [LanguageRiskAssessment] {

        let lowered = text.lowercased()
        var assessments: [LanguageRiskAssessment] = []

        let keywords: [(LanguageRiskCategory, [String])] = [
            (.hopelessness, [
                "i give up", "what's the point", "nothing matters",
                "too tired to", "can't keep going", "there's no hope",
                "pointless", "what's even the point"
            ]),
            (.burdensomeness, [
                "everyone would be better", "i'm a burden", "no one needs me",
                "better off without me", "i just get in the way"
            ]),
            (.entrapment, [
                "can't escape", "no way out", "trapped",
                "i'm stuck forever", "no exit", "can't get out of this"
            ]),
            (.activeSuicidalIdeation, [
                "want to kill myself", "end my life", "going to kill myself",
                "want to die", "planning to end it", "going to end it all"
            ]),
            (.passiveSuicidalIdeation, [
                "wish i was dead", "don't want to be here anymore",
                "want to disappear", "wish i could just disappear",
                "wouldn't mind if i never woke up"
            ]),
            (.financialDesperation, [
                "can't pay rent", "losing my home", "can't afford",
                "evicted", "can't eat", "going to lose everything",
                "about to be homeless", "can't make ends meet"
            ]),
            (.abuse, [
                "he hits me", "she controls me", "scared of",
                "afraid to leave", "he threatens me", "she won't let me",
                "i can't leave", "afraid of what they'll do"
            ]),
            (.selfLoathing, [
                "i hate myself", "i'm worthless", "i'm pathetic",
                "disgusted with myself", "i'm a failure", "i'm nothing"
            ]),
            (.panicCrisis, [
                "can't breathe", "having a panic attack", "heart is racing",
                "i'm losing my mind", "i can't function"
            ]),
            (.relapse, [
                "i relapsed", "i slipped up again", "i drank again",
                "i used again", "back to square one"
            ]),
            (.bodyComparisonDistress, [
                "i hate my body", "i'll never look like that",
                "everyone is so much prettier", "i'm so ugly compared",
                "i'm disgusting compared"
            ]),
            (.harassmentVictim, [
                "they won't stop messaging me", "being harassed",
                "can't make them stop", "they're threatening me"
            ]),
            (.faithShame, [
                "god doesn't love me", "i'm too sinful", "god gave up on me",
                "i'm beyond forgiveness", "unworthy of grace"
            ]),
            (.romanticRejectionSpiral, [
                "no one will ever love me", "i'm going to be alone forever",
                "nobody wants me", "i'm unlovable"
            ]),
            (.socialWithdrawal, [
                "i've been isolating", "stopped talking to everyone",
                "nobody checks on me", "i've been alone for weeks"
            ])
        ]

        // Sarcasm markers
        let sarcasmMarkers = ["lol", "lmao", "jk", "just kidding", "😂", "😅", "🙃", "haha"]
        let hasSarcasm = sarcasmMarkers.contains { lowered.contains($0) }

        // Scripture detection (verse references like "John 3:16", "Romans", "Psalms")
        let scripturePatterns = ["matthew", "luke", "john", "romans", "psalms", "proverbs",
                                 "genesis", "exodus", "revelation", "corinthians", "ephesians",
                                 "philippians", "hebrews", "james", "peter", "isaiah", "jeremiah"]
        let hasScripture = scripturePatterns.contains { lowered.contains($0) }

        for (category, phrases) in keywords {
            let matched = phrases.first { lowered.contains($0) }
            guard matched != nil else { continue }

            // Base confidence from match quality
            let confidence: Double = 0.75
            let isSelfRef = checkSelfReferential(text: lowered)

            // Context modifiers
            var modifier: Double = 1.0
            if hasSarcasm   { modifier *= 0.4 }
            if hasScripture { modifier *= 0.1 }
            if !isPublicPost { modifier *= 1.2 }   // DMs have higher weight

            let assessment = LanguageRiskAssessment(
                category: category,
                confidence: confidence,
                isQuoted: isQuoted,
                isSelfReferential: isSelfRef,
                contextualModifier: min(modifier, 1.2)
            )
            assessments.append(assessment)
            _ = confidence  // suppress warning
        }

        return assessments
    }

    private func checkSelfReferential(text: String) -> Bool {
        let selfMarkers = ["i ", "i'm ", "im ", "i've ", "ive ", "i feel", "i am "]
        return selfMarkers.contains { text.hasPrefix($0) || text.contains(" \($0)") }
    }

    // MARK: processLanguageRisk

    func processLanguageRisk(_ assessments: [LanguageRiskAssessment]) {
        let now = Date()
        let fortyEightHoursAgo = now.addingTimeInterval(-48 * 3600)

        // Prune old language assessments
        recentLanguageAssessments = recentLanguageAssessments.filter { _ in
            // LanguageRiskAssessment has no timestamp — keep all for now
            // In a full implementation, wrap with a timestamped container
            true
        }
        recentLanguageAssessments.append(contentsOf: assessments)
        _ = fortyEightHoursAgo

        for assessment in assessments {
            let cat = assessment.category

            // Immediate elevation: active suicidal ideation or very high confidence
            if cat == .activeSuicidalIdeation || assessment.confidence > 0.85 {
                applyLanguageScore(assessment)
                continue
            }

            // Pattern confirmation required for low-risk categories
            if cat.requiresPatternConfirmation {
                let similarCount = recentLanguageAssessments.filter {
                    $0.category == cat && $0.isSelfReferential
                }.count
                if similarCount >= 2 {
                    applyLanguageScore(assessment)
                }
            } else {
                applyLanguageScore(assessment)
            }
        }

        currentRiskState.lastUpdated = Date()
        evaluateAndIntervene()
    }

    private func applyLanguageScore(_ assessment: LanguageRiskAssessment) {
        let eff = assessment.effectiveWeight
        switch assessment.category {
        case .activeSuicidalIdeation, .passiveSuicidalIdeation, .entrapment,
             .panicCrisis, .burdensomeness:
            currentRiskState.acuteRiskScore = min(
                currentRiskState.acuteRiskScore + eff, 1.0)
        case .hopelessness, .selfLoathing, .romanticRejectionSpiral,
             .faithShame, .socialWithdrawal:
            currentRiskState.chronicDistressScore = min(
                currentRiskState.chronicDistressScore + eff * 0.7, 1.0)
        case .financialDesperation:
            currentRiskState.financialNeedScore = min(
                currentRiskState.financialNeedScore + eff, 1.0)
        case .abuse, .harassmentVictim:
            currentRiskState.abuseRiskScore = min(
                currentRiskState.abuseRiskScore + eff, 1.0)
        case .bodyComparisonDistress, .relapse:
            currentRiskState.comparisonHarmScore = min(
                currentRiskState.comparisonHarmScore + eff, 1.0)
        }
    }

    // MARK: evaluateAndIntervene

    func evaluateAndIntervene() {
        let s = currentRiskState

        // Composite formula
        let composite =
            s.acuteRiskScore       * 0.35
            + s.chronicDistressScore * 0.25
            + s.abuseRiskScore       * 0.20
            + (s.financialNeedScore + s.socialIsolationScore) * 0.10
            + s.comparisonHarmScore  * 0.10

        // Detect active suicidal signal from language assessments
        let activeSuicidalConfidence = recentLanguageAssessments
            .filter { $0.category == .activeSuicidalIdeation }
            .map { $0.confidence }
            .max() ?? 0.0

        // Determine risk level
        let level: WellnessRiskLevel
        if composite > 0.80 || activeSuicidalConfidence > 0.7 {
            level = .imminentDanger
        } else if composite >= 0.60 {
            level = .highConcern
        } else if composite >= 0.40 {
            level = .moderateDistress
        } else if composite >= 0.20 {
            level = .mildStrain
        } else {
            level = .normal
        }

        // Determine intervention
        let now = Date()
        let intervention: WellnessIntervention

        switch level {
        case .normal:
            intervention = .none

        case .mildStrain:
            // Throttle: only once per 24h
            if let last = lastSoftNudgeDate,
               now.timeIntervalSince(last) < 86400 {
                intervention = .feedAdjustment
            } else if isSuppressed(.softNudge) {
                intervention = .feedAdjustment
            } else {
                intervention = .softNudge
                lastSoftNudgeDate = now
            }

        case .moderateDistress:
            if isSuppressed(.supportSheet) {
                intervention = .reflectionPrompt
            } else {
                intervention = .supportSheet
            }

        case .highConcern:
            intervention = isSuppressed(.supportSheet) ? .crisisSheet : .supportSheet

        case .imminentDanger:
            intervention = activeSuicidalConfidence > 0.7
                ? .urgentEscalation
                : .crisisSheet
        }

        currentRiskState.recommendedIntervention = intervention
        currentRiskState.recommendedSupportDomains = inferSupportDomains()
        currentRiskState.confidenceScore = min(composite + 0.1, 1.0)

        pendingIntervention = intervention
        activeSupportDomains = currentRiskState.recommendedSupportDomains
    }

    // MARK: inferSupportDomains

    func inferSupportDomains() -> [SupportDomain] {
        var domains: [SupportDomain] = []
        let s = currentRiskState

        if s.financialNeedScore > 0.4 {
            domains.append(.financialHelp)
            domains.append(.housingFoodAid)
        }
        if s.abuseRiskScore > 0.4 {
            domains.append(.abuseSafety)
        }
        if s.socialIsolationScore > 0.5 {
            domains.append(.lonelinessCommunity)
        }
        if s.chronicDistressScore > 0.4 && s.acuteRiskScore < 0.6 {
            domains.append(.therapyCounseling)
        }
        if s.acuteRiskScore > 0.5 {
            domains.append(.emotionalSupport)
        }

        // Faith shame signals
        let hasFaithShame = recentLanguageAssessments.contains {
            $0.category == .faithShame
        }
        if hasFaithShame {
            domains.append(.faithShame)
            domains.append(.prayerPastoralCare)
        }

        // Crisis-level always includes crisis support
        if s.compositeRiskLevel == .imminentDanger || s.compositeRiskLevel == .highConcern {
            domains.insert(.crisisSupport, at: 0)
        }

        return Array(Set(domains)).sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: decayScores

    func decayScores() {
        currentRiskState.acuteRiskScore        *= (1.0 - 0.40)
        currentRiskState.chronicDistressScore   *= (1.0 - 0.10)
        currentRiskState.comparisonHarmScore    *= (1.0 - 0.30)
        currentRiskState.financialNeedScore     *= (1.0 - 0.05)
        // Social isolation and abuse risk intentionally not decayed here —
        // they should only reduce on positive signals
        currentRiskState.lastUpdated = Date()
    }

    // MARK: dismissIntervention

    func dismissIntervention(feedback: WellnessDismissalFeedback) {
        if feedback == .notHelpful {
            let fortyEightHoursLater = Date().addingTimeInterval(48 * 3600)
            suppressedUntil[pendingIntervention] = fortyEightHoursLater
        }
        pendingIntervention = .none
    }

    // MARK: recordHelpSeeking

    func recordHelpSeeking() {
        currentRiskState.acuteRiskScore = max(
            currentRiskState.acuteRiskScore - 0.20, 0.0)
        currentRiskState.lastUpdated = Date()
        // Re-evaluate after positive signal
        evaluateAndIntervene()
    }

    // MARK: Private helpers

    private func isSuppressed(_ intervention: WellnessIntervention) -> Bool {
        guard let until = suppressedUntil[intervention] else { return false }
        return Date() < until
    }
}

// MARK: - Part 3: SwiftUI Views

// MARK: Glass ViewModifier

private struct AMENGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                Color(white: 0.88).opacity(0.5),
                                lineWidth: 0.5
                            )
                    )
            )
    }
}

private extension View {
    func amenGlassCard(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(AMENGlassCard(cornerRadius: cornerRadius))
    }
}

// Convenience glass capsule button style
private struct GlassCapsuleButton: View {
    let label: String
    let action: () -> Void
    var isBold: Bool = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(isBold ? AMENFont.semiBold(14) : AMENFont.regular(14))
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .amenGlassCard(cornerRadius: 100)
        }
    }
}

// MARK: WellnessSoftNudgeCard

struct WellnessSoftNudgeCard: View {

    @StateObject private var service = WellnessRiskService.shared
    @State private var dismissed = false
    var onTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        if !dismissed {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundColor(Color(white: 0.45))
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Take a moment")
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(.black)
                    Text("Would support be helpful right now?")
                        .font(AMENFont.regular(13))
                        .foregroundColor(Color(white: 0.45))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        onTap?()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(white: 0.45))
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dismissed = true
                        }
                        service.dismissIntervention(feedback: .notRelevant)
                        onDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(white: 0.55))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .amenGlassCard(cornerRadius: 16)
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: WellnessReflectionPromptCard

struct WellnessReflectionPromptCard: View {

    @StateObject private var service = WellnessRiskService.shared
    var onOpenChurchNotes: (() -> Void)?
    var onOpenBerean: (() -> Void)?
    var onSkip: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Want to write this out first?")
                .font(AMENFont.semiBold(14))
                .foregroundColor(.black)

            Text("Church Notes or Berean can help you process.")
                .font(AMENFont.regular(13))
                .foregroundColor(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                GlassCapsuleButton(label: "Open Church Notes") {
                    onOpenChurchNotes?()
                    service.recordHelpSeeking()
                }

                GlassCapsuleButton(label: "Ask Berean") {
                    onOpenBerean?()
                    service.recordHelpSeeking()
                }

                GlassCapsuleButton(label: "Skip") {
                    service.dismissIntervention(feedback: .notRelevant)
                    onSkip?()
                }
            }
        }
        .padding(16)
        .amenGlassCard(cornerRadius: 16)
        .padding(.horizontal, 16)
    }
}

// MARK: SupportChoiceRow

struct SupportChoiceRow: View {
    let domain: SupportDomain
    var onSelect: ((SupportDomain) -> Void)?

    var body: some View {
        Button {
            onSelect?(domain)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: domain.icon)
                    .font(.system(size: 18))
                    .foregroundColor(Color(white: 0.45))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.displayName)
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(.black)
                    Text(domain.resourceSubtext)
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.65))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .amenGlassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: WellnessSupportSheet

struct WellnessSupportSheet: View {

    @StateObject private var service = WellnessRiskService.shared
    @Environment(\.dismiss) private var dismiss

    var domains: [SupportDomain]
    var onSelectDomain: ((SupportDomain) -> Void)?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You deserve support.")
                            .font(AMENFont.bold(20))
                            .foregroundColor(.black)

                        Text("What kind of help would be most useful right now?")
                            .font(AMENFont.regular(15))
                            .foregroundColor(Color(white: 0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    // Domain rows
                    VStack(spacing: 10) {
                        ForEach(domains) { domain in
                            SupportChoiceRow(domain: domain) { selected in
                                service.recordHelpSeeking()
                                onSelectDomain?(selected)
                            }
                        }
                    }

                    // Dismiss
                    HStack {
                        Spacer()
                        GlassCapsuleButton(label: "Dismiss") {
                            service.dismissIntervention(feedback: .notRelevant)
                            dismiss()
                        }
                        Spacer()
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
            }
        }
    }
}

// MARK: WellnessCrisisSheet

struct WellnessCrisisSheet: View {

    @StateObject private var service = WellnessRiskService.shared
    @Environment(\.dismiss) private var dismiss

    var onOpenBerean: (() -> Void)?
    var onFindChurch: (() -> Void)?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 10) {
                        Text("You're not alone.")
                            .font(AMENFont.bold(28))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)

                        Text("Take a breath. Choose what would help most right now.")
                            .font(AMENFont.regular(16))
                            .foregroundColor(Color(white: 0.45))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 20)

                    // Three large choice cards
                    VStack(spacing: 14) {
                        CrisisChoiceCard(
                            icon: "heart.fill",
                            title: "Emotional support",
                            subtitle: "Talk through what you're feeling"
                        ) {
                            service.recordHelpSeeking()
                        }

                        CrisisChoiceCard(
                            icon: "hands.and.sparkles.fill",
                            title: "Practical help",
                            subtitle: "Resources for real-world needs"
                        ) {
                            service.recordHelpSeeking()
                        }

                        CrisisChoiceCard(
                            icon: "phone.fill",
                            title: "Urgent crisis help",
                            subtitle: "988 — Call or text, free & confidential"
                        ) {
                            service.recordHelpSeeking()
                            if let url = URL(string: "tel://988") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }

                    // Smaller options
                    VStack(spacing: 10) {
                        GlassCapsuleButton(label: "Talk to Berean") {
                            service.recordHelpSeeking()
                            onOpenBerean?()
                        }

                        GlassCapsuleButton(label: "Find a church near me") {
                            service.recordHelpSeeking()
                            onFindChurch?()
                        }

                        Button {
                            service.dismissIntervention(feedback: .notRelevant)
                            dismiss()
                        } label: {
                            Text("Close for now")
                                .font(AMENFont.regular(14))
                                .foregroundColor(Color(white: 0.55))
                        }
                    }

                    // Footer
                    Text("This is not a medical emergency service. If you are in immediate danger, call 911.")
                        .font(AMENFont.regular(11))
                        .foregroundColor(Color(white: 0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// Reusable large crisis card
private struct CrisisChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(Color(white: 0.45))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AMENFont.semiBold(16))
                        .foregroundColor(.black)
                    Text(subtitle)
                        .font(AMENFont.regular(13))
                        .foregroundColor(Color(white: 0.55))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.65))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 0)
            .frame(height: 88)
            .amenGlassCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: WellnessUrgentEscalationView

struct WellnessUrgentEscalationView: View {

    @StateObject private var service = WellnessRiskService.shared
    @Environment(\.dismiss) private var dismiss

    var onOpenBerean: (() -> Void)?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 16)

                    // Header — calm, no alarm colors
                    VStack(spacing: 10) {
                        Text("Support is available right now.")
                            .font(AMENFont.bold(24))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)

                        Text("If you're in a crisis, you don't have to face it alone.")
                            .font(AMENFont.regular(15))
                            .foregroundColor(Color(white: 0.45))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Primary action — black capsule
                    Button {
                        service.recordHelpSeeking()
                        if let url = URL(string: "tel://988") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Call or Text 988")
                            .font(AMENFont.semiBold(16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                Capsule().fill(Color.black)
                            )
                    }
                    .padding(.horizontal, 24)

                    // Secondary options
                    VStack(spacing: 12) {
                        GlassCapsuleButton(label: "Text HOME to 741741") {
                            service.recordHelpSeeking()
                            if let url = URL(string: "sms://741741&body=HOME") {
                                UIApplication.shared.open(url)
                            }
                        }

                        GlassCapsuleButton(label: "Call 911 if in immediate danger") {
                            if let url = URL(string: "tel://911") {
                                UIApplication.shared.open(url)
                            }
                        }

                        GlassCapsuleButton(label: "Talk to Berean") {
                            service.recordHelpSeeking()
                            onOpenBerean?()
                        }

                        Button {
                            service.dismissIntervention(feedback: .notRelevant)
                            dismiss()
                        } label: {
                            Text("Close")
                                .font(AMENFont.regular(14))
                                .foregroundColor(Color(white: 0.55))
                        }
                    }

                    // Footer
                    Text("988 is the US Suicide & Crisis Lifeline. Outside the US, please contact your local crisis line.")
                        .font(AMENFont.regular(11))
                        .foregroundColor(Color(white: 0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: WellnessFeedAdjustmentCard

struct WellnessFeedAdjustmentCard: View {
    @State private var showingExplanation = false

    var body: some View {
        // Subtle opt-in pill — the feed adjustment itself is invisible
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.45))

            Text("Showing calmer content")
                .font(AMENFont.regular(12))
                .foregroundColor(Color(white: 0.45))

            Text("· Why?")
                .font(AMENFont.semiBold(12))
                .foregroundColor(Color(white: 0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .amenGlassCard(cornerRadius: 100)
        .onTapGesture {
            showingExplanation = true
        }
        .sheet(isPresented: $showingExplanation) {
            FeedAdjustmentExplanationSheet()
                .presentationDetents([.medium])
        }
    }
}

private struct FeedAdjustmentExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("Why calmer content?")
                    .font(AMENFont.bold(20))
                    .foregroundColor(.black)

                Text("AMEN noticed you've been scrolling through content that makes comparison or heavy feelings more likely. We've quietly adjusted your feed to show more grounding, reflective, and local content for a while.\n\nThis is not about you doing anything wrong. It's about your feed working for you, not against you.\n\nYour regular feed returns automatically.")
                    .font(AMENFont.regular(15))
                    .foregroundColor(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    GlassCapsuleButton(label: "Got it") {
                        dismiss()
                    }
                    Spacer()
                }
            }
            .padding(28)
        }
    }
}

// MARK: WellnessComparisonHarmBanner

struct WellnessComparisonHarmBanner: View {

    @StateObject private var feedMode = WellnessFeedModeService.shared
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.45))

                Text("Want to switch to a calmer feed for a bit?")
                    .font(AMENFont.regular(13))
                    .foregroundColor(Color(white: 0.35))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        feedMode.activateMode(.comparisonReset, durationHours: 2)
                        withAnimation { dismissed = true }
                    } label: {
                        Text("Yes")
                            .font(AMENFont.semiBold(13))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .amenGlassCard(cornerRadius: 100)
                    }

                    Button {
                        withAnimation { dismissed = true }
                    } label: {
                        Text("Not now")
                            .font(AMENFont.regular(13))
                            .foregroundColor(Color(white: 0.55))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .amenGlassCard(cornerRadius: 16)
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - WellnessRiskOverlay

struct WellnessRiskOverlay: View {
    @StateObject private var service = WellnessRiskService.shared
    @State private var activeSheet: ActiveSheet?
    @State private var showUrgentEscalation = false

    private enum ActiveSheet: Identifiable {
        case support
        case crisis
        case churchNotes
        case berean
        case findChurch

        var id: String {
            switch self {
            case .support: return "support"
            case .crisis: return "crisis"
            case .churchNotes: return "churchNotes"
            case .berean: return "berean"
            case .findChurch: return "findChurch"
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if service.pendingIntervention == .feedAdjustment {
                WellnessFeedAdjustmentCard()
            }

            if service.pendingIntervention == .softNudge {
                WellnessSoftNudgeCard(onTap: {
                    activeSheet = .support
                })
            }

            if service.pendingIntervention == .reflectionPrompt {
                WellnessReflectionPromptCard(
                    onOpenChurchNotes: {
                        service.dismissIntervention(feedback: .helpful)
                        activeSheet = .churchNotes
                    },
                    onOpenBerean: {
                        service.dismissIntervention(feedback: .helpful)
                        activeSheet = .berean
                    },
                    onSkip: {
                        service.dismissIntervention(feedback: .notRelevant)
                    }
                )
            }

            if service.currentRiskState.comparisonHarmScore > 0.55 {
                WellnessComparisonHarmBanner()
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: service.pendingIntervention)
        .onChange(of: service.pendingIntervention) { _, newValue in
            switch newValue {
            case .supportSheet:
                activeSheet = .support
            case .crisisSheet:
                activeSheet = .crisis
            case .urgentEscalation:
                showUrgentEscalation = true
            default:
                break
            }
        }
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            switch sheet {
            case .support:
                WellnessSupportSheet(
                    domains: supportDomains,
                    onSelectDomain: { _ in
                        service.dismissIntervention(feedback: .helpful)
                        activeSheet = nil
                    }
                )
                .presentationDetents([.medium, .large])
            case .crisis:
                WellnessCrisisSheet(
                    onOpenBerean: {
                        activeSheet = .berean
                    },
                    onFindChurch: {
                        activeSheet = .findChurch
                    }
                )
                .presentationDetents([.large])
            case .churchNotes:
                ChurchNotesView()
            case .berean:
                BereanAIAssistantView(initialQuery: "I need support")
            case .findChurch:
                FindChurchView()
            }
        }
        .fullScreenCover(isPresented: $showUrgentEscalation, onDismiss: {
            service.dismissIntervention(feedback: .helpful)
        }) {
            WellnessUrgentEscalationView()
        }
    }

    private var supportDomains: [SupportDomain] {
        let domains = service.currentRiskState.recommendedSupportDomains
        return domains.isEmpty ? SupportDomain.allCases : domains
    }

    private func handleSheetDismiss() {
        switch service.pendingIntervention {
        case .supportSheet, .crisisSheet:
            service.dismissIntervention(feedback: .notRelevant)
        default:
            break
        }
    }
}

// MARK: - Part 4: WellnessFeedModeService

enum WellnessFeedMode: String {
    case standard        // default
    case nourish         // more grounding, reflective, local content
    case lowStimulation  // fewer high-arousal clips
    case comparisonReset // suppress body/wealth/status content temporarily
    case sabbath         // Church Notes + Resources only
}

@MainActor
final class WellnessFeedModeService: ObservableObject {

    static let shared = WellnessFeedModeService()

    @Published var activeMode: WellnessFeedMode = .standard
    @Published var modeSetAt: Date?
    @Published var modeDurationHours: Int = 2

    private init() {}

    func activateMode(_ mode: WellnessFeedMode, durationHours: Int) {
        activeMode = mode
        modeSetAt = Date()
        modeDurationHours = durationHours
    }

    func deactivate() {
        activeMode = .standard
        modeSetAt = nil
    }

    var modeLabel: String {
        guard isActive, let setAt = modeSetAt else { return "" }
        let elapsed = Date().timeIntervalSince(setAt)
        let totalSeconds = Double(modeDurationHours) * 3600
        let remaining = max(totalSeconds - elapsed, 0)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        let modeName: String
        switch activeMode {
        case .standard:        modeName = "Standard"
        case .nourish:         modeName = "Nourish"
        case .lowStimulation:  modeName = "Low Stimulation"
        case .comparisonReset: modeName = "Comparison Reset"
        case .sabbath:         modeName = "Sabbath"
        }

        if hours > 0 {
            return "\(modeName) Mode active · \(hours)h \(minutes)m remaining"
        } else {
            return "\(modeName) Mode active · \(minutes)m remaining"
        }
    }

    var isActive: Bool {
        guard activeMode != .standard, let setAt = modeSetAt else { return false }
        let elapsed = Date().timeIntervalSince(setAt)
        let totalSeconds = Double(modeDurationHours) * 3600
        if elapsed >= totalSeconds {
            // Auto-expire
            Task { @MainActor in deactivate() }
            return false
        }
        return true
    }
}

// MARK: - Previews

struct WellnessRiskLayer_Previews: PreviewProvider {
    static var previews: some View {
        Group {

            // 1. Soft nudge card
            ZStack {
                Color.white.ignoresSafeArea()
                VStack {
                    WellnessSoftNudgeCard()
                    Spacer()
                }
                .padding(.top, 40)
            }
            .previewDisplayName("Soft Nudge Card")

            // 2. Reflection prompt card
            ZStack {
                Color.white.ignoresSafeArea()
                VStack {
                    WellnessReflectionPromptCard()
                    Spacer()
                }
                .padding(.top, 40)
            }
            .previewDisplayName("Reflection Prompt Card")

            // 3. Support sheet
            WellnessSupportSheet(
                domains: [
                    .emotionalSupport,
                    .therapyCounseling,
                    .lonelinessCommunity,
                    .prayerPastoralCare,
                    .financialHelp
                ]
            )
            .previewDisplayName("Support Sheet")

            // 4. Crisis sheet
            WellnessCrisisSheet()
                .previewDisplayName("Crisis Sheet")

            // 5. Urgent escalation
            WellnessUrgentEscalationView()
                .previewDisplayName("Urgent Escalation")

            // 6. Feed adjustment pill
            ZStack {
                Color(white: 0.96).ignoresSafeArea()
                VStack {
                    WellnessFeedAdjustmentCard()
                        .padding(.top, 60)
                    Spacer()
                }
            }
            .previewDisplayName("Feed Adjustment Pill")

            // 7. Comparison harm banner
            ZStack {
                Color.white.ignoresSafeArea()
                VStack {
                    WellnessComparisonHarmBanner()
                        .padding(.top, 40)
                    Spacer()
                }
            }
            .previewDisplayName("Comparison Harm Banner")
        }
    }
}

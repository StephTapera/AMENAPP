// JobSafetyEngine.swift
// AMENAPP
//
// Job-specific safety evaluation layer.
// Wraps UnifiedSafetyGate for general content safety, and adds
// domain-specific fraud/scam/exploitation detection for job listings,
// applications, and recruiter profiles.
//
// All detection is on-device (regex + keyword heuristics).
// No raw text is stored; only decision codes are logged.

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Job Safety Decision

enum JobSafetyDecision: Equatable {
    case allow
    case warn(message: String)
    case deRank(reason: String)
    case requireVerification(reason: String)
    case restrictMessaging(reason: String)
    case hide(reason: String)
    case block(reason: String)
    case manualReview(reason: String)

    var isAllowed: Bool {
        switch self {
        case .allow, .warn: return true
        default: return false
        }
    }

    var displayMessage: String? {
        switch self {
        case .warn(let msg):                return msg
        case .requireVerification(let r):  return "Verification required: \(r)"
        case .restrictMessaging(let r):    return "Messaging restricted: \(r)"
        case .hide(let r):                 return "Hidden from discovery: \(r)"
        case .block(let r):                return "This content cannot be published: \(r)"
        case .manualReview(let r):         return "Sent for review: \(r)"
        default:                           return nil
        }
    }
}

// MARK: - Scam Signal

enum ScamSignal: String {
    case advanceFee             = "advance_fee"
    case guaranteedIncome       = "guaranteed_income"
    case requestsPersonalBankInfo = "requests_bank_info"
    case urgentHiring           = "urgent_hiring"
    case tooGoodToBeTrue        = "too_good_to_be_true"
    case vagueDescription       = "vague_description"
    case requestsMoney          = "requests_money"
    case offPlatformPayment     = "off_platform_payment"
    case predatoryReligious     = "predatory_religious"
    case exploitativeVolunteer  = "exploitative_volunteer"
    case traffickingIndicators  = "trafficking_indicators"
    case noContactInfo          = "no_contact_info"
    case unverifiedHighSalary   = "unverified_high_salary"
}

// MARK: - Recruiter Trust Level

enum RecruiterTrustLevel {
    case trusted        // verified, high response rate, established history
    case standard       // unverified but no red flags
    case unverified     // no verification, limited history
    case suspicious     // multiple flags or scam signals detected
    case blocked        // moderation action applied

    var canMessageCandidates: Bool {
        self == .trusted || self == .standard
    }

    var requiresDisclosure: Bool {
        self == .unverified || self == .suspicious
    }
}

// MARK: - Safety Score Result

struct JobSafetyScore {
    var score: Double           // 0.0–1.0 (higher = safer)
    var signals: [ScamSignal]
    var isSuspicious: Bool { score < 0.5 || signals.count >= 2 }
}

// MARK: - JobSafetyEngine

@MainActor
final class JobSafetyEngine {
    static let shared = JobSafetyEngine()

    private let db = Firestore.firestore()
    private var cachedDecisions: [String: (JobSafetyDecision, Date)] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 minutes

    private init() {}

    // MARK: - Public API

    /// Evaluates a job listing before it is published to Firestore.
    func evaluateJobPosting(_ listing: JobListing) -> JobSafetyDecision {
        let cacheKey = "listing_\(listing.title)_\(listing.employerId)"
        if let cached = cachedDecisions[cacheKey], Date().timeIntervalSince(cached.1) < cacheTTL {
            return cached.0
        }

        var signals: [ScamSignal] = []
        let textToAnalyze = "\(listing.title) \(listing.description) \(listing.requirements.joined(separator: " "))"

        // Run all detectors
        signals.append(contentsOf: detectScamPatterns(textToAnalyze))
        if detectAdvanceFeeScam(textToAnalyze) { signals.append(.advanceFee) }
        if detectPredatoryReligiousManipulation(textToAnalyze) { signals.append(.predatoryReligious) }
        if detectTraffickingSignals(textToAnalyze) { signals.append(.traffickingIndicators) }
        if detectExploitativeVolunteer(listing) { signals.append(.exploitativeVolunteer) }
        if detectOffPlatformPaymentScam(textToAnalyze) { signals.append(.offPlatformPayment) }
        if detectUnverifiedHighSalary(listing) { signals.append(.unverifiedHighSalary) }
        if detectVagueDescription(listing.description) { signals.append(.vagueDescription) }

        let decision = mapSignalsToDecision(signals, isVolunteer: listing.jobType == .volunteer)
        cachedDecisions[cacheKey] = (decision, Date())
        return decision
    }

    /// Evaluates application text (cover note, screening answers) before submission.
    func evaluateApplication(text: String, applicantId: String) -> JobSafetyDecision {
        // Check for PII exfiltration attempts or off-platform requests embedded in application text
        if detectOffPlatformPaymentScam(text) {
            return .warn(message: "Your application contains content that may violate our policies. Please remove any requests for off-platform communication or payments.")
        }

        let lower = text.lowercased()
        // Block if application contains threat signals
        let threatPhrases = ["i will harm", "i'll find you", "you'll regret", "threatening"]
        for phrase in threatPhrases where lower.contains(phrase) {
            return .block(reason: "Threatening language detected in application.")
        }

        return .allow
    }

    /// Computes a 0.0–1.0 safety score for ranking (lower = less safe = rank lower).
    func computeJobSafetyScore(_ listing: JobListing) -> Double {
        let result = internalSafetyScore(
            text: "\(listing.title) \(listing.description)",
            isVolunteer: listing.jobType == .volunteer,
            salaryMax: listing.salaryMax,
            isVerified: listing.employerVerified
        )
        return result.score
    }

    /// Computes a 0.0–1.0 safety score for an employer profile.
    func computeEmployerSafetyScore(_ employer: EmployerProfile) -> Double {
        var score = 1.0

        // Verification boost
        if employer.isVerified { score = min(score + 0.10, 1.0) }

        // Moderation history penalty
        switch employer.moderationState {
        case .active: break
        case .underReview: score -= 0.20
        case .warned: score -= 0.30
        case .restricted: score -= 0.50
        case .suspended: return 0.0
        }

        // Response rate quality signal
        if employer.responseRate < 0.30 { score -= 0.10 }

        // Low trust score penalty
        if employer.trustScore < 0.40 { score -= 0.15 }

        return max(0.0, min(score, 1.0))
    }

    /// Evaluates a recruiter profile's trust level.
    func evaluateRecruiterTrust(_ employer: EmployerProfile) -> RecruiterTrustLevel {
        switch employer.moderationState {
        case .suspended: return .blocked
        case .restricted: return .suspicious
        case .warned: return .suspicious
        default: break
        }

        if employer.isVerified && employer.trustScore >= 0.70 { return .trusted }
        if employer.trustScore >= 0.40 { return .standard }
        return .unverified
    }

    // MARK: - Scam Pattern Detection

    func detectScamPatterns(_ text: String) -> [ScamSignal] {
        var signals: [ScamSignal] = []
        let lower = text.lowercased()

        // Advance-fee fraud
        let advanceFeePatterns = [
            "send us money", "pay a fee", "registration fee", "training fee",
            "processing fee", "background check fee", "equipment deposit",
            "pay for your kit", "purchase your starter kit", "buy your materials"
        ]
        if advanceFeePatterns.contains(where: { lower.contains($0) }) {
            signals.append(.advanceFee)
        }

        // Guaranteed income scam
        let guaranteedIncomePatterns = [
            "guaranteed income", "earn $\\d+k per", "make money fast",
            "work from home and earn", "six figures guaranteed", "unlimited earning",
            "no experience \\.+ \\$", "easy money"
        ]
        for pattern in guaranteedIncomePatterns where lower.contains(pattern.replacingOccurrences(of: "\\.", with: ".").replacingOccurrences(of: "\\d+", with: "")) {
            signals.append(.guaranteedIncome)
            break
        }

        // Requests personal financial info
        let bankInfoPatterns = [
            "bank account number", "routing number", "social security",
            "ssn required", "wire transfer", "western union", "zelle payment",
            "cashapp", "crypto payment", "bitcoin payment"
        ]
        if bankInfoPatterns.contains(where: { lower.contains($0) }) {
            signals.append(.requestsPersonalBankInfo)
        }

        // Urgent hiring scam patterns
        let urgentPatterns = [
            "urgent hire", "immediate start", "must start today",
            "hiring immediately no interview", "no interview needed",
            "hired on the spot"
        ]
        if urgentPatterns.contains(where: { lower.contains($0) }) {
            signals.append(.urgentHiring)
        }

        // Requests money patterns
        let requestsMoneyPatterns = [
            "pay us", "send payment", "payment required to start",
            "refundable deposit", "you will be reimbursed after"
        ]
        if requestsMoneyPatterns.contains(where: { lower.contains($0) }) {
            signals.append(.requestsMoney)
        }

        return Array(Set(signals))  // deduplicate
    }

    func detectAdvanceFeeScam(_ text: String) -> Bool {
        let lower = text.lowercased()
        let advanceFeeKeywords = [
            "pay a fee before", "registration fee required", "initial investment required",
            "purchase equipment from us", "buy your starter", "pay for training materials",
            "money order", "gift card payment", "itunes card", "google play card"
        ]
        return advanceFeeKeywords.contains(where: { lower.contains($0) })
    }

    func detectPredatoryReligiousManipulation(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Patterns that weaponize faith for exploitation
        let manipulationPatterns = [
            "god told me you should work for free",
            "it's your spiritual duty to not ask for pay",
            "true believers don't need compensation",
            "faith-based salary means no pay",
            "serving god means you won't be paid",
            "if you're truly called you won't need money",
            "submit to our spiritual authority",
            "must tithe 20% of earnings back to us",
            "required to sign over your financial blessings"
        ]
        return manipulationPatterns.contains(where: { lower.contains($0) })
    }

    func detectTraffickingSignals(_ text: String) -> Bool {
        let lower = text.lowercased()
        // High-risk trafficking/grooming indicators
        let traffickingKeywords = [
            "travel with us for free", "we'll provide housing and meals",
            "live-in position with exclusive access", "companion position",
            "escort duties", "entertainment role requiring travel alone",
            "no questions asked work", "discretion required",
            "private arrangement", "model position no experience needed contact privately"
        ]
        return traffickingKeywords.contains(where: { lower.contains($0) })
    }

    func detectExploitativeVolunteer(_ listing: JobListing) -> Bool {
        // Volunteer roles that look like unpaid labor extraction
        guard listing.jobType == .volunteer || listing.compensationType == .volunteer else {
            return false
        }

        let description = listing.description.lowercased()
        let exploitativePatterns = [
            "40 hours per week", "full-time volunteer",
            "mandatory attendance 5 days", "required to be available 24/7",
            "unpaid but expected to", "no days off", "no vacation"
        ]

        let hasExploitativeLanguage = exploitativePatterns.contains(where: { description.contains($0) })
        let lacksNPOClassification = listing.classification != .churchMinistry && listing.classification != .missionOrg

        return hasExploitativeLanguage && lacksNPOClassification
    }

    func detectOffPlatformPaymentScam(_ text: String) -> Bool {
        let lower = text.lowercased()
        let offPlatformPatterns = [
            "contact me outside amen", "email me directly for payment",
            "pay via venmo only", "pay via cashapp only",
            "don't use amen to pay", "bypass the platform",
            "we'll pay you directly outside"
        ]
        return offPlatformPatterns.contains(where: { lower.contains($0) })
    }

    // MARK: - Additional Checks

    private func detectUnverifiedHighSalary(_ listing: JobListing) -> Bool {
        // Flag suspiciously high salaries from unverified employers
        guard !listing.employerVerified else { return false }
        guard let salaryMax = listing.salaryMax else { return false }
        // Flag if claiming >$200k/yr from unverified org
        if listing.salaryPeriod == .annual && salaryMax > 200_000 { return true }
        // Flag if claiming >$100/hr from unverified org
        if listing.salaryPeriod == .hourly && salaryMax > 100 { return true }
        return false
    }

    private func detectVagueDescription(_ description: String) -> Bool {
        let wordCount = description.split(separator: " ").count
        // Listings with <20 words in description are suspicious
        return wordCount < 20
    }

    // MARK: - Decision Mapping

    private func mapSignalsToDecision(_ signals: [ScamSignal], isVolunteer: Bool) -> JobSafetyDecision {
        // Critical signals -> block immediately
        let blockSignals: [ScamSignal] = [
            .traffickingIndicators, .advanceFee, .requestsPersonalBankInfo, .requestsMoney
        ]
        if signals.contains(where: { blockSignals.contains($0) }) {
            return .block(reason: "This listing contains content that violates AMEN safety policies.")
        }

        // High-severity -> manual review
        let reviewSignals: [ScamSignal] = [
            .predatoryReligious, .exploitativeVolunteer, .offPlatformPayment
        ]
        if signals.contains(where: { reviewSignals.contains($0) }) {
            return .manualReview(reason: "This listing has been flagged for review.")
        }

        // Multiple moderate signals -> require verification
        if signals.count >= 3 {
            return .requireVerification(reason: "Multiple risk signals detected. Employer verification required.")
        }

        // Moderate signals -> de-rank
        let deRankSignals: [ScamSignal] = [
            .guaranteedIncome, .urgentHiring, .unverifiedHighSalary, .tooGoodToBeTrue
        ]
        if signals.contains(where: { deRankSignals.contains($0) }) {
            return .deRank(reason: "This listing may contain misleading information.")
        }

        // Vague description warning
        if signals.contains(.vagueDescription) {
            return .warn(message: "Job descriptions should be detailed and clear to attract qualified candidates.")
        }

        return .allow
    }

    private func internalSafetyScore(
        text: String,
        isVolunteer: Bool,
        salaryMax: Double?,
        isVerified: Bool
    ) -> JobSafetyScore {
        var signals: [ScamSignal] = []
        signals.append(contentsOf: detectScamPatterns(text))
        if detectAdvanceFeeScam(text) { signals.append(.advanceFee) }
        if detectPredatoryReligiousManipulation(text) { signals.append(.predatoryReligious) }
        if detectTraffickingSignals(text) { signals.append(.traffickingIndicators) }
        if detectOffPlatformPaymentScam(text) { signals.append(.offPlatformPayment) }
        if detectVagueDescription(text) { signals.append(.vagueDescription) }

        var score = 1.0
        // Each signal reduces safety score
        score -= Double(signals.count) * 0.15
        // Verified employers get a bump
        if isVerified { score += 0.10 }
        score = max(0.0, min(score, 1.0))

        return JobSafetyScore(score: score, signals: signals)
    }
}

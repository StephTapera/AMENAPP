// SafetyOrchestrator.swift
// AMENAPP
//
// Unified safety coordination layer.
// Wires together: ContentRiskAnalyzer, BehavioralAwarenessEngine,
// CrisisDetectionService, ContentSafetyShieldService, ModerationService,
// BlockService, and the adaptive support UI layer.
//
// Architecture:
//   SafetyOrchestrator  ← single entry point for all safety decisions
//   ContentRiskAnalyzer ← text-based risk scoring (distress/violence/drugs/financial)
//   BehavioralAwarenessEngine ← session/scroll/dwell behavioral signals
//   AdaptiveSupportCoordinator ← decides which support surface to show
//   PreSubmissionSafetyGate ← validates content before publish
//
// Privacy: all behavioral signals are local/in-memory only.
// No raw behavioral data is sent to the server.
// Only aggregated support-state changes (checkIn triggered, etc.) are logged.

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Safety State

/// The current aggregate safety support state for the active user.
/// Used by AdaptiveSupportCoordinator to decide what UI to surface.
enum SafetySupportState: Int, Comparable, Equatable {
    case normal           = 0   // no action needed
    case awarenessActive  = 1   // gentle awareness — nothing surfaced unless asked
    case gentleCheckIn    = 2   // show optional soft check-in prompt
    case supportSurface   = 3   // surface support resources (prayer, grounding, help)
    case crisisRecommended = 4  // surface crisis resources prominently
    case crisisUrgent     = 5   // surface crisis help immediately + 988

    static func < (lhs: SafetySupportState, rhs: SafetySupportState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .normal:             return "Normal"
        case .awarenessActive:    return "Awareness Active"
        case .gentleCheckIn:      return "Gentle Check-In"
        case .supportSurface:     return "Support Surface"
        case .crisisRecommended:  return "Crisis Recommended"
        case .crisisUrgent:       return "Crisis Urgent"
        }
    }
}

// MARK: - Content Decision

/// The decision made about a piece of user-generated content.
struct SafetyContentDecision {
    enum Action {
        case allow              // publish as-is
        case allowWithWarning   // publish + show copy warning to author
        case holdForSoftReview  // show author "your post is being reviewed"
        case blockAndReview     // do not publish; queue for human review
        case blockImmediate     // do not publish; high-confidence violation
    }

    let action: Action
    let riskCategory: ContentRiskCategory
    let riskScore: Double          // 0.0 – 1.0
    let authorSupportState: SafetySupportState
    let moderatorReason: String    // internal, not user-facing
    let userFacingMessage: String? // if action != allow, shown to author
    let requiresHumanReview: Bool
    let logForAudit: Bool
}

// MARK: - Safety Orchestrator

/// Single entry point for all safety decisions in AMEN.
/// Lightweight — designed to be called inline without blocking the main thread.
@MainActor
final class SafetyOrchestrator: ObservableObject {
    static let shared = SafetyOrchestrator()

    // Sub-services (all singletons)
    private let contentRisk    = ContentRiskAnalyzer.shared
    private let behavioral     = BehavioralAwarenessEngine.shared
    private let crisisService  = CrisisDetectionService.shared
    private let db             = Firestore.firestore()

    /// Current user-facing support state — observed by ContentView/tab bar
    @Published var supportState: SafetySupportState = .normal

    /// The highest-priority support surface currently warranted
    @Published var pendingSupportSurface: SupportSurface?

    /// True while a content safety decision is being computed asynchronously
    @Published var isEvaluatingContent = false

    /// Handle for the current in-flight evaluation task — cancelled on re-entry
    private var evaluationTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Roll up behavioral state changes into support state
        behavioral.$sessionSignal
            .receive(on: RunLoop.main)
            .sink { [weak self] signal in
                self?.integrateSessionSignal(signal)
            }
            .store(in: &cancellables)
    }

    // MARK: - Pre-submission safety gate

    /// Call before publishing a post, comment, prayer request, or message.
    /// Returns synchronously if the local check is sufficient; the async path
    /// handles cloud review for higher-risk content.
    func evaluateBeforeSubmit(
        text: String,
        context: SafetyContentContext,
        completion: @escaping (SafetyContentDecision) -> Void
    ) {
        // P0 FIX: Cancel any in-flight evaluation before starting a new one.
        // Prevents the post button from being stuck when this is called rapidly.
        evaluationTask?.cancel()
        isEvaluatingContent = true

        evaluationTask = Task {
            // P0 FIX: 10-second timeout via withTaskGroup race.
            // If the local risk analysis or Firestore logging hangs, we fall through
            // to the safe default (.allow + logForAudit: true) rather than blocking forever.
            let decision: SafetyContentDecision = await withTaskGroup(
                of: SafetyContentDecision?.self,
                returning: SafetyContentDecision.self
            ) { group in
                // Worker: actual safety evaluation (hop to MainActor for isolated methods)
                group.addTask { @MainActor in
                    guard !Task.isCancelled else { return nil }
                    let risk = self.contentRisk.analyze(text: text, context: context)
                    return self.makeContentDecision(risk: risk, context: context)
                }
                // Watchdog: 10-second deadline
                group.addTask {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    return nil  // nil signals timeout
                }

                // Return whichever resolves first
                for await result in group {
                    if let decision = result {
                        group.cancelAll()
                        return decision
                    }
                }
                // Timeout path: fail closed — hold for review and flag for audit.
                // We never silently allow content when the safety gate hangs.
                return SafetyContentDecision(
                    action: .holdForSoftReview,
                    riskCategory: .none,
                    riskScore: 0,
                    authorSupportState: .gentleCheckIn,
                    moderatorReason: "Safety gate timed out — held for review",
                    userFacingMessage: "Your post is being reviewed. This usually takes just a moment.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            }

            guard !Task.isCancelled else { return }

            // For crisis-level content, also update the author's support state
            if decision.authorSupportState >= .crisisRecommended {
                await updateSupportState(to: decision.authorSupportState, reason: "pre-submit-crisis")
            }

            // Log high-risk decisions to Firestore for moderator review
            if decision.logForAudit {
                logSafetyEvent(
                    type: "pre_submit_flag",
                    category: decision.riskCategory.rawValue,
                    score: decision.riskScore,
                    context: context.rawValue,
                    action: "\(decision.action)"
                )
            }

            await MainActor.run {
                self.isEvaluatingContent = false
                completion(decision)
            }
        }
    }

    // MARK: - Passive content signal (feed / comments / messages)

    /// Call when displaying content authored by another user.
    /// Used to update behavioral awareness; never blocks rendering.
    func noteContentExposure(text: String, context: SafetyContentContext) {
        let risk = contentRisk.quickScan(text: text)
        behavioral.noteContentExposure(category: risk.primaryCategory, intensity: risk.totalScore)
    }

    // MARK: - Session signal integration

    func integrateSessionSignal(_ signal: SessionSignal) {
        let newState: SafetySupportState
        switch signal {
        case .normal:
            newState = .normal
        case .mildDistress:
            newState = max(supportState, .awarenessActive)
        case .repeatedHeavyContent:
            newState = max(supportState, .gentleCheckIn)
        case .distressedScrolling:
            newState = max(supportState, .gentleCheckIn)
        case .crisisContentDwell:
            newState = max(supportState, .supportSurface)
        case .elevatedConcern:
            newState = max(supportState, .crisisRecommended)
        }
        Task { await updateSupportState(to: newState, reason: "session-signal-\(signal)") }
    }

    // MARK: - Support state management

    func updateSupportState(to newState: SafetySupportState, reason: String) async {
        guard newState > supportState else { return }
        supportState = newState

        // Derive the appropriate support surface
        pendingSupportSurface = AdaptiveSupportCoordinator.surface(for: newState)
    }

    func clearSupportState() {
        supportState = .normal
        pendingSupportSurface = nil
    }

    func dismissPendingSurface() {
        pendingSupportSurface = nil
        // After dismissal, lower urgency slightly (user acknowledged)
        if supportState >= .supportSurface {
            supportState = .gentleCheckIn
        }
    }

    // MARK: - Content decision logic

    private func makeContentDecision(
        risk: ContentRiskResult,
        context: SafetyContentContext
    ) -> SafetyContentDecision {
        let score = risk.totalScore

        switch risk.primaryCategory {

        // ── Crisis / self-harm ───────────────────────────────────────────
        case .selfHarmCrisis:
            if score > 0.75 {
                return SafetyContentDecision(
                    action: .holdForSoftReview,
                    riskCategory: .selfHarmCrisis,
                    riskScore: score,
                    authorSupportState: .crisisUrgent,
                    moderatorReason: "High-confidence self-harm language: \(risk.matchedSignals.prefix(3).joined(separator: ", "))",
                    userFacingMessage: "We noticed something that concerns us. Your post has been paused — please know you're not alone. Would you like to talk to someone right now?",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            } else if score > 0.45 {
                return SafetyContentDecision(
                    action: .allowWithWarning,
                    riskCategory: .selfHarmCrisis,
                    riskScore: score,
                    authorSupportState: .crisisRecommended,
                    moderatorReason: "Moderate distress / self-harm signal",
                    userFacingMessage: nil,
                    requiresHumanReview: false,
                    logForAudit: true
                )
            }

        // ── Violence / threats ───────────────────────────────────────────
        case .violenceThreat:
            if score > 0.80 {
                return SafetyContentDecision(
                    action: .blockAndReview,
                    riskCategory: .violenceThreat,
                    riskScore: score,
                    authorSupportState: .crisisRecommended,
                    moderatorReason: "High-confidence threat/violence: \(risk.matchedSignals.prefix(3).joined(separator: ", "))",
                    userFacingMessage: "This content couldn't be posted. If you're going through something difficult, support is available.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            } else if score > 0.55 {
                return SafetyContentDecision(
                    action: .holdForSoftReview,
                    riskCategory: .violenceThreat,
                    riskScore: score,
                    authorSupportState: .supportSurface,
                    moderatorReason: "Possible threat or violent language — pending review",
                    userFacingMessage: "Your post is being reviewed before it's shared.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            }

        // ── Illegal / drug / trafficking ─────────────────────────────────
        case .illegalActivity:
            if score > 0.70 {
                return SafetyContentDecision(
                    action: .blockImmediate,
                    riskCategory: .illegalActivity,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "High-confidence illegal activity pattern: \(risk.matchedSignals.prefix(3).joined(separator: ", "))",
                    userFacingMessage: "This content violated our community guidelines and couldn't be posted.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            } else if score > 0.45 {
                return SafetyContentDecision(
                    action: .holdForSoftReview,
                    riskCategory: .illegalActivity,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Possible illegal activity — pending review",
                    userFacingMessage: "Your post is being reviewed before it's shared.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            }

        // ── Financial distress (never block — route to support) ──────────
        case .financialDistress:
            if score > 0.60 {
                return SafetyContentDecision(
                    action: .allow,
                    riskCategory: .financialDistress,
                    riskScore: score,
                    authorSupportState: .supportSurface,
                    moderatorReason: "Financial distress signal — support surface recommended",
                    userFacingMessage: nil,
                    requiresHumanReview: false,
                    logForAudit: false
                )
            }

        // ── Emotional distress / sadness ─────────────────────────────────
        case .emotionalDistress:
            if score > 0.65 {
                return SafetyContentDecision(
                    action: .allow,
                    riskCategory: .emotionalDistress,
                    riskScore: score,
                    authorSupportState: .gentleCheckIn,
                    moderatorReason: "Distress/sadness signal — gentle check-in recommended",
                    userFacingMessage: nil,
                    requiresHumanReview: false,
                    logForAudit: false
                )
            }

        // ── Harassment / exploitation ─────────────────────────────────────
        case .harassmentExploitation:
            if score > 0.75 {
                return SafetyContentDecision(
                    action: .blockAndReview,
                    riskCategory: .harassmentExploitation,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Harassment or exploitation language",
                    userFacingMessage: "This content couldn't be posted. It may violate our safety guidelines.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            }

        // ── Grooming / trafficking / child safety ─────────────────────────────
        // Lowest tolerance — even moderate scores are blocked immediately.
        case .groomingTrafficking:
            if score > 0.50 {
                return SafetyContentDecision(
                    action: .blockImmediate,
                    riskCategory: .groomingTrafficking,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Grooming, trafficking, or child-exploitation language: \(risk.matchedSignals.prefix(3).joined(separator: ", "))",
                    userFacingMessage: "This content couldn't be posted. It may violate our community safety guidelines.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            } else if score > 0.28 {
                return SafetyContentDecision(
                    action: .blockAndReview,
                    riskCategory: .groomingTrafficking,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Possible grooming / predatory contact pattern — flagged for review",
                    userFacingMessage: "This content is being reviewed before it can be shared.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            }

        // ── Explicit sexual content ───────────────────────────────────────────
        case .explicitSexual:
            if score > 0.55 {
                return SafetyContentDecision(
                    action: .blockImmediate,
                    riskCategory: .explicitSexual,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Explicit sexual content",
                    userFacingMessage: "This content couldn't be posted. Explicit content isn't allowed on AMEN.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            } else if score > 0.35 {
                return SafetyContentDecision(
                    action: .blockAndReview,
                    riskCategory: .explicitSexual,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Possible explicit content — flagged for review",
                    userFacingMessage: "This content is being reviewed before it can be shared.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            }

        // ── Profanity / hate speech ───────────────────────────────────────────
        case .profanityHate:
            if score > 0.70 {
                return SafetyContentDecision(
                    action: .blockAndReview,
                    riskCategory: .profanityHate,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Hate speech or severe profanity",
                    userFacingMessage: "This content couldn't be posted. Please keep language respectful and uplifting.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            } else if score > 0.45 {
                return SafetyContentDecision(
                    action: .allowWithWarning,
                    riskCategory: .profanityHate,
                    riskScore: score,
                    authorSupportState: .awarenessActive,
                    moderatorReason: "Profanity detected — warning issued",
                    userFacingMessage: "Please keep language uplifting and respectful in this community.",
                    requiresHumanReview: false,
                    logForAudit: false
                )
            }

        // ── Spam / scam / phishing ────────────────────────────────────────────
        case .spamScam:
            if score > 0.60 {
                return SafetyContentDecision(
                    action: .blockImmediate,
                    riskCategory: .spamScam,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Spam, scam, or phishing content: \(risk.matchedSignals.prefix(3).joined(separator: ", "))",
                    userFacingMessage: "This content couldn't be posted. It may violate our community guidelines.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            } else if score > 0.40 {
                return SafetyContentDecision(
                    action: .holdForSoftReview,
                    riskCategory: .spamScam,
                    riskScore: score,
                    authorSupportState: .normal,
                    moderatorReason: "Possible spam or scam content — held for review",
                    userFacingMessage: "Your post is being reviewed before it's shared.",
                    requiresHumanReview: true,
                    logForAudit: true
                )
            }

        default: break
        }

        // Default: allow
        return SafetyContentDecision(
            action: .allow,
            riskCategory: .none,
            riskScore: score,
            authorSupportState: .normal,
            moderatorReason: "Within acceptable threshold",
            userFacingMessage: nil,
            requiresHumanReview: false,
            logForAudit: false
        )
    }

    // MARK: - Audit logging (aggregated, no raw content stored)

    private func logSafetyEvent(
        type: String,
        category: String,
        score: Double,
        context: String,
        action: String
    ) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Log only category/score/context — never raw content
        let doc: [String: Any] = [
            "type": type,
            "category": category,
            "score": score,
            "context": context,
            "action": action,
            "timestamp": FieldValue.serverTimestamp()
        ]
        db.collection("safetyAuditLog")
            .document(uid)
            .collection("events")
            .addDocument(data: doc)
    }
}

// MARK: - Support Surface

enum SupportSurface: Equatable {
    case gentleCheckIn
    case pauseAndBreathe
    case prayerAndSupport
    case crisisHelpCard
    case financialHelpCard
    case fullCrisisUrgent

    var priority: Int {
        switch self {
        case .gentleCheckIn:     return 1
        case .pauseAndBreathe:   return 2
        case .prayerAndSupport:  return 3
        case .crisisHelpCard:    return 4
        case .financialHelpCard: return 3
        case .fullCrisisUrgent:  return 5
        }
    }
}

// MARK: - Adaptive Support Coordinator

enum AdaptiveSupportCoordinator {
    static func surface(for state: SafetySupportState) -> SupportSurface? {
        switch state {
        case .normal, .awarenessActive:   return nil
        case .gentleCheckIn:              return .gentleCheckIn
        case .supportSurface:             return .prayerAndSupport
        case .crisisRecommended:          return .crisisHelpCard
        case .crisisUrgent:               return .fullCrisisUrgent
        }
    }
}

//
//  SupportIntelligenceCoordinator.swift
//  AMENAPP
//
//  Shared facade for the production Resources Intelligence System.
//  Accepts cross-app text/context, classifies support need, persists normalized
//  signals, and returns deterministic route decisions the UI can render safely.
//

import Foundation
import FirebaseAuth

@MainActor
final class SupportIntelligenceCoordinator: ObservableObject {
    @MainActor static let shared: SupportIntelligenceCoordinator = {
        SupportIntelligenceCoordinator(
            classifier: RuleBasedSupportClassifier(),
            router: SupportCareRoutingEngine(),
            repository: InMemorySupportProfileRepository()
        )
    }()

    @Published private(set) var lastDecision: SupportRouteDecision?
    @Published private(set) var currentProfile: SupportProfile = .empty

    private let classifier: SupportClassifying
    private let router: SupportCareRouting
    private let repository: SupportProfileRepository

    init(
        classifier: SupportClassifying,
        router: SupportCareRouting,
        repository: SupportProfileRepository
    ) {
        self.classifier = classifier
        self.router = router
        self.repository = repository
    }

    func analyze(
        text: String,
        surface: SupportSurface,
        sourceId: String? = nil
    ) async -> SupportRouteDecision {
        let classification = classifier.classify(text: text, surface: surface)
        let userId = Auth.auth().currentUser?.uid ?? "local-user"

        let profile = (try? await repository.fetchProfile(userId: userId)) ?? currentProfile
        let contacts = (try? await repository.fetchTrustedContacts(userId: userId)) ?? []
        let decision = router.route(
            classification: classification,
            profile: profile,
            trustedContacts: contacts,
            surface: surface
        )

        let signal = SupportSignal.make(
            type: signalType(for: surface, classification: classification),
            sourceType: sourceType(for: surface),
            sourceId: sourceId,
            surface: surface,
            domains: classification.domains,
            themes: classification.detectedThemes,
            confidence: classification.confidence,
            reasonCode: classification.reasoningCodes.first ?? .noSignalsSufficient,
            reasoningCodes: classification.reasoningCodes,
            riskTier: classification.severity,
            helpingSomeoneElse: classification.helpingSomeoneElse
        )

        try? await repository.saveSignal(signal, userId: userId)

        var nextProfile = profile
        nextProfile.riskTier = classification.severity
        nextProfile.riskScore = max(profile.riskScore * 0.45, classification.confidence * 0.75)
        nextProfile.supportNeedScore = classification.severity == .none ? 0 : max(profile.supportNeedScore * 0.55, classification.confidence)
        nextProfile.activeThemes = classification.detectedThemes
        nextProfile.resourcePriority = classification.domains.map { $0.rawValue }
        nextProfile.recommendedDomains = classification.domains
        nextProfile.suggestedActions = decision.actions
        nextProfile.forFriendModeEligible = classification.helpingSomeoneElse
        nextProfile.givingSuppressed = decision.shouldSuppressGiving
        nextProfile.supportMode = supportMode(for: classification.severity)
        nextProfile.eligibleForPrompt = decision.promptType != nil
        nextProfile.lastAnalyzedAt = Date()
        nextProfile.updatedAt = Date()

        try? await repository.saveProfile(nextProfile, userId: userId)
        currentProfile = nextProfile
        lastDecision = decision
        return decision
    }

    func recordIntervention(
        surface: SupportSurface,
        decision: SupportRouteDecision,
        outcome: InterventionOutcome
    ) async {
        let userId = Auth.auth().currentUser?.uid ?? "local-user"
        let profile = (try? await repository.fetchProfile(userId: userId)) ?? currentProfile
        let intervention = SupportIntervention(
            id: UUID().uuidString,
            interventionType: interventionType(for: decision),
            promptType: decision.promptType,
            surface: surface,
            outcome: outcome,
            reasonCodes: decision.supportingReasons,
            riskTierAtTime: profile.riskTier,
            supportNeedScoreAtTime: profile.supportNeedScore,
            createdAt: Date(),
            resolvedAt: outcome == .shown ? nil : Date()
        )
        try? await repository.saveIntervention(intervention, userId: userId)
    }

    private func sourceType(for surface: SupportSurface) -> String {
        switch surface {
        case .postComposer, .postDraft, .postSubmitSheet, .postPublished:
            return "post"
        case .commentDraft, .commentPublished:
            return "comment"
        case .dmDraft, .dmThread:
            return "dm"
        case .note, .notesComposer:
            return "note"
        case .churchNote:
            return "churchNote"
        case .prayerComposer, .prayerRequest, .prayerRequestCard:
            return "prayer"
        case .bereanChat:
            return "berean"
        case .search:
            return "search"
        default:
            return "support"
        }
    }

    private func signalType(for surface: SupportSurface, classification: SupportClassification) -> SupportSignalType {
        if classification.helpingSomeoneElse {
            return .forFriendDetected
        }
        switch surface {
        case .postComposer, .postDraft, .postSubmitSheet, .postPublished:
            return .postSemanticDistress
        case .commentDraft, .commentPublished:
            return .commentSemanticDistress
        case .churchNote:
            return .churchNoteStress
        case .search:
            return .searchIntentSupport
        case .prayerComposer, .prayerRequest, .prayerRequestCard:
            return .prayerSupportNeed
        default:
            return .supportContentDwell
        }
    }

    private func supportMode(for tier: SupportRiskTier) -> SupportMode {
        switch tier {
        case .none, .low:
            return .quietMonitoring
        case .moderate:
            return .gentleSupport
        case .elevated:
            return .activeSupport
        case .acute:
            return .crisisReady
        }
    }

    private func interventionType(for decision: SupportRouteDecision) -> String {
        switch decision.routingLevel {
        case .none:
            return "no_action"
        case .gentleSupport:
            return "micro_prompt"
        case .guidedSupport:
            return "inline_support"
        case .immediateHelp:
            return "crisis_surface"
        }
    }
}

import Foundation

// MARK: - Social Constitution Engine

/// Deterministic constitutional evaluator for compiled social actions.
/// Rented model outputs may feed SocialContext, but they are never final authority here.
final class SocialConstitutionEngine {
    static let shared = SocialConstitutionEngine()

    private init() {}

    func evaluate(
        _ context: SocialContext,
        communityRules: [SocialSubConstitutionRule] = []
    ) -> SocialConstitutionVerdict {
        let platformVerdict = evaluatePlatformConstitution(context)
        let communityVerdict = evaluateCommunityRules(context, rules: communityRules)

        guard let communityVerdict else { return platformVerdict }

        // Article II is an absolute floor: no local policy may soften it.
        if platformVerdict.winningArticle == .articleIIMinorSafety,
           platformVerdict.decision >= communityVerdict.decision {
            return platformVerdict
        }

        if communityVerdict.decision > platformVerdict.decision {
            return communityVerdict.composed(withPlatformEvidence: platformVerdict.evidenceTrail)
        }

        return platformVerdict
    }

    private func evaluatePlatformConstitution(_ context: SocialContext) -> SocialConstitutionVerdict {
        let minorVerdict = evaluateMinorSafety(context)
        if minorVerdict.decision >= .holdReview { return minorVerdict }

        let crisisVerdict = evaluateCrisisAndAbuse(context, existingEvidence: minorVerdict.evidenceTrail)
        if crisisVerdict.decision >= .escalate { return crisisVerdict }

        let privacyVerdict = evaluatePrivacy(context, existingEvidence: crisisVerdict.evidenceTrail)
        if privacyVerdict.decision >= .holdReview { return privacyVerdict }

        let peaceVerdict = evaluateCommunityPeace(context, existingEvidence: privacyVerdict.evidenceTrail)
        if peaceVerdict.decision >= .requireEdit { return peaceVerdict }

        let truthVerdict = evaluateTruthAndClaims(context, existingEvidence: peaceVerdict.evidenceTrail)
        if truthVerdict.decision >= .nudge { return truthVerdict }

        let formationVerdict = evaluateFormation(context, existingEvidence: truthVerdict.evidenceTrail)
        if formationVerdict.decision >= .nudge { return formationVerdict }

        return .allow(evidence: formationVerdict.evidenceTrail)
    }

    private func evaluateMinorSafety(_ context: SocialContext) -> SocialConstitutionVerdict {
        var evidence: [SocialConstitutionVerdict.Evidence] = []

        if context.actor.ageBand == .under13 {
            evidence.append(.init(
                article: .articleIIMinorSafety,
                signal: "actor_under_13",
                weight: 1.0,
                summary: "The actor is below the minimum permitted age band."
            ))
            return verdict(
                .block,
                article: .articleIIMinorSafety,
                rationale: "Article II blocks social actions from under-minimum accounts.",
                evidence: evidence,
                humanReview: false,
                appealable: true
            )
        }

        if context.actor.ageBand == .unknown,
           context.surface.kind == .directMessage || context.content.containsMinor || context.risk.minorSafety >= .medium {
            evidence.append(.init(
                article: .articleIIMinorSafety,
                signal: "unknown_age_guard_surface",
                weight: 0.9,
                summary: "Age is unknown on a minor-adjacent or private surface."
            ))
            return verdict(
                .holdReview,
                article: .articleIIMinorSafety,
                rationale: "Article II fails closed when age is unknown in a private or minor-adjacent context.",
                evidence: evidence,
                humanReview: true,
                appealable: true
            )
        }

        if context.actor.ageBand == .minor && context.surface.visibility.isPublicLike {
            evidence.append(.init(
                article: .articleIIMinorSafety,
                signal: "minor_public_visibility",
                weight: 0.75,
                summary: "A minor-originated action is targeting a broad audience."
            ))
            return verdict(
                .requireEdit,
                article: .articleIIMinorSafety,
                rationale: "Article II requires a narrower audience for minor-originated actions.",
                evidence: evidence,
                humanReview: false,
                appealable: true
            )
        }

        if context.content.containsMinor && context.surface.visibility.isPublicLike {
            evidence.append(.init(
                article: .articleIIMinorSafety,
                signal: "minor_content_public_visibility",
                weight: 0.85,
                summary: "Content appears to include a minor and is aimed at a broad audience."
            ))
            return verdict(
                .holdReview,
                article: .articleIIMinorSafety,
                rationale: "Article II requires review before public distribution of minor-adjacent content.",
                evidence: evidence,
                humanReview: true,
                appealable: true
            )
        }

        if context.relationship.powerAsymmetry == .actorOverTarget,
           context.relationship.familiarity != .guardian,
           context.surface.kind == .directMessage,
           context.actor.hasElevatedAuthority {
            evidence.append(.init(
                article: .articleIIMinorSafety,
                signal: "authority_private_message",
                weight: 0.8,
                summary: "An elevated-authority actor is using a private surface."
            ))
            return verdict(
                .holdReview,
                article: .articleIIMinorSafety,
                rationale: "Article II requires additional review for authority-weighted private contact.",
                evidence: evidence,
                humanReview: true,
                appealable: true
            )
        }

        return .allow(evidence: evidence)
    }

    private func evaluateCrisisAndAbuse(
        _ context: SocialContext,
        existingEvidence: [SocialConstitutionVerdict.Evidence]
    ) -> SocialConstitutionVerdict {
        var evidence = existingEvidence

        if context.risk.selfHarm >= .critical || context.content.sensitivity == .critical {
            evidence.append(.init(
                article: .articleIHumanDignity,
                signal: "critical_crisis_signal",
                weight: 1.0,
                summary: "The action contains critical crisis or self-harm signals."
            ))
            return verdict(
                .escalate,
                article: .articleIHumanDignity,
                rationale: "Article I escalates active crisis signals to human-safe resources and blocks ordinary delivery.",
                evidence: evidence,
                humanReview: true,
                appealable: false
            )
        }

        if context.risk.abuse >= .high {
            evidence.append(.init(
                article: .articleIHumanDignity,
                signal: "abuse_or_exploitation_risk",
                weight: 0.9,
                summary: "The action carries high abuse or exploitation risk."
            ))
            return verdict(
                .block,
                article: .articleIHumanDignity,
                rationale: "Article I blocks abuse and exploitation risk before distribution.",
                evidence: evidence,
                humanReview: true,
                appealable: true
            )
        }

        return .allow(evidence: evidence)
    }

    private func evaluatePrivacy(
        _ context: SocialContext,
        existingEvidence: [SocialConstitutionVerdict.Evidence]
    ) -> SocialConstitutionVerdict {
        var evidence = existingEvidence

        if context.content.containsPII && context.surface.visibility.isPublicLike {
            evidence.append(.init(
                article: .articleIVPrivacyAndConsent,
                signal: "pii_public_surface",
                weight: 0.8,
                summary: "Potential personal information is present on a broad-audience surface."
            ))
            return verdict(
                .requireEdit,
                article: .articleIVPrivacyAndConsent,
                rationale: "Article IV requires removing personal information before broad distribution.",
                evidence: evidence,
                humanReview: false,
                appealable: true
            )
        }

        if context.risk.privacy >= .high {
            evidence.append(.init(
                article: .articleIVPrivacyAndConsent,
                signal: "high_privacy_risk",
                weight: 0.9,
                summary: "The privacy risk vector is high."
            ))
            return verdict(
                .holdReview,
                article: .articleIVPrivacyAndConsent,
                rationale: "Article IV holds high privacy-risk actions for review.",
                evidence: evidence,
                humanReview: true,
                appealable: true
            )
        }

        return .allow(evidence: evidence)
    }

    private func evaluateCommunityPeace(
        _ context: SocialContext,
        existingEvidence: [SocialConstitutionVerdict.Evidence]
    ) -> SocialConstitutionVerdict {
        var evidence = existingEvidence

        if context.risk.harassment >= .high || context.thread.conflictRisk >= .high {
            evidence.append(.init(
                article: .articleVICommunityPeace,
                signal: "high_conflict_or_harassment",
                weight: 0.75,
                summary: "The action is attached to high conflict or harassment risk."
            ))
            return verdict(
                .requireEdit,
                article: .articleVICommunityPeace,
                rationale: "Article VI requires de-escalation before the action continues.",
                evidence: evidence,
                humanReview: false,
                appealable: true
            )
        }

        if context.thread.temperature == .heated || context.risk.harassment == .medium {
            evidence.append(.init(
                article: .articleVICommunityPeace,
                signal: "heated_thread",
                weight: 0.55,
                summary: "The thread is trending heated or contains moderate harassment risk."
            ))
            return verdict(
                .nudge,
                article: .articleVICommunityPeace,
                rationale: "Article VI recommends a calming rewrite or pause.",
                evidence: evidence,
                humanReview: false,
                appealable: false
            )
        }

        return .allow(evidence: evidence)
    }

    private func evaluateTruthAndClaims(
        _ context: SocialContext,
        existingEvidence: [SocialConstitutionVerdict.Evidence]
    ) -> SocialConstitutionVerdict {
        var evidence = existingEvidence

        if context.risk.medical >= .high || context.risk.financial >= .high {
            evidence.append(.init(
                article: .articleIIITruthAndClaims,
                signal: "high_impact_claim",
                weight: 0.8,
                summary: "The action appears to include high-impact medical or financial claims."
            ))
            return verdict(
                .requireEdit,
                article: .articleIIITruthAndClaims,
                rationale: "Article III requires high-impact claims to be framed cautiously and non-authoritatively.",
                evidence: evidence,
                humanReview: false,
                appealable: true
            )
        }

        if context.content.containsScripture && context.risk.theological >= .medium {
            evidence.append(.init(
                article: .articleIIITruthAndClaims,
                signal: "theological_claim_uncertainty",
                weight: 0.45,
                summary: "The action contains theological or scripture-related claims that may need provenance."
            ))
            return verdict(
                .nudge,
                article: .articleIIITruthAndClaims,
                rationale: "Article III recommends adding context, citation, or humility markers around theological claims.",
                evidence: evidence,
                humanReview: false,
                appealable: false
            )
        }

        return .allow(evidence: evidence)
    }

    private func evaluateFormation(
        _ context: SocialContext,
        existingEvidence: [SocialConstitutionVerdict.Evidence]
    ) -> SocialConstitutionVerdict {
        var evidence = existingEvidence

        if context.action.verb == AmenActionVerb.startFundraiser.rawValue,
           context.actor.trustLevel == .new || context.actor.trustLevel == .unknown {
            evidence.append(.init(
                article: .articleVIIStewardship,
                signal: "new_actor_fundraiser",
                weight: 0.7,
                summary: "A low-trust or unknown-trust actor is starting a fundraiser."
            ))
            return verdict(
                .holdReview,
                article: .articleVIIStewardship,
                rationale: "Article VII requires review before financial solicitation by low-trust actors.",
                evidence: evidence,
                humanReview: true,
                appealable: true
            )
        }

        if context.thread.recentInterventionCount >= 2 {
            evidence.append(.init(
                article: .articleVFormationOverEngagement,
                signal: "calm_cap_pressure",
                weight: 0.55,
                summary: "The thread has already received repeated interventions."
            ))
            return verdict(
                .nudge,
                article: .articleVFormationOverEngagement,
                rationale: "Article V avoids repeated pressure and recommends a quieter path.",
                evidence: evidence,
                humanReview: false,
                appealable: false
            )
        }

        return .allow(evidence: evidence)
    }

    private func evaluateCommunityRules(
        _ context: SocialContext,
        rules: [SocialSubConstitutionRule]
    ) -> SocialConstitutionVerdict? {
        let activeRules = rules.filter { rule in
            rule.isRatified &&
            rule.appliesToSurfaceKinds.contains(context.surface.kind) &&
            rule.triggerSignals.contains { signal in
                context.content.text.localizedCaseInsensitiveContains(signal) ||
                context.content.claims.contains(where: { $0.localizedCaseInsensitiveContains(signal) })
            }
        }

        guard let strongest = activeRules.max(by: { $0.decision < $1.decision }) else { return nil }
        return verdict(
            strongest.decision,
            article: .communitySubConstitution,
            rationale: strongest.rationale,
            evidence: [
                .init(
                    article: .communitySubConstitution,
                    signal: strongest.articleName,
                    weight: 0.6,
                    summary: "Ratified community rule matched this action."
                )
            ],
            humanReview: strongest.decision >= .holdReview,
            appealable: true
        )
    }

    private func verdict(
        _ decision: SocialConstitutionVerdict.Decision,
        article: SocialConstitutionVerdict.Article,
        rationale: String,
        evidence: [SocialConstitutionVerdict.Evidence],
        humanReview: Bool,
        appealable: Bool
    ) -> SocialConstitutionVerdict {
        SocialConstitutionVerdict(
            decision: decision,
            winningArticle: article,
            rationale: rationale,
            evidenceTrail: evidence,
            requiresHumanReview: humanReview,
            isAppealable: appealable
        )
    }
}

private extension SocialConstitutionVerdict {
    func composed(withPlatformEvidence platformEvidence: [Evidence]) -> SocialConstitutionVerdict {
        SocialConstitutionVerdict(
            decision: decision,
            winningArticle: winningArticle,
            rationale: rationale,
            evidenceTrail: platformEvidence + evidenceTrail,
            requiresHumanReview: requiresHumanReview,
            isAppealable: isAppealable
        )
    }
}

// MARK: - Action Intelligence Compiler

struct SocialContextCompiler {
    static func compile(
        source: ActionIntelligenceSource,
        analysis: AmenIntentAnalysis? = nil,
        action: AmenActionSuggestion? = nil,
        actorAgeBand: SocialActorContext.AgeBand = .unknown,
        actorTrustLevel: SocialActorContext.TrustLevel = .unknown,
        moderationHistory: SocialActorContext.ModerationHistory = .empty,
        relationship: SocialRelationshipEdge = .unknown,
        thread: SocialThreadContext = .empty
    ) -> SocialContext {
        let text = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionKind = mapActionKind(surface: source.surface)
        let surface = SocialSurfaceContext(
            kind: mapSurfaceKind(source.surface),
            visibility: mapVisibility(source.surface, privacyTier: source.privacyTier),
            privacyTier: mapPrivacyTier(source.privacyTier),
            communityId: nil,
            organizationId: nil
        )
        let content = SocialContentContext(
            text: text,
            mediaCount: 0,
            claims: extractClaims(from: text, analysis: analysis),
            containsPII: containsPII(text),
            containsScripture: containsScripture(text, analysis: analysis),
            containsMinor: containsMinorSignal(text, analysis: analysis),
            sensitivity: mapSensitivity(analysis?.sensitivityLevel ?? .standard),
            languageCode: nil
        )
        let risk = buildRiskVector(text: text, analysis: analysis, content: content)
        let actorRole: SocialActorContext.Role = source.isCurrentUserLeader ? .leader : .member

        return SocialContext(
            action: SocialAction(
                kind: actionKind,
                verb: action?.verb.rawValue ?? analysis?.intentKind.rawValue ?? actionKind.rawValue,
                sourceId: source.id,
                targetId: source.authorId
            ),
            actor: SocialActorContext(
                userId: source.currentUserId,
                role: actorRole,
                ageBand: actorAgeBand,
                trustLevel: actorTrustLevel,
                moderationHistory: moderationHistory
            ),
            surface: surface,
            thread: thread,
            relationship: relationship,
            content: content,
            risk: risk
        )
    }

    static func compileAndEvaluate(
        source: ActionIntelligenceSource,
        analysis: AmenIntentAnalysis? = nil,
        action: AmenActionSuggestion? = nil,
        communityRules: [SocialSubConstitutionRule] = [],
        actorAgeBand: SocialActorContext.AgeBand = .unknown,
        actorTrustLevel: SocialActorContext.TrustLevel = .unknown,
        moderationHistory: SocialActorContext.ModerationHistory = .empty,
        relationship: SocialRelationshipEdge = .unknown,
        thread: SocialThreadContext = .empty
    ) -> (context: SocialContext, verdict: SocialConstitutionVerdict) {
        let context = compile(
            source: source,
            analysis: analysis,
            action: action,
            actorAgeBand: actorAgeBand,
            actorTrustLevel: actorTrustLevel,
            moderationHistory: moderationHistory,
            relationship: relationship,
            thread: thread
        )
        return (context, SocialConstitutionEngine.shared.evaluate(context, communityRules: communityRules))
    }

    private static func mapActionKind(surface: ActionIntelligenceSurface) -> SocialAction.Kind {
        switch surface {
        case .feedPost, .creatorPost, .organizationUpdate:
            return .post
        case .comment:
            return .comment
        case .directMessage:
            return .directMessage
        case .message, .groupChat:
            return .groupMessage
        case .amenRoom:
            return .callUtterance
        default:
            return .actionSuggestion
        }
    }

    private static func mapSurfaceKind(_ surface: ActionIntelligenceSurface) -> SocialSurfaceContext.Kind {
        switch surface {
        case .feedPost, .creatorPost, .organizationUpdate:
            return .feed
        case .comment:
            return .comment
        case .directMessage:
            return .directMessage
        case .message:
            return .group
        case .groupChat, .amenSpace:
            return .group
        case .amenRoom:
            return .room
        case .churchNote:
            return .actionThread
        default:
            return .unknown
        }
    }

    private static func mapVisibility(
        _ surface: ActionIntelligenceSurface,
        privacyTier: ActionIntelligencePrivacyTier
    ) -> SocialSurfaceContext.Visibility {
        switch privacyTier {
        case .publicCommunity:
            return .publicFeed
        case .confidential:
            return surface == .directMessage ? .private : .participants
        case .sacred:
            return .private
        }
    }

    private static func mapPrivacyTier(_ tier: ActionIntelligencePrivacyTier) -> SocialSurfaceContext.PrivacyTier {
        switch tier {
        case .publicCommunity: return .publicCommunity
        case .confidential: return .confidential
        case .sacred: return .sacred
        }
    }

    private static func mapSensitivity(_ sensitivity: CareSensitivityLevel) -> SocialContentContext.Sensitivity {
        switch sensitivity {
        case .standard: return .standard
        case .elevated: return .elevated
        case .high: return .high
        case .critical: return .critical
        }
    }

    private static func buildRiskVector(
        text: String,
        analysis: AmenIntentAnalysis?,
        content: SocialContentContext
    ) -> SocialRiskVector {
        let lower = text.lowercased()
        let crisis = containsAny(lower, ["suicide", "kill myself", "end my life", "self harm", "can't go on"]) ? SocialRiskVector.Level.critical : .none
        let harassment = containsAny(lower, ["idiot", "shut up", "hate you", "worthless", "loser"]) ? SocialRiskVector.Level.medium : .none
        let medical = containsAny(lower, ["diagnosis", "dosage", "prescription", "treatment", "symptom", "medicine"]) ? SocialRiskVector.Level.high : .none
        let financial = containsAny(lower, ["donate now", "wire money", "cashapp", "fundraiser", "investment", "guaranteed return"]) ? SocialRiskVector.Level.high : .none
        let minor = content.containsMinor ? SocialRiskVector.Level.medium : .none
        let privacy = content.containsPII ? SocialRiskVector.Level.medium : .none
        let theological = content.containsScripture || analysis?.intentKind == .scriptureReference ? SocialRiskVector.Level.low : .none
        let spam = containsAny(lower, ["click here now", "limited time offer", "you have been selected"]) ? SocialRiskVector.Level.medium : .none

        return SocialRiskVector(
            minorSafety: minor,
            selfHarm: crisis,
            abuse: .none,
            harassment: harassment,
            privacy: privacy,
            medical: medical,
            financial: financial,
            theological: theological,
            spam: spam
        )
    }

    private static func extractClaims(from text: String, analysis: AmenIntentAnalysis?) -> [String] {
        var claims: [String] = []
        let lower = text.lowercased()
        if containsAny(lower, ["god told me", "the bible says", "scripture says", "this proves"]) {
            claims.append(text)
        }
        if analysis?.intentKind == .scriptureReference || analysis?.intentKind == .studyPrompt {
            claims.append(analysis?.explanation ?? "Scripture-related claim")
        }
        return claims
    }

    private static func containsPII(_ text: String) -> Bool {
        let lower = text.lowercased()
        if containsAny(lower, ["my address is", "phone number", "social security", "ssn", "home address"]) {
            return true
        }
        return text.range(of: #"\b\d{3}[- .]?\d{3}[- .]?\d{4}\b"#, options: .regularExpression) != nil
    }

    private static func containsScripture(_ text: String, analysis: AmenIntentAnalysis?) -> Bool {
        guard analysis?.intentKind != .scriptureReference else { return true }
        let lower = text.lowercased()
        let books = ["genesis", "exodus", "psalm", "proverbs", "isaiah", "matthew", "mark", "luke", "john", "romans", "corinthians", "revelation"]
        return books.contains { lower.contains($0) } || text.range(of: #"\b\d?\s?[A-Z][a-z]+\s\d{1,3}:\d{1,3}\b"#, options: .regularExpression) != nil
    }

    private static func containsMinorSignal(_ text: String, analysis: AmenIntentAnalysis?) -> Bool {
        let lower = text.lowercased()
        if analysis?.intentKind == .prayerNeed {
            return containsAny(lower, ["child", "kid", "teen", "minor", "student", "youth"])
        }
        return containsAny(lower, ["child", "kid", "teen", "minor", "student", "youth", "under 18"])
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

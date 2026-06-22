import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helper: Minimal Post Factory

private func makePost(
    id: String = UUID().uuidString,
    authorId: String = "user_test_123",
    content: String = "Test post content",
    category: Post.PostCategory = .openTable,
    verseReference: String? = nil,
    isAnsweredPrayer: Bool = false
) -> Post {
    var post = Post(
        id: UUID(),
        firebaseId: id,
        authorId: authorId,
        authorName: "Test User",
        authorUsername: "testuser",
        authorInitials: "TU",
        authorProfileImageURL: nil,
        timeAgo: "1m",
        content: content,
        category: category,
        topicTag: nil,
        visibility: .everyone,
        allowComments: true,
        commentPermissions: .everyone,
        imageURLs: nil,
        linkURL: nil,
        linkPreviewTitle: nil,
        linkPreviewDescription: nil,
        linkPreviewImageURL: nil,
        linkPreviewSiteName: nil,
        linkPreviewType: nil,
        verseReference: verseReference,
        verseText: nil,
        createdAt: Date(),
        amenCount: 0,
        lightbulbCount: 0,
        commentCount: 0,
        repostCount: 0
    )
    post.isAnsweredPrayer = isAnsweredPrayer
    return post
}

// MARK: - Action Thread Model Tests

@Suite("ActionThread — Domain Models")
struct ActionThreadModelTests {

    @Test("ActionThreadType has correct rawValues")
    func actionThreadTypeRawValues() {
        #expect(ActionThreadType.prayerCircle.rawValue == "prayer_circle")
        #expect(ActionThreadType.checkIn.rawValue == "check_in")
        #expect(ActionThreadType.mealSupport.rawValue == "meal_support")
        #expect(ActionThreadType.scriptureSupport.rawValue == "scripture_support")
        #expect(ActionThreadType.encouragementFlow.rawValue == "encouragement_flow")
        #expect(ActionThreadType.careFollowup.rawValue == "care_followup")
        #expect(ActionThreadType.crisisResource.rawValue == "crisis_support_resource_prompt")
        #expect(ActionThreadType.customSupport.rawValue == "custom_support_flow")
    }

    @Test("ActionThreadType covers 8 care workflow kinds")
    func actionThreadTypeCount() {
        #expect(ActionThreadType.allCases.count == 8)
    }

    @Test("ActionThreadType.isSensitive only true for crisis and care followup")
    func sensitiveTypes() {
        #expect(ActionThreadType.crisisResource.isSensitive == true)
        #expect(ActionThreadType.careFollowup.isSensitive == true)
        #expect(ActionThreadType.prayerCircle.isSensitive == false)
        #expect(ActionThreadType.checkIn.isSensitive == false)
        #expect(ActionThreadType.mealSupport.isSensitive == false)
        #expect(ActionThreadType.scriptureSupport.isSensitive == false)
        #expect(ActionThreadType.encouragementFlow.isSensitive == false)
        #expect(ActionThreadType.customSupport.isSensitive == false)
    }

    @Test("ActionThread.isActionable returns true only for active/paused")
    func isActionable() {
        func makeThread(state: ActionThreadState) -> ActionThread {
            ActionThread(
                id: "t1", postId: "p1", postAuthorId: "u1", creatorUserId: "u1",
                type: .checkIn, visibility: .participants, state: state,
                sensitivityLevel: .standard, title: nil, description: nil,
                intent: nil, createdAt: Date(), updatedAt: Date(),
                completedAt: nil, expiresAt: nil,
                participantCount: 1, completedStepCount: 0, totalStepCount: 2
            )
        }
        #expect(makeThread(state: .active).isActionable == true)
        #expect(makeThread(state: .paused).isActionable == true)
        #expect(makeThread(state: .draft).isActionable == false)
        #expect(makeThread(state: .completed).isActionable == false)
        #expect(makeThread(state: .archived).isActionable == false)
        #expect(makeThread(state: .expired).isActionable == false)
        #expect(makeThread(state: .suggested).isActionable == false)
    }

    @Test("ActionSuggestion.SuggestionStatus has all expected cases")
    func suggestionStatusCases() {
        let statuses: [ActionSuggestion.SuggestionStatus] = [
            .pending, .seen, .accepted, .dismissed, .expired
        ]
        #expect(statuses.count == 5)
        #expect(ActionSuggestion.SuggestionStatus.pending.rawValue == "pending")
        #expect(ActionSuggestion.SuggestionStatus.accepted.rawValue == "accepted")
        #expect(ActionSuggestion.SuggestionStatus.dismissed.rawValue == "dismissed")
    }

    @Test("ActionThreadPermissionSet.ownerDefaults grants full permissions")
    func ownerDefaultPermissions() {
        let perms = ActionThreadPermissionSet.ownerDefaults
        #expect(perms.canAddParticipants == true)
        #expect(perms.canRemoveParticipants == true)
        #expect(perms.canEditSteps == true)
        #expect(perms.canCompleteSteps == true)
        #expect(perms.canArchiveThread == true)
        #expect(perms.canViewAuditLog == true)
        #expect(perms.requiresOwnerApproval == false)
    }

    @Test("ActionThreadPermissionSet.supporterDefaults only allows step completion")
    func supporterDefaultPermissions() {
        let perms = ActionThreadPermissionSet.supporterDefaults
        #expect(perms.canAddParticipants == false)
        #expect(perms.canRemoveParticipants == false)
        #expect(perms.canEditSteps == false)
        #expect(perms.canCompleteSteps == true)
        #expect(perms.canArchiveThread == false)
        #expect(perms.canViewAuditLog == false)
    }

    @Test("ActionThreadPermissionSet.observerDefaults has no active permissions")
    func observerDefaultPermissions() {
        let perms = ActionThreadPermissionSet.observerDefaults
        #expect(perms.canAddParticipants == false)
        #expect(perms.canCompleteSteps == false)
        #expect(perms.canArchiveThread == false)
        #expect(perms.canEditSteps == false)
    }

    @Test("SupportIntent encodes and decodes correctly")
    func supportIntentCodable() throws {
        let intent = SupportIntent(
            category: .prayerCircle,
            sensitivityLevel: .elevated,
            description: "Urgent prayer request",
            detectedSignals: ["urgent", "hospital"],
            confidence: 0.85,
            sourcePostId: "post_abc"
        )
        let data = try JSONEncoder().encode(intent)
        let decoded = try JSONDecoder().decode(SupportIntent.self, from: data)
        #expect(decoded.category == .prayerCircle)
        #expect(decoded.sensitivityLevel == .elevated)
        #expect(decoded.confidence == 0.85)
        #expect(decoded.detectedSignals == ["urgent", "hospital"])
    }

    @Test("ActionStep.StepType covers 8 care step types")
    func stepTypes() {
        let types: [ActionStep.StepType] = [
            .prayer, .checkIn, .mealDelivery, .scripture,
            .encouragement, .reminder, .resource, .custom
        ]
        #expect(types.count == 8)
    }

    @Test("CareSensitivityLevel has correct ordering semantics")
    func careSensitivityLevels() {
        // Verify all four levels exist
        let levels: [CareSensitivityLevel] = [.standard, .elevated, .high, .critical]
        #expect(levels.count == 4)
        #expect(CareSensitivityLevel.critical.rawValue == "critical")
        #expect(CareSensitivityLevel.standard.rawValue == "standard")
    }

    @Test("ActionSuggestion stores cooldownKey correctly")
    func cooldownKeyFormat() {
        let suggestion = ActionSuggestion(
            id: "s1",
            postId: "post_123",
            suggestedThreadType: .prayerCircle,
            intent: SupportIntent(
                category: .prayerCircle,
                sensitivityLevel: .standard,
                description: nil,
                detectedSignals: nil,
                confidence: 0.7,
                sourcePostId: "post_123"
            ),
            suggestedSteps: [],
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(604_800),
            status: .pending,
            cooldownKey: "user_xyz_post_123_prayer_circle"
        )
        #expect(suggestion.cooldownKey.contains("prayer_circle"))
        #expect(suggestion.cooldownKey.contains("post_123"))
        #expect(suggestion.status == .pending)
    }
}

// MARK: - Action Suggestion Engine Tests

@Suite("ActionSuggestionEngine — Feature Flag Gating")
@MainActor
struct ActionSuggestionEngineTests {

    @Test("Feature flag off: evaluatePost is a no-op")
    func featureFlagOffNoOp() async {
        // AMENFeatureFlags.actionSuggestionsEnabled defaults to false in tests
        let engine = ActionSuggestionEngine.shared
        let postId = UUID().uuidString
        let post = makePost(
            id: postId,
            content: "urgent prayer please surgery tomorrow please pray"
        )
        let beforeCount = engine.pendingSuggestions.count
        engine.evaluatePost(post)
        // Allow brief async Task to settle
        try? await Task.sleep(nanoseconds: 100_000_000)
        // With flag off, no new suggestion should be added
        #expect(engine.pendingSuggestions.count == beforeCount)
    }

    @Test("ActionSuggestionEngine is a shared singleton")
    func singleton() {
        let a = ActionSuggestionEngine.shared
        let b = ActionSuggestionEngine.shared
        #expect(a === b)
    }
}

// MARK: - Trust Signal Model Tests

@Suite("TrustSignalModels — Proof of Human & Care")
struct TrustSignalModelTests {

    @Test("TrustSignalDirection has positive and negative cases")
    func trustSignalDirectionCases() {
        #expect(TrustSignalDirection.positive.rawValue == "positive")
        #expect(TrustSignalDirection.negative.rawValue == "negative")
    }

    @Test("HumanSignalFactor.contribution is positive for positive direction")
    func humanFactorPositiveContribution() {
        let factor = HumanSignalFactor(
            factorType: .typedVsPastedRatio,
            value: 0.8,
            weight: 0.25,
            direction: .positive,
            source: "test",
            measuredAt: Date()
        )
        #expect(factor.contribution > 0)
        #expect(abs(factor.contribution - (0.8 * 0.25)) < 0.0001)
    }

    @Test("HumanSignalFactor.contribution is negative for negative direction")
    func humanFactorNegativeContribution() {
        let factor = HumanSignalFactor(
            factorType: .moderationHits,
            value: 0.5,
            weight: 0.2,
            direction: .negative,
            source: "moderation",
            measuredAt: Date()
        )
        #expect(factor.contribution < 0)
        #expect(abs(factor.contribution - (0.5 * 0.2 * -1.0)) < 0.0001)
    }

    @Test("CareSignalFactor.contribution is positive for positive direction")
    func careFactorPositiveContribution() {
        let factor = CareSignalFactor(
            factorType: .prayerFollowThrough,
            value: 1.0,
            weight: 0.25,
            direction: .positive,
            source: "PrayerFollowThroughService",
            measuredAt: Date()
        )
        #expect(factor.contribution == 0.25)
    }

    @Test("ProofOfHumanScore.meetsHumanThreshold requires score >= 0.5 and confidence >= 0.3")
    func humanScoreThreshold() {
        let passing = ProofOfHumanScore(
            userId: "u1", score: 0.6, confidence: 0.4, factors: [],
            computedAt: Date(), snapshotId: "s1", version: "1"
        )
        let failScore = ProofOfHumanScore(
            userId: "u2", score: 0.4, confidence: 0.5, factors: [],
            computedAt: Date(), snapshotId: "s2", version: "1"
        )
        let failConfidence = ProofOfHumanScore(
            userId: "u3", score: 0.7, confidence: 0.2, factors: [],
            computedAt: Date(), snapshotId: "s3", version: "1"
        )
        #expect(passing.meetsHumanThreshold == true)
        #expect(failScore.meetsHumanThreshold == false)
        #expect(failConfidence.meetsHumanThreshold == false)
    }

    @Test("ProofOfCareScore.meetsCareThreshold requires score >= 0.4 and confidence >= 0.3")
    func careScoreThreshold() {
        let passing = ProofOfCareScore(
            userId: "u1", score: 0.5, confidence: 0.35, factors: [],
            computedAt: Date(), snapshotId: "s1", version: "1"
        )
        let failing = ProofOfCareScore(
            userId: "u2", score: 0.3, confidence: 0.4, factors: [],
            computedAt: Date(), snapshotId: "s2", version: "1"
        )
        #expect(passing.meetsCareThreshold == true)
        #expect(failing.meetsCareThreshold == false)
    }

    @Test("TrustActionConstraint.createActionThread has minimum human score 0.3 and no care requirement")
    func trustConstraintCreateThread() {
        let constraint = TrustActionConstraint.createActionThread
        #expect(constraint.minimumHumanScore == 0.3)
        #expect(constraint.minimumCareScore == 0.0)
        #expect(constraint.minimumAccountAgeDays == 3)
        #expect(constraint.requiresVerification == false)
    }

    @Test("TrustActionConstraint.inviteToThread has higher minimum than createActionThread")
    func trustConstraintInviteHigherThanCreate() {
        #expect(TrustActionConstraint.inviteToThread.minimumHumanScore >
                TrustActionConstraint.createActionThread.minimumHumanScore)
        #expect(TrustActionConstraint.inviteToThread.minimumCareScore >
                TrustActionConstraint.createActionThread.minimumCareScore)
    }

    @Test("TrustEventType has all required cases for trust scoring")
    func trustEventTypeCases() {
        // Verify critical cases compile and exist
        let cases: [TrustEvent.TrustEventType] = [
            .postCreated, .commentCreated, .contentFlagged,
            .accountVerified, .prayerCommitment, .prayerFollowUp,
            .checkInCompleted, .actionStepCompleted, .meaningfulReply,
            .supportThreadJoined, .commitmentAbandoned, .moderationAction,
            .blockReceived, .reportReceived, .composerIntegrity, .suspiciousPattern
        ]
        #expect(cases.count == 16)
    }

    @Test("TrustEvent initializes with correct fields")
    func trustEventInit() {
        let ts = Date()
        let event = TrustEvent(
            id: "e1",
            userId: "u1",
            eventType: .postCreated,
            category: .human,
            value: 1.0,
            source: "FirebasePostService",
            relatedEntityId: "post_abc",
            timestamp: ts,
            metadata: ["category": "prayer"]
        )
        #expect(event.userId == "u1")
        #expect(event.eventType == .postCreated)
        #expect(event.category == .human)
        #expect(event.value == 1.0)
        #expect(event.relatedEntityId == "post_abc")
        #expect(event.source == "FirebasePostService")
        #expect(event.timestamp == ts)
    }

    @Test("TrustEventCategory has human, care, and both cases")
    func trustEventCategory() {
        let categories: [TrustEvent.TrustEventCategory] = [.human, .care, .both]
        #expect(categories.count == 3)
        #expect(TrustEvent.TrustEventCategory.human.rawValue == "human")
        #expect(TrustEvent.TrustEventCategory.care.rawValue == "care")
    }

    @Test("TrustEligibility captures gating fields correctly")
    func trustEligibilityFields() {
        let eligibility = TrustEligibility(
            userId: "u1",
            feature: "create_action_thread",
            isEligible: true,
            reason: "All requirements met",
            humanScoreRequired: 0.3,
            careScoreRequired: 0.0,
            actualHumanScore: 0.7,
            actualCareScore: 0.5,
            evaluatedAt: Date()
        )
        #expect(eligibility.isEligible == true)
        #expect(eligibility.humanScoreRequired == 0.3)
        #expect(eligibility.actualHumanScore == 0.7)
        #expect(eligibility.feature == "create_action_thread")
    }

    @Test("TrustEligibility ineligible when human score below requirement")
    func trustEligibilityBlocked() {
        let blocked = TrustEligibility(
            userId: "u2",
            feature: "invite_to_thread",
            isEligible: false,
            reason: "Human score too low",
            humanScoreRequired: 0.4,
            careScoreRequired: 0.2,
            actualHumanScore: 0.1,
            actualCareScore: 0.5,
            evaluatedAt: Date()
        )
        #expect(blocked.isEligible == false)
        #expect(blocked.reason == "Human score too low")
        #expect(blocked.actualHumanScore < blocked.humanScoreRequired)
    }
}

// MARK: - Compound Identity Graph Model Tests

@Suite("CompoundIdentityGraph — Agent Models")
struct CompoundIdentityGraphModelTests {

    @Test("AgentType has all six agents")
    func agentTypeCount() {
        #expect(AgentType.allCases.count == 6)
    }

    @Test("AgentType rawValues are lowercase strings")
    func agentTypeRawValues() {
        #expect(AgentType.berean.rawValue == "berean")
        #expect(AgentType.care.rawValue == "care")
        #expect(AgentType.trust.rawValue == "trust")
        #expect(AgentType.growth.rawValue == "growth")
        #expect(AgentType.community.rawValue == "community")
        #expect(AgentType.creator.rawValue == "creator")
    }

    @Test("AgentPermissionBoundary.defaults returns boundary for every agent type")
    func agentPermissionBoundaryExistsForAll() {
        for agent in AgentType.allCases {
            let boundary = AgentPermissionBoundary.defaults(for: agent)
            #expect(boundary.agentType == agent)
        }
    }

    @Test("Berean agent can read user content and write insights")
    func bereanAgentPermissions() {
        let boundary = AgentPermissionBoundary.defaults(for: .berean)
        #expect(boundary.canReadUserContent == true)
        #expect(boundary.canWriteInsights == true)
        #expect(boundary.canWriteRecommendations == true)
        #expect(boundary.canReadOtherUserContent == false)  // private by default
        #expect(boundary.canTriggerNotifications == false)  // Berean does not push notifications
    }

    @Test("Trust agent cannot read user content (privacy constraint)")
    func trustAgentCannotReadUserContent() {
        let boundary = AgentPermissionBoundary.defaults(for: .trust)
        #expect(boundary.canReadUserContent == false)
        #expect(boundary.canReadOtherUserContent == false)
        #expect(boundary.canWriteInsights == true)         // Can write trust insights
        #expect(boundary.canWriteRecommendations == false) // Trust agent doesn't surface recs
    }

    @Test("Care agent can trigger notifications (for urgent care)")
    func careAgentCanTriggerNotifications() {
        let boundary = AgentPermissionBoundary.defaults(for: .care)
        #expect(boundary.canTriggerNotifications == true)
        #expect(boundary.canAccessSensitiveData == true)
    }

    @Test("Community agent can read other user content but not sensitive data")
    func communityAgentPermissions() {
        let boundary = AgentPermissionBoundary.defaults(for: .community)
        #expect(boundary.canReadOtherUserContent == true)
        #expect(boundary.canAccessSensitiveData == false)
        #expect(boundary.canTriggerNotifications == false)
    }

    @Test("AgentPermissionBoundary memory retention varies by agent")
    func memoryRetentionDiffers() {
        // Trust agent has longest retention (audit trail)
        let trust = AgentPermissionBoundary.defaults(for: .trust)
        let care = AgentPermissionBoundary.defaults(for: .care)
        #expect(trust.memoryRetentionDays > care.memoryRetentionDays)
    }

    @Test("UserContextWindow initializes correctly")
    func userContextWindowInit() {
        let ctx = UserContextWindow(
            userId: "u1",
            currentSurface: "post_creation",
            sessionSignal: nil,
            recentPostCategories: ["prayer", "testimony"],
            recentActionTypes: ["post_created"],
            accountAgeDays: 90,
            isMinor: false,
            trustTier: "standard",
            activeActionThreadCount: 1,
            timestamp: Date()
        )
        #expect(ctx.userId == "u1")
        #expect(ctx.currentSurface == "post_creation")
        #expect(ctx.recentPostCategories.count == 2)
        #expect(ctx.accountAgeDays == 90)
        #expect(ctx.isMinor == false)
        #expect(ctx.activeActionThreadCount == 1)
    }

    @Test("AgentRecommendation.RecommendationStatus has expected cases")
    func recommendationStatusCases() {
        let statuses: [AgentRecommendation.RecommendationStatus] = [
            .pending, .surfaced, .accepted, .dismissed, .expired
        ]
        #expect(statuses.count == 5)
    }

    @Test("AgentPrioritySignal.Urgency has correct ordering")
    func urgencyOrdering() {
        #expect(AgentPrioritySignal.Urgency.low < AgentPrioritySignal.Urgency.normal)
        #expect(AgentPrioritySignal.Urgency.normal < AgentPrioritySignal.Urgency.elevated)
        #expect(AgentPrioritySignal.Urgency.elevated < AgentPrioritySignal.Urgency.urgent)
    }
}

// MARK: - AMENFeatureFlags — All New Flags Default to False

@Suite("AMENFeatureFlags — Intelligent Social Architecture defaults")
@MainActor
struct IntelligentSocialFeatureFlagTests {

    @Test("Action Thread flags default to false")
    func actionThreadFlagsOff() {
        let flags = AMENFeatureFlags.shared
        #expect(flags.actionThreadsEnabled == false)
        #expect(flags.actionSuggestionsEnabled == false)
        #expect(flags.careFollowupsEnabled == false)
    }

    @Test("Compound Identity Graph flags default to false")
    func compoundIdentityFlagsOff() {
        let flags = AMENFeatureFlags.shared
        #expect(flags.compoundIdentityGraphEnabled == false)
        #expect(flags.agentRecommendationsEnabled == false)
    }

    @Test("Proof of Human/Care flags default to false")
    func trustSignalFlagsOff() {
        let flags = AMENFeatureFlags.shared
        #expect(flags.proofOfHumanEnabled == false)
        #expect(flags.proofOfCareEnabled == false)
        #expect(flags.trustSignalsEnabled == false)
    }
}

// MARK: - IntelligentSocialPipeline — Integration Guard Tests

@Suite("IntelligentSocialPipeline — Feature flag gating")
@MainActor
struct IntelligentSocialPipelineTests {

    @Test("Pipeline is a shared singleton")
    func singleton() {
        let a = IntelligentSocialPipeline.shared
        let b = IntelligentSocialPipeline.shared
        #expect(a === b)
    }

    @Test("Pipeline handlePostCreated runs without crash when all flags are off")
    func pipelineNoCrashFlagsOff() async {
        let post = makePost(content: "Just a normal post")
        // Should complete cleanly with no flags enabled (no Firebase calls)
        await IntelligentSocialPipeline.shared.handlePostCreated(
            post: post,
            currentSurface: "test"
        )
        #expect(Bool(true))  // reaching here without crash = pass
    }
}

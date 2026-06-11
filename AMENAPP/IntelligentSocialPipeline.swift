import Foundation
import FirebaseAuth

@MainActor
final class IntelligentSocialPipeline {

    static let shared = IntelligentSocialPipeline()

    private init() {}

    func handlePostCreated(
        post: Post,
        authenticitySignals: AuthenticitySignals? = nil,
        currentSurface: String = "post_creation"
    ) async {
        guard let userId = Auth.auth().currentUser?.uid, post.authorId == userId else { return }

        if AMENFeatureFlags.shared.trustSignalsEnabled {
            if let authenticitySignals {
                await TrustEventRecorder.shared.recordComposerIntegrity(
                    userId: userId,
                    typedRatio: authenticitySignals.typedVsPastedRatio
                )
            }

            let postId = post.firebaseId ?? post.id.uuidString
            await TrustEventRecorder.shared.recordPostCreated(
                userId: userId,
                postId: postId,
                category: post.category.rawValue
            )

            if AMENFeatureFlags.shared.proofOfHumanEnabled || AMENFeatureFlags.shared.proofOfCareEnabled {
                let _ = await TrustScoringEngine.shared.computeScores(userId: userId)
            }
        }

        if AMENFeatureFlags.shared.actionSuggestionsEnabled {
            ActionSuggestionEngine.shared.evaluatePost(post)
        }

        if AMENFeatureFlags.shared.compoundIdentityGraphEnabled || AMENFeatureFlags.shared.agentRecommendationsEnabled {
            let context = buildContextWindow(
                userId: userId,
                post: post,
                currentSurface: currentSurface
            )
            let _ = await UserIntelligenceOrchestrator.shared.evaluate(context: context)
        }
    }

    private func buildContextWindow(
        userId: String,
        post: Post,
        currentSurface: String
    ) -> UserContextWindow {
        let creationDate = Auth.auth().currentUser?.metadata.creationDate ?? Date()
        let accountAgeDays = max(
            0,
            Calendar.current.dateComponents([.day], from: creationDate, to: Date()).day ?? 0
        )

        // SECURITY FIX (MEDIUM 2026-06-11): Resolve actual minor status from
        // AgeAssuranceService (synchronous, already loaded) instead of hardcoding false.
        // Default to true (minor-safe) so that users on first load or with a stale token
        // receive protective defaults until the age tier is confirmed.
        let currentIsMinor = AgeAssuranceService.shared.currentUserTier.isMinor

        let category = post.category.rawValue
        return UserContextWindow(
            userId: userId,
            currentSurface: currentSurface,
            sessionSignal: nil,
            recentPostCategories: [category],
            recentActionTypes: ["post_created"],
            accountAgeDays: accountAgeDays,
            isMinor: currentIsMinor,
            trustTier: "standard",
            activeActionThreadCount: post.hasActiveActionThread ? 1 : 0,
            timestamp: Date()
        )
    }
}

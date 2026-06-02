// CommunityGraphViewModel.swift
// AMEN App — Community Around Content OS / Graph
//
// @MainActor ObservableObject that drives Community Graph UI.
// Delegates all Firestore work to CommunityGraphService and CommunityDNAService.
// All operations are gated on the .meaningGraph Remote Config flag.

import Foundation
import FirebaseAuth

// MARK: - CommunityGraphViewModel

@MainActor
final class CommunityGraphViewModel: ObservableObject {

    // MARK: Published state

    @Published var dnaProfile: CommunityDNAProfile?
    @Published var affinityScores: [CommunityAffinityScore] = []
    @Published var isLoading = false

    // MARK: Private state

    /// Minimum interval between automatic profile refreshes after an engagement event.
    private let refreshDebounceInterval: TimeInterval = 30
    private var lastRefreshedAt: Date?

    // MARK: - loadProfile

    /// Loads the DNA profile for the currently authenticated Firebase user.
    /// Silently no-ops if the flag is off or no user is signed in.
    func loadProfile() async {
        guard CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityGraphViewModel] meaningGraph flag off — skipping loadProfile")
            return
        }

        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("[CommunityGraphViewModel] No authenticated user — skipping loadProfile")
            return
        }

        isLoading = true
        defer {
            withAnimation(AppAnimation.stateChange) {
                isLoading = false
            }
        }

        do {
            async let profileFetch = CommunityDNAService.shared.getOrCreateDNA(for: userId)
            async let scoresFetch = CommunityGraphService.shared.getAffinityScores(for: userId)

            let (profile, scores) = try await (profileFetch, scoresFetch)

            withAnimation(AppAnimation.stateChange) {
                dnaProfile = profile
                affinityScores = scores
            }

            dlog("[CommunityGraphViewModel] Profile loaded — primary: \(profile.primaryAffinity?.displayName ?? "none")")
        } catch {
            dlog("[CommunityGraphViewModel] loadProfile failed: \(error)")
        }
    }

    // MARK: - recordEngagement

    /// Records a content engagement event via CommunityGraphService,
    /// then refreshes the profile if the debounce window has elapsed.
    func recordEngagement(
        event: ContentEngagementEvent,
        contentObject: ContentObject
    ) async {
        guard CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityGraphViewModel] meaningGraph flag off — skipping recordEngagement")
            return
        }

        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("[CommunityGraphViewModel] No authenticated user — skipping recordEngagement")
            return
        }

        // Delegate write to the service actor
        await CommunityGraphService.shared.recordEngagement(
            userId: userId,
            event: event,
            contentObject: contentObject
        )

        // Refresh profile if enough time has passed since the last refresh
        let now = Date()
        let shouldRefresh: Bool
        if let last = lastRefreshedAt {
            shouldRefresh = now.timeIntervalSince(last) >= refreshDebounceInterval
        } else {
            shouldRefresh = true
        }

        if shouldRefresh {
            lastRefreshedAt = now
            do {
                let refreshed = try await CommunityDNAService.shared.refreshDNA(for: userId)
                let scores = try await CommunityGraphService.shared.getAffinityScores(for: userId)
                withAnimation(AppAnimation.fade) {
                    dnaProfile = refreshed
                    affinityScores = scores
                }
                dlog("[CommunityGraphViewModel] Profile refreshed after engagement event '\(event.eventType.rawValue)'")
            } catch {
                dlog("[CommunityGraphViewModel] Profile refresh failed: \(error)")
            }
        }
    }

    // MARK: - Computed

    /// Human-readable label for the user's dominant spiritual affinity.
    var primaryAffinityLabel: String {
        dnaProfile?.primaryAffinity?.displayName ?? "Explorer"
    }
}

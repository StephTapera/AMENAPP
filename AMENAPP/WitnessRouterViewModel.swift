// WitnessRouterViewModel.swift
// AMENAPP — Witness Network matching engine ViewModel

import Foundation
import FirebaseAuth
import Combine

// MARK: - WitnessRouterViewModel

@MainActor
final class WitnessRouterViewModel: ObservableObject {

    // MARK: - Published State

    @Published var matchedTestimonies: [Testimony] = []
    @Published var myPrayerRequests: [PrayerRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let service = WitnessService.shared
    private var currentUserId: String? { Auth.auth().currentUser?.uid }

    // MARK: - Load

    /// Builds user prayer context from their latest requests and loads matching testimonies.
    /// Degrades gracefully: if AI fails, returns recent testimonies instead.
    func loadMatchedTestimonies() async {
        guard let uid = currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let requests = try await service.fetchMyPrayerRequests(userId: uid)
            myPrayerRequests = requests

            let context = buildContext(from: requests)
            matchedTestimonies = await service.fetchMatchedTestimonies(for: context)
        } catch {
            errorMessage = "Couldn't load testimonies. Please try again."
        }
    }

    // MARK: - Submit

    /// Submits a new testimony for the current user.
    func submitTestimony(content: String, authorName: String) async {
        guard let uid = currentUserId, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let testimony = Testimony(
            userId: uid,
            authorDisplayName: authorName,
            content: content
        )

        do {
            _ = try await service.submitTestimony(testimony)
            // Refresh after submit
            await loadMatchedTestimonies()
        } catch {
            errorMessage = "Couldn't submit your testimony. Please try again."
        }
    }

    /// Submits a new prayer request.
    func submitPrayerRequest(content: String, isAnonymous: Bool, urgency: String) async {
        guard let uid = currentUserId, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let request = PrayerRequest(
            userId: uid,
            content: content,
            urgencyLevel: urgency,
            isAnonymous: isAnonymous
        )

        do {
            _ = try await service.submitPrayerRequest(request)
            await loadMatchedTestimonies()
        } catch {
            errorMessage = "Couldn't submit your prayer request."
        }
    }

    /// Marks a testimony as impactful.
    func markImpact(testimonyId: String) async {
        try? await service.reportImpact(testimonyId: testimonyId)
    }

    // MARK: - Helpers

    private func buildContext(from requests: [PrayerRequest]) -> UserPrayerContext {
        let allThemes = requests.flatMap { $0.themes }
        let uniqueThemes = Array(Set(allThemes))
        let latestEmotion = requests.first?.emotionalState ?? ""
        return UserPrayerContext(
            prayerThemes: uniqueThemes,
            emotionalState: latestEmotion,
            recentRequests: Array(requests.prefix(3))
        )
    }
}

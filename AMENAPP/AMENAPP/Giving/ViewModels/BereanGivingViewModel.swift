// BereanGivingViewModel.swift
// AMENAPP
//
// Berean giving counselor — discernment guide, not a conversion funnel.

import Foundation
import SwiftUI

@MainActor
final class BereanGivingViewModel: ObservableObject {

    @Published var promptText = ""
    @Published var budgetDollars: Int = 100
    @Published var response: BereanGivingResponse? = nil
    @Published var isLoading = false
    @Published var selectedRecommendation: BereanGivingRecommendation? = nil
    @Published var showScripture: Set<UUID> = []
    @Published var savedRecommendationIds: Set<UUID> = []

    private let service = BereanGivingService()
    var profile: GivingProfile = .empty
    var candidates: [GivingOrganization] = []

    let budgetOptions = [25, 50, 100, 200, 500]

    func submitPrompt() async {
        guard !isLoading else { return }
        isLoading = true
        response = nil

        let prompt = promptText.isEmpty
            ? "I have $\(budgetDollars) to give this month. What should I do with it?"
            : promptText

        response = await service.getCounsel(
            prompt: prompt,
            budget: budgetDollars * 100,
            profile: profile,
            candidates: candidates
        )
        isLoading = false
    }

    func toggleSaved(id: UUID) {
        if savedRecommendationIds.contains(id) {
            savedRecommendationIds.remove(id)
        } else {
            savedRecommendationIds.insert(id)
        }
    }

    func toggleScripture(id: UUID) {
        if showScripture.contains(id) {
            showScripture.remove(id)
        } else {
            showScripture.insert(id)
        }
    }

    func clearSession() {
        response = nil
        promptText = ""
    }
}

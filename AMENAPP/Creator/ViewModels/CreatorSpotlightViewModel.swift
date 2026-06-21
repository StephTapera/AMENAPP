// CreatorSpotlightViewModel.swift
// AMENAPP — Creator Spotlight / Wave 1
//
// ViewModel for the Creator Spotlight public page.
// Fail-closed: nothing loads unless the feature flag is on.
// No trust score, no vanity counters.

import Foundation
import SwiftUI

@MainActor
final class CreatorSpotlightViewModel: ObservableObject {

    @Published var spotlight: CreatorSpotlight?
    @Published var isLoading = false
    @Published var error: String?

    private let creatorId: String

    init(creatorId: String) {
        self.creatorId = creatorId
    }

    func load() async {
        guard AMENFeatureFlags.shared.creatorSpotlightEnabled else { return }

        isLoading = true
        defer { isLoading = false }

        // TODO: load from Firestore /creators/{creatorId}/spotlight
        // Until the Firestore document shape is deployed and the callable is wired,
        // leave spotlight nil so every view guards on it correctly.
        spotlight = nil
    }
}

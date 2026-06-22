// BereanGivingViewModel.swift
// AMENAPP
//
// Berean giving counselor — discernment guide, not a conversion funnel.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class BereanGivingViewModel: ObservableObject {

    @Published var promptText = ""
    @Published var budgetDollars: Int = 100
    @Published var response: BereanGivingResponse? = nil
    @Published var isLoading = false
    @Published var selectedRecommendation: BereanGivingRecommendation? = nil
    @Published var showScripture: Set<UUID> = []
    @Published var savedRecs: Set<UUID> = []

    private let service = BereanGivingService()
    private let db = Firestore.firestore()
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

    func toggleScripture(id: UUID) {
        if showScripture.contains(id) {
            showScripture.remove(id)
        } else {
            showScripture.insert(id)
        }
    }

    func saveRecommendation(_ rec: BereanGivingRecommendation) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Toggle local state immediately so the UI responds without waiting on Firestore.
        if savedRecs.contains(rec.id) {
            savedRecs.remove(rec.id)
            db.collection("users").document(uid)
                .collection("savedGivingRecs").document(rec.id.uuidString)
                .delete()
            return
        }

        savedRecs.insert(rec.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        var payload: [String: Any] = [
            "recId": rec.id.uuidString,
            "reason": rec.reason,
            "fitLabel": rec.fitLabel,
            "actionLabel": rec.actionLabel,
            "destinationType": "\(rec.destinationType)",
            "savedAt": FieldValue.serverTimestamp()
        ]
        if let org = rec.org {
            payload["orgId"] = org.id
            payload["orgName"] = org.name
            payload["donationUrl"] = org.donationUrl as Any
        }
        if let ref = rec.scriptureRef { payload["scriptureRef"] = ref }
        if let text = rec.scriptureText { payload["scriptureText"] = text }

        db.collection("users").document(uid)
            .collection("savedGivingRecs").document(rec.id.uuidString)
            .setData(payload)
    }

    func clearSession() {
        response = nil
        promptText = ""
    }
}

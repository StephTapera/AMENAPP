// CreatorStudioViewModel.swift
// AMENAPP — Creator Studio / Wave 5
//
// ViewModel for the anti-vanity Creator Studio stewardship dashboard.
// Fail-closed: nothing loads unless creatorStudioDashboardEnabled.
// CONSTITUTION LOCK: no growth chart, no streak, no raw number headlines.
//
// Real data path: on load, ask the backend `generateStudioInsights` callable to
// (re)compute insights from the creator's OWN real content, then read the persisted
// insights from Firestore. No fabricated/stub insights — if there is nothing real to
// say yet, the dashboard shows its honest empty state.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class CreatorStudioViewModel: ObservableObject {

    @Published var insights: [StudioInsight] = []
    @Published var isLoading = false
    /// Visitor count — ONLY surfaced as a narrative sentence, never as a headline metric.
    /// 0 until a real aggregate source exists (no fabricated number).
    @Published var profileViews: Int = 0

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-east1")
    private static let insightsCollection = "creatorStudioInsights"

    func load(creatorId: String) async {
        guard AMENFeatureFlags.shared.creatorStudioDashboardEnabled else { return }

        isLoading = true
        defer { isLoading = false }

        // 1. Best-effort refresh: recompute from the creator's real content server-side.
        //    Non-fatal if the callable isn't deployed yet — we still read whatever exists.
        do {
            _ = try await functions.httpsCallable("generateStudioInsights").call([:])
        } catch {
            // Ignore — fall through to read any previously-persisted insights.
        }

        // 2. Read the persisted insights (server is the only writer; rules enforce own-only).
        do {
            let snapshot = try await db.collection(Self.insightsCollection)
                .whereField("creatorId", isEqualTo: creatorId)
                .order(by: "generatedAt", descending: true)
                .getDocuments()

            insights = snapshot.documents.compactMap {
                try? $0.data(as: StudioInsight.self)
            }
        } catch {
            // Fail-closed: empty dashboard rather than fabricated content.
            insights = []
        }

        // No real per-creator profile-view aggregate is wired yet — keep 0 (the view
        // hides the narrative row entirely when this is 0, so nothing fake is shown).
        profileViews = 0
    }
}

// CreatorTestimonyViewModel.swift
// AMENAPP — Creator Spotlight / Wave 2
//
// Manages approved community reflections for a creator.
// Fail-closed: testimonies stays empty unless moderationStatus == .approved
// AND visibleToPublic == true. Never exposes unmoderated content.

import Foundation

@MainActor
final class CreatorTestimonyViewModel: ObservableObject {

    @Published var testimonies: [CommunityReflection] = []
    @Published var bereanSummary: BereanReflectionSummary?
    @Published var isSubmitting: Bool = false
    @Published private(set) var submitSuccess: Bool = false

    // MARK: - Load

    /// Loads approved, public-visible reflections for the given creator.
    /// Fail-closed: any error or missing flag leaves `testimonies` empty.
    func load(creatorId: String) async {
        guard AMENFeatureFlags.shared.creatorTestimonyEnabled else { return }

        do {
            // TODO: replace with real Firestore query:
            //   db.collection("communityReflections")
            //     .whereField("targetCreatorId", isEqualTo: creatorId)
            //     .whereField("moderationStatus", isEqualTo: "approved")
            //     .whereField("visibleToPublic", isEqualTo: true)
            let fetched: [CommunityReflection] = []  // stub

            // Double-filter client-side: only approved + visibleToPublic
            testimonies = fetched.filter {
                $0.moderationStatus == .approved && $0.visibleToPublic
            }

            // TODO: load BereanReflectionSummary from
            //   db.collection("bereanReflectionSummaries")
            //     .whereField("creatorId", isEqualTo: creatorId)
            bereanSummary = nil  // stub

        } catch {
            // Fail-closed: keep testimonies empty
            testimonies = []
        }
    }

    // MARK: - Submit

    /// Creates a new CommunityReflection with pending moderation status.
    /// The reflection is invisible to the public until GUARDIAN approves it.
    func submit(
        creatorId: String,
        contentId: String?,
        tags: [ReflectionTag],
        written: String?
    ) async {
        guard AMENFeatureFlags.shared.creatorTestimonyEnabled else { return }
        guard !tags.isEmpty else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        let reflection = CommunityReflection(
            id: UUID().uuidString,
            authorId: "current_user",            // TODO: inject real auth UID
            contentId: contentId,
            targetCreatorId: creatorId,
            tags: tags,
            writtenReflection: written.flatMap { $0.isEmpty ? nil : $0 },
            submittedAt: Date().timeIntervalSince1970,
            moderationStatus: .pending,          // GUARDIAN pre-moderation; never auto-approve
            visibleToPublic: false               // Invisible until approved
        )

        do {
            // TODO: write to Firestore:
            //   try await db.collection("communityReflections")
            //                .document(reflection.id)
            //                .setData(reflection.firestoreData)
            _ = reflection  // stub — suppress unused warning

            // Show success state locally; do NOT add to testimonies
            // (it will appear after moderation clears it)
            submitSuccess = true
        } catch {
            // Non-fatal — UI surfaces error through isSubmitting returning false
            submitSuccess = false
        }
    }

    // MARK: - Reset

    func resetSubmitState() {
        submitSuccess = false
    }
}

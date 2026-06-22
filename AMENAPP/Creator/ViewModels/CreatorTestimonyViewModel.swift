// CreatorTestimonyViewModel.swift
// AMENAPP — Creator Spotlight / Wave 2
//
// Manages approved community reflections for a creator.
// Fail-closed: testimonies stays empty unless moderationStatus == .approved
// AND visibleToPublic == true. Never exposes unmoderated content.
//
// Write path: every submission runs through ContentModerationService (the same
// GUARDIAN pre-moderation path posts and comments use) BEFORE it is written, and
// is always persisted as `.pending` / `visibleToPublic == false`. A human/Berean
// approval flips it to `.approved` server-side — the client never auto-approves.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class CreatorTestimonyViewModel: ObservableObject {

    @Published var testimonies: [CommunityReflection] = []
    @Published var bereanSummary: BereanReflectionSummary?
    @Published var isSubmitting: Bool = false
    @Published private(set) var submitSuccess: Bool = false
    /// Honest, user-facing error when a submission is blocked or fails. nil when clear.
    @Published var submitError: String?

    private let db = Firestore.firestore()
    private static let reflectionsCollection = "communityReflections"
    private static let summariesCollection = "bereanReflectionSummaries"

    // MARK: - Load

    /// Loads approved, public-visible reflections for the given creator.
    /// Fail-closed: any error or missing flag leaves `testimonies` empty.
    func load(creatorId: String) async {
        guard AMENFeatureFlags.shared.creatorTestimonyEnabled else { return }

        do {
            let snapshot = try await db.collection(Self.reflectionsCollection)
                .whereField("targetCreatorId", isEqualTo: creatorId)
                .whereField("moderationStatus", isEqualTo: SpotlightModerationStatus.approved.rawValue)
                .whereField("visibleToPublic", isEqualTo: true)
                .order(by: "submittedAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            let fetched: [CommunityReflection] = snapshot.documents.compactMap {
                try? $0.data(as: CommunityReflection.self)
            }

            // Double-filter client-side: only approved + visibleToPublic (defense in depth).
            testimonies = fetched.filter {
                $0.moderationStatus == .approved && $0.visibleToPublic
            }

            // Berean theme summary (generated + written server-side; read-only here).
            let summarySnap = try await db.collection(Self.summariesCollection)
                .whereField("creatorId", isEqualTo: creatorId)
                .limit(to: 1)
                .getDocuments()
            bereanSummary = summarySnap.documents.first.flatMap {
                try? $0.data(as: BereanReflectionSummary.self)
            }
        } catch {
            // Fail-closed: keep testimonies empty
            testimonies = []
            bereanSummary = nil
        }
    }

    // MARK: - Submit

    /// Creates a new CommunityReflection with pending moderation status.
    /// The reflection runs through GUARDIAN pre-moderation and is invisible to the
    /// public until it is approved server-side.
    func submit(
        creatorId: String,
        contentId: String?,
        tags: [ReflectionTag],
        written: String?
    ) async {
        guard AMENFeatureFlags.shared.creatorTestimonyEnabled else { return }
        guard !tags.isEmpty else { return }

        guard let uid = Auth.auth().currentUser?.uid else {
            submitError = "Please sign in to share a reflection."
            return
        }

        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let trimmedWritten = written?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reflectionText = (trimmedWritten?.isEmpty == false) ? trimmedWritten : nil

        // Moderation-write path: any free text passes through the same pre-moderation
        // gate as posts/comments before it is written. Tags alone (no free text) are
        // a fixed, safe vocabulary and still land as `.pending` for human review.
        if let text = reflectionText {
            do {
                let decision = try await ContentModerationService.moderateContent(
                    text: text,
                    category: .comment,
                    signals: Self.typedSignals(for: text),
                    parentContentId: contentId
                )
                if decision.shouldBlock {
                    submitSuccess = false
                    submitError = decision.userMessage
                    return
                }
            } catch {
                // Fail-closed: if moderation cannot be reached, do not write.
                submitSuccess = false
                submitError = "We couldn't review your reflection right now. Please try again."
                return
            }
        }

        let reflection = CommunityReflection(
            id: UUID().uuidString,
            authorId: uid,
            contentId: contentId,
            targetCreatorId: creatorId,
            tags: tags,
            writtenReflection: reflectionText,
            submittedAt: Date().timeIntervalSince1970,
            moderationStatus: .pending,          // GUARDIAN pre-moderation; never auto-approve
            visibleToPublic: false               // Invisible until approved server-side
        )

        do {
            try db.collection(Self.reflectionsCollection)
                .document(reflection.id)
                .setData(from: reflection)

            // Show success state locally; do NOT add to testimonies
            // (it will appear after moderation clears it).
            submitSuccess = true
        } catch {
            submitSuccess = false
            submitError = "Your reflection couldn't be saved. Please try again."
        }
    }

    // MARK: - Reset

    func resetSubmitState() {
        submitSuccess = false
        submitError = nil
    }

    // MARK: - Helpers

    /// Neutral authenticity signals for text typed into the reflection composer.
    /// This view does not instrument keystrokes, so we report it as typed (not pasted).
    private static func typedSignals(for text: String) -> AuthenticitySignals {
        AuthenticitySignals(
            typedCharacters: text.count,
            pastedCharacters: 0,
            typedVsPastedRatio: 1.0,
            largestPasteLength: 0,
            pasteEventCount: 0,
            typingDurationSeconds: 0,
            hasLargePaste: false
        )
    }
}

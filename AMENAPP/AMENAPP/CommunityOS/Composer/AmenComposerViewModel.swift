// AmenComposerViewModel.swift
// AMEN App — CommunityOS / Composer
//
// Phase 2 — Agent A3 (Universal Composer)
// @MainActor ObservableObject driving AmenUniversalComposerView.
//
// Responsibilities:
//   - Holds the mutable ComposerDraft and resolved ComposerConfig.
//   - Validates the draft (character limits, required fields).
//   - Submits via AmenTransformEngine + AmenObjectRepository.
//   - Never exposes public post counts or comparison metrics (anti-engagement rule).
//
// Async: async/await only — no Combine.
// Safety: no force-unwraps; all guard lets + throws.

import Foundation
import FirebaseAuth

// MARK: - AmenComposerViewModel

@MainActor
final class AmenComposerViewModel: ObservableObject {

    // MARK: Published State

    @Published var draft: ComposerDraft
    @Published var isSubmitting: Bool = false
    @Published var submitError: String? = nil
    @Published var didSubmit: Bool = false

    // MARK: Resolved Config

    private(set) var config: ComposerConfig

    // MARK: Private

    private let repository: AmenObjectRepository
    private let engine: AmenTransformEngine

    // MARK: - Init

    /// Creates a new composer session for the given source and optional initial intent.
    ///
    /// - Parameters:
    ///   - source: Where the composition is seeded from (or `.standalone` for a new post).
    ///   - intent: Optional pre-selected intent. Falls back to the first allowed intent.
    ///   - repository: The object repository to write to on submit (injectable for tests).
    @MainActor
    init(
        source: ComposerSource,
        intent: AmenIntent? = nil,
        repository: AmenObjectRepository? = nil
    ) {
        let resolved = ComposerConfig.config(for: source, intent: intent)

        var initialDraft = ComposerDraft()
        initialDraft.selectedIntent = resolved.intent
        initialDraft.audience       = resolved.defaultAudience
        initialDraft.sourceRef      = source.existingRef
        initialDraft.sourceType     = source.type.amenObjectTypeRaw

        // Pre-fill from source if provided.
        if let prefill = source.prefillText {
            initialDraft.body = prefill
        }
        if let prefillTitle = source.prefillTitle {
            initialDraft.title = prefillTitle
        }

        self.config     = resolved
        self.draft      = initialDraft
        self.repository = repository ?? AmenObjectRepository()
        self.engine     = AmenTransformEngine()
    }

    // MARK: - Character Limits

    /// Maximum character count for the body field, based on selected intent.
    var characterLimit: Int {
        switch draft.selectedIntent {
        case .announce: return 280
        case .pray:     return 500
        default:        return 2000
        }
    }

    // MARK: - Validation

    /// True when the draft has all required fields filled and is within limits.
    var isValid: Bool {
        let trimmedBody = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return false }
        guard trimmedBody.count <= characterLimit else { return false }

        // Title is required for jobs, events, and announcements.
        if config.showTitleField {
            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return false }
        }

        // Job intent requires both title and organization.
        if draft.selectedIntent == .hire {
            let jt = draft.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let jo = draft.jobOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !jt.isEmpty, !jo.isEmpty else { return false }
        }

        return true
    }

    // MARK: - Intent Switch

    /// Switches to a new intent, reconfigures the session, and resets intent-specific fields.
    ///
    /// Non-intent-specific content (body, title, provenance) is preserved.
    func updateIntent(_ intent: AmenIntent) {
        guard config.allowedIntents.contains(intent) else { return }

        let newConfig = ComposerConfig.config(for: config.source, intent: intent)
        config = newConfig

        draft.selectedIntent = intent
        draft.audience       = newConfig.defaultAudience

        // Reset intent-specific fields on intent switch to avoid stale data.
        draft.prayerPrivacyLevel = "private"
        draft.isAnonymous        = false
        draft.jobTitle           = ""
        draft.jobOrganization    = ""
        draft.eventDate          = nil
        draft.scriptureReference = ""
    }

    // MARK: - Submit

    /// Validates the draft, runs the transform engine, and persists the new object
    /// via `AmenObjectRepository`.
    ///
    /// Sets `isSubmitting = true` during the async operation and toggles it off
    /// regardless of success or failure. On success `didSubmit` becomes `true`.
    func submit() async {
        guard isValid, !isSubmitting else { return }

        guard let currentUser = Auth.auth().currentUser, !currentUser.uid.isEmpty else {
            submitError = "You must be signed in to create content."
            return
        }

        isSubmitting = true
        submitError  = nil

        defer { isSubmitting = false }

        do {
            let actorId = currentUser.uid
            let intent  = draft.selectedIntent

            // Resolve AmenObjectType for the source (nil falls back to .post).
            let sourceObjectType = AmenObjectType(rawValue: config.source.type.amenObjectTypeRaw)
                ?? .post

            // Validate the (source x intent) combination via the engine.
            guard engine.isSupported(sourceType: sourceObjectType, intent: intent) else {
                throw TransformError.unsupportedCombination(
                    sourceType: sourceObjectType,
                    intent: intent
                )
            }

            // Determine the target collection from the transform config.
            let transformConfig  = engine.config(for: sourceObjectType, intent: intent)
            let targetCollection = transformConfig?.targetObjectType ?? "posts"

            // Build the payload of additional fields for the Firestore write.
            var additionalFields: [String: Any] = [
                "body":     draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
                "audience": draft.audience,
                "intent":   intent.rawValue
            ]

            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                additionalFields["title"] = trimmedTitle
            }

            if draft.selectedIntent == .pray {
                additionalFields["prayerPrivacyLevel"] = draft.prayerPrivacyLevel
                additionalFields["isAnonymous"]        = draft.isAnonymous
            }

            if draft.selectedIntent == .hire {
                additionalFields["jobTitle"]        = draft.jobTitle
                additionalFields["jobOrganization"] = draft.jobOrganization
            }

            if let eventDate = draft.eventDate {
                additionalFields["eventDate"] = eventDate
            }

            let trimmedScripture = draft.scriptureReference.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedScripture.isEmpty {
                additionalFields["scriptureReference"] = trimmedScripture
            }

            if let scheduled = draft.scheduledDate {
                additionalFields["scheduledAt"] = scheduled
            }

            additionalFields["locationEnabled"] = draft.locationEnabled

            // Build a minimal SpawnableObject stub to pass into the repository.
            // Provenance is attached by createSpawnedObject() via the engine.
            let lastPathComponent = draft.sourceRef
                .flatMap { $0.split(separator: "/").last.map(String.init) }
                ?? UUID().uuidString

            let stub = ComposerObjectStub(
                id:         lastPathComponent,
                createdBy:  config.source.existingOwnerId ?? actorId,
                provenance: provenanceFromDraft(actorId: actorId)
            )

            _ = try await repository.createSpawnedObject(
                from: stub,
                sourceObjectType: sourceObjectType,
                intent: intent,
                actorId: actorId,
                targetCollection: targetCollection,
                additionalFields: additionalFields
            )

            didSubmit = true

        } catch let transformErr as TransformError {
            submitError = transformErr.localizedMessage
        } catch {
            submitError = error.localizedDescription
        }
    }

    // MARK: - Private Helpers

    /// Builds the provenance record from the draft's source fields.
    /// `createdAt` is a placeholder — overwritten by `FieldValue.serverTimestamp()` in the repo.
    private func provenanceFromDraft(actorId: String) -> SpawnProvenance? {
        guard let sourceRef = draft.sourceRef, let sourceType = draft.sourceType else {
            return nil
        }
        return SpawnProvenance(
            sourceType:    sourceType,
            sourceRef:     sourceRef,
            sourceOwnerId: config.source.existingOwnerId,
            intent:        draft.selectedIntent.rawValue,
            createdAt:     Date()
        )
    }
}

// MARK: - TransformError + Localized Message

private extension TransformError {
    var localizedMessage: String {
        switch self {
        case .unsupportedCombination(let src, let intent):
            return "You can't \(intent.rawValue) a \(src.rawValue) object."
        case .actorNotAuthorized:
            return "You don't have permission to do this."
        case .sourceObjectNotFound:
            return "The source content could not be found."
        case .provenanceWriteFailed:
            return "Could not save provenance. Please try again."
        case .audienceCapExceeded:
            return "The audience you selected is wider than allowed for this content."
        case .featureFlagDisabled(let flag):
            return "This feature (\(flag)) is not enabled yet."
        case .orgNotVerified:
            return "Your organization must be verified before posting job roles."
        case .mentorConsentPending:
            return "The mentor hasn't accepted yet. Check back soon."
        case .missingRequiredProvenance(let field):
            return "Missing required field: \(field)."
        }
    }
}

// MARK: - ComposerObjectStub

/// A minimal SpawnableObject passed to `AmenObjectRepository.createSpawnedObject()`
/// when the composer is creating a brand-new or transform-derived object.
///
/// This avoids importing a full domain model for the sole purpose of satisfying
/// the generic `<S: SpawnableObject>` constraint in the repository.
struct ComposerObjectStub: SpawnableObject {
    let id: String
    let createdBy: String
    let createdAt: Date = Date()
    let updatedAt: Date = Date()
    let isDeleted: Bool = false
    let provenance: SpawnProvenance?
}

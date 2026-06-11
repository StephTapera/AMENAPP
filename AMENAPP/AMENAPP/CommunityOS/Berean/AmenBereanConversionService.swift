// AmenBereanConversionService.swift
// AMEN App — CommunityOS / Berean
//
// Phase 2 — Agent A4 (Berean Integration)
// Core engine that converts BereanCapture objects into canonical AMEN objects
// via the existing AmenTransformEngine + AmenObjectRepository pipeline.
//
// Design rules:
//   - Every conversion goes through AmenTransformEngine — no direct Firestore writes.
//   - Provenance is always written; sourceType is always "bereanInsight" (C2 matrix key).
//   - No screenshot workflow: conversions go directly to Firestore.
//   - async/await + @MainActor throughout.
//   - openInComposer() is the "unsaved" path — pre-fills AmenUniversalComposerView.
//
// SHARED TYPES:
//   AmenObjectType, AmenIntent, SpawnProvenance  →  CommunityObjectTypes.swift
//   AmenTransformEngine                          →  CommunityOS/Core/AmenTransformEngine.swift
//   AmenObjectRepository                         →  CommunityOS/Core/AmenObjectRepository.swift
//   ComposerSource, ComposerSourceType           →  CommunityOS/Composer/AmenComposerModels.swift
//   AmenDiscussionRoomType                       →  CommunityOS/Discussion/AmenDiscussionModels.swift
//   PrayerPrivacyLevel                           →  CommunityOS/Prayer/PrayerModels.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AmenBereanConversionService

/// Converts a `BereanCapture` into any canonical AMEN object.
///
/// All writes are routed through `AmenTransformEngine` to ensure the C2 matrix
/// is enforced and provenance is correctly populated. The service never writes
/// directly to Firestore outside the repository.
///
/// Usage:
/// ```swift
/// let service = AmenBereanConversionService()
/// let result = try await service.convertToPost(capture, actorId: uid)
/// ```
@MainActor
final class AmenBereanConversionService: ObservableObject {

    // MARK: - State

    @Published var isConverting: Bool = false
    @Published var lastConversionResult: BereanConversionResult?
    @Published var conversionError: String?

    // MARK: - Private Infrastructure

    private let engine      = AmenTransformEngine()
    private let repository  = AmenObjectRepository()
    private let db          = Firestore.firestore()

    // MARK: - Constants

    /// The AmenObjectType used for all Berean-sourced conversions.
    /// Must match the `bereanInsight` key in AmenTransformEngine.matrix.
    private static let bereanObjectType = AmenObjectType.bereanInsight

    // MARK: - convertToPost

    /// Converts a BereanCapture into an AmenPost (share or teach intent).
    ///
    /// Target collection: `posts`
    /// SpawnProvenance.sourceType: "bereanInsight"
    /// SpawnProvenance.intent:     "share"
    ///
    /// - Parameters:
    ///   - capture: The Berean output to convert.
    ///   - actorId: Firebase Auth UID of the initiating user.
    /// - Returns: A `BereanConversionResult` with the new document ID.
    func convertToPost(
        _ capture: BereanCapture,
        actorId: String
    ) async throws -> BereanConversionResult {
        isConverting = true
        conversionError = nil
        defer { isConverting = false }

        let intent = AmenIntent.share
        let provenance = buildProvenance(from: capture, intent: intent)

        // Build a synthetic spawnable stub that satisfies the repository contract.
        let stub = BereanInsightSourceObject(
            id:         capture.id,
            createdBy:  actorId,
            capturedAt: capture.capturedAt,
            provenance: provenance
        )

        let additionalFields: [String: Any] = [
            "body":          capture.content,
            "authorId":      actorId,
            "scriptureRefs": capture.scriptureRefs,
            "visibility":    "public",
            "audience":      "public_feed",
            "likeCount":     0,
            "commentCount":  0,
            "prayerCount":   0,
            "moderationStatus": "pending",
            "capabilities":  ["share", "save", "discuss", "pray"],
            "isDeleted":     false,
            "title":         capture.resolvedTitle
        ]

        let docId = try await repository.createSpawnedObject(
            from:                     stub,
            sourceObjectType:         Self.bereanObjectType,
            intent:                   intent,
            actorId:                  actorId,
            targetCollection:         "posts",
            additionalFields:         additionalFields
        )

        let result = BereanConversionResult(
            targetType:  "posts",
            documentId:  docId,
            provenance:  provenance,
            intent:      intent
        )
        lastConversionResult = result
        return result
    }

    // MARK: - convertToDiscussion

    /// Converts a BereanCapture into an AmenDiscussionRoom (discuss intent).
    ///
    /// Target collection: `amenDiscussionRooms`
    /// SpawnProvenance.sourceType: "bereanInsight"
    /// SpawnProvenance.intent:     "discuss"
    ///
    /// The capture title becomes the room title.
    /// The capture content becomes the room description and the seed for follow-up prompts.
    ///
    /// - Parameters:
    ///   - capture:        The Berean output to convert.
    ///   - roomType:       Functional type of the discussion room.
    ///                     Pass `.bibleStudy` for scripture studies, `.general` for answers.
    ///                     Uses `AmenDiscussionRoomType` from AmenDiscussionModels.swift.
    ///   - actorId:        Firebase Auth UID of the initiating user.
    func convertToDiscussion(
        _ capture: BereanCapture,
        roomType: AmenDiscussionRoomType,
        actorId: String
    ) async throws -> BereanConversionResult {
        isConverting = true
        conversionError = nil
        defer { isConverting = false }

        let intent = AmenIntent.discuss
        let provenance = buildProvenance(from: capture, intent: intent)

        let stub = BereanInsightSourceObject(
            id:         capture.id,
            createdBy:  actorId,
            capturedAt: capture.capturedAt,
            provenance: provenance
        )

        // Build follow-up prompts from study outline points (if available)
        let followUpPrompts: [String] = {
            if !capture.studyOutlinePoints.isEmpty {
                return capture.studyOutlinePoints
            }
            // Derive a seed follow-up from the first scripture ref if present
            if let firstRef = capture.scriptureRefs.first {
                return ["What does \(firstRef) mean for your life?"]
            }
            return []
        }()

        let additionalFields: [String: Any] = [
            "title":                capture.resolvedTitle,
            "description":          capture.content,
            "type":                 roomType.rawValue,
            "privacyLevel":         roomType.defaultPrivacyLevel.rawValue,
            "participationControl": "open",
            "sourceContextRef":     capture.provenanceRef,
            "sourceContextType":    AmenObjectType.bereanInsight.rawValue,
            "participantIds":       [actorId],
            "messageCount":         0,
            "followUpPrompts":      followUpPrompts,
            "moderatorIds":         [actorId],
            "isPinned":             false,
            "isDeleted":            false
        ]

        let docId = try await repository.createSpawnedObject(
            from:             stub,
            sourceObjectType: Self.bereanObjectType,
            intent:           intent,
            actorId:          actorId,
            targetCollection: "amenDiscussionRooms",
            additionalFields: additionalFields
        )

        let result = BereanConversionResult(
            targetType: "amenDiscussionRooms",
            documentId: docId,
            provenance: provenance,
            intent:     intent
        )
        lastConversionResult = result
        return result
    }

    // MARK: - convertToPrayerRequest

    /// Converts a BereanCapture (typically a prayerGuide capture) into a prayer request.
    ///
    /// Target collection: `prayers`
    /// SpawnProvenance.sourceType: "bereanInsight"
    /// SpawnProvenance.intent:     "pray"
    ///
    /// - Parameters:
    ///   - capture:  The Berean prayer guide content to convert.
    ///   - privacy:  Privacy level for the prayer request. Defaults to `.private`.
    ///   - actorId:  Firebase Auth UID of the initiating user.
    func convertToPrayerRequest(
        _ capture: BereanCapture,
        privacy: PrayerPrivacyLevel = .private,
        actorId: String
    ) async throws -> BereanConversionResult {
        isConverting = true
        conversionError = nil
        defer { isConverting = false }

        let intent = AmenIntent.pray
        let provenance = buildProvenance(from: capture, intent: intent)

        let stub = BereanInsightSourceObject(
            id:         capture.id,
            createdBy:  actorId,
            capturedAt: capture.capturedAt,
            provenance: provenance
        )

        let additionalFields: [String: Any] = [
            "title":             capture.resolvedTitle,
            "body":              capture.content,
            "authorUserId":      actorId,
            "privacyLevel":      privacy.rawValue,
            "isAnonymous":       false,
            "displayAuthorName": "",   // CF sets displayName from Auth profile
            "tags":              capture.scriptureRefs,
            "prayerCount":       0,
            "followUps":         [] as [String],
            "isAnswered":        false,
            "reminderScheduled": false,
            "isDeleted":         false
        ]

        let docId = try await repository.createSpawnedObject(
            from:             stub,
            sourceObjectType: Self.bereanObjectType,
            intent:           intent,
            actorId:          actorId,
            targetCollection: "prayers",
            additionalFields: additionalFields
        )

        let result = BereanConversionResult(
            targetType: "prayers",
            documentId: docId,
            provenance: provenance,
            intent:     intent
        )
        lastConversionResult = result
        return result
    }

    // MARK: - convertToStudyRoom

    /// Converts a BereanCapture into an AmenDiscussionRoom typed as a Bible study.
    ///
    /// Distinct from `convertToDiscussion` in that it:
    ///   - Forces `roomType = .bibleStudy`
    ///   - Uses the study outline points as pre-loaded follow-up prompts
    ///   - Sets participation control to `.open` to encourage group study
    ///
    /// Target collection: `amenDiscussionRooms`
    /// SpawnProvenance.intent:     "study"
    func convertToStudyRoom(
        _ capture: BereanCapture,
        actorId: String
    ) async throws -> BereanConversionResult {
        isConverting = true
        conversionError = nil
        defer { isConverting = false }

        let intent = AmenIntent.study
        let provenance = buildProvenance(from: capture, intent: intent)

        let stub = BereanInsightSourceObject(
            id:         capture.id,
            createdBy:  actorId,
            capturedAt: capture.capturedAt,
            provenance: provenance
        )

        // Study outline points become the follow-up prompts inside the room.
        let followUpPrompts: [String] = capture.studyOutlinePoints.isEmpty
            ? capture.scriptureRefs.map { "Explore \($0)" }
            : capture.studyOutlinePoints

        let additionalFields: [String: Any] = [
            "title":                capture.resolvedTitle,
            "description":          capture.content,
            "type":                 AmenDiscussionRoomType.bibleStudy.rawValue,
            "privacyLevel":         "public",   // AmenDiscussionPrivacyLevel.public.rawValue
            "participationControl": AmenDiscussionParticipationControl.open.rawValue,
            "sourceContextRef":     capture.provenanceRef,
            "sourceContextType":    AmenObjectType.bereanInsight.rawValue,
            "participantIds":       [actorId],
            "messageCount":         0,
            "followUpPrompts":      followUpPrompts,
            "moderatorIds":         [actorId],
            "isPinned":             false,
            "isDeleted":            false
        ]

        let docId = try await repository.createSpawnedObject(
            from:             stub,
            sourceObjectType: Self.bereanObjectType,
            intent:           intent,
            actorId:          actorId,
            targetCollection: "amenDiscussionRooms",
            additionalFields: additionalFields
        )

        let result = BereanConversionResult(
            targetType: "amenDiscussionRooms",
            documentId: docId,
            provenance: provenance,
            intent:     intent
        )
        lastConversionResult = result
        return result
    }

    // MARK: - convertToChurchNote

    /// Converts a BereanCapture into a new church note with scripture references attached.
    ///
    /// Target collection: `users/{actorId}/churchNotes`
    /// SpawnProvenance.sourceType: "bereanInsight"
    /// SpawnProvenance.intent:     "study"
    ///
    /// - Parameters:
    ///   - capture:    The Berean content to save as a note.
    ///   - churchRef:  Firestore church document ID to associate the note with.
    ///   - actorId:    Firebase Auth UID of the note owner.
    func convertToChurchNote(
        _ capture: BereanCapture,
        churchRef: String,
        actorId: String
    ) async throws -> BereanConversionResult {
        isConverting = true
        conversionError = nil
        defer { isConverting = false }

        let intent = AmenIntent.study
        let provenance = buildProvenance(from: capture, intent: intent)

        // Church notes are user-owned sub-collection documents.
        // Write directly via Firestore (sub-collection path not covered by createSpawnedObject).
        let noteRef = db
            .collection("users")
            .document(actorId)
            .collection("churchNotes")
            .document()

        let provenanceData: [String: Any] = [
            "sourceType":    provenance.sourceType,
            "sourceRef":     provenance.sourceRef ?? "",
            "sourceOwnerId": provenance.sourceOwnerId ?? "",
            "intent":        provenance.intent,
            "createdAt":     FieldValue.serverTimestamp()
        ]

        let payload: [String: Any] = [
            "id":              noteRef.documentID,
            "userId":          actorId,
            "noteType":        "berean",
            "title":           capture.resolvedTitle,
            "body":            capture.content,
            "churchId":        churchRef,
            "scriptureRefs":   capture.scriptureRefs,
            "tags":            [],
            "state":           "active",
            "aiSummary":       "",
            "provenance":      provenanceData,
            "createdBy":       actorId,
            "createdAt":       FieldValue.serverTimestamp(),
            "updatedAt":       FieldValue.serverTimestamp(),
            "isDeleted":       false
        ]

        try await noteRef.setData(payload)

        let result = BereanConversionResult(
            targetType: "churchNotes",
            documentId: noteRef.documentID,
            provenance: provenance,
            intent:     intent
        )
        lastConversionResult = result
        return result
    }

    // MARK: - convertToMentorshipTopic

    /// Converts a BereanCapture into a mentorship request topic.
    ///
    /// The Berean question or insight becomes the `focus` field on the mentorship object.
    /// Target collection: `mentorships`
    /// SpawnProvenance.intent:     "mentor"
    ///
    /// - Parameters:
    ///   - capture:  The Berean output whose question/topic drives the mentorship request.
    ///   - actorId:  Firebase Auth UID of the mentee (the user requesting mentorship).
    func convertToMentorshipTopic(
        _ capture: BereanCapture,
        actorId: String
    ) async throws -> BereanConversionResult {
        isConverting = true
        conversionError = nil
        defer { isConverting = false }

        let intent = AmenIntent.mentor
        let provenance = buildProvenance(from: capture, intent: intent)

        let stub = BereanInsightSourceObject(
            id:         capture.id,
            createdBy:  actorId,
            capturedAt: capture.capturedAt,
            provenance: provenance
        )

        let scriptureTheme: String = capture.scriptureRefs.first
            ?? capture.studyOutlinePoints.first
            ?? ""

        let additionalFields: [String: Any] = [
            "menteeUid":       actorId,
            "mentorUid":       "",          // Assigned after mentor accepts
            "status":          "requested",
            "focus":           capture.resolvedTitle,
            "scriptureTheme":  scriptureTheme,
            "sessionCount":    0,
            "isDeleted":       false
        ]

        let docId = try await repository.createSpawnedObject(
            from:             stub,
            sourceObjectType: Self.bereanObjectType,
            intent:           intent,
            actorId:          actorId,
            targetCollection: "mentorships",
            additionalFields: additionalFields
        )

        let result = BereanConversionResult(
            targetType: "mentorships",
            documentId: docId,
            provenance: provenance,
            intent:     intent
        )
        lastConversionResult = result
        return result
    }

    // MARK: - openInComposer

    /// Returns a `ComposerSource` pre-filled with the capture content, suitable for
    /// presenting `AmenUniversalComposerView` without triggering a Firestore write.
    ///
    /// This is the "drafting" path — the user can review and edit before committing.
    /// Provenance is preserved via `existingRef` and will be written when the composer submits.
    ///
    /// - Parameters:
    ///   - capture: The Berean output to pre-fill.
    ///   - intent:  The initial intent to select in the composer.
    /// - Returns: A `ComposerSource` ready for `AmenUniversalComposerView`.
    func openInComposer(_ capture: BereanCapture, intent: AmenIntent) -> ComposerSource {
        ComposerSource(
            type:            .bereanInsight,
            existingRef:     capture.provenanceRef,
            existingOwnerId: nil,           // Berean is the AI source, not a user
            prefillText:     capture.content,
            prefillTitle:    capture.title
        )
    }

    // MARK: - Private Helpers

    /// Builds a `SpawnProvenance` record for a given capture and intent.
    /// The `sourceType` is always "bereanInsight" to match the C2 matrix key.
    private func buildProvenance(from capture: BereanCapture, intent: AmenIntent) -> SpawnProvenance {
        SpawnProvenance(
            sourceType:    AmenObjectType.bereanInsight.rawValue,  // "bereanInsight"
            sourceRef:     capture.provenanceRef,
            sourceOwnerId: nil,     // Berean AI — no human owner
            intent:        intent.rawValue,
            createdAt:     Date()   // Overwritten by FieldValue.serverTimestamp() in repository
        )
    }
}

// MARK: - BereanInsightSourceObject (internal)

/// Minimal `SpawnableObject` stub used to feed `AmenObjectRepository.createSpawnedObject`.
///
/// `AmenObjectRepository` expects a `SpawnableObject` as the source. Since the actual
/// `AmenBereanInsight` document may live in a user sub-collection that requires a
/// separate read, we construct a lightweight stub with the provenance already set.
/// The repository uses the stub only to extract `id`, `createdBy`, and `provenance`.
private struct BereanInsightSourceObject: SpawnableObject {
    let id: String
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
    let provenance: SpawnProvenance?

    init(
        id: String,
        createdBy: String,
        capturedAt: Date,
        provenance: SpawnProvenance
    ) {
        self.id         = id
        self.createdBy  = createdBy
        self.createdAt  = capturedAt
        self.updatedAt  = capturedAt
        self.isDeleted  = false
        self.provenance = provenance
    }

    // Satisfy Codable (required by SpawnableObject → AmenObject → Codable)
    enum CodingKeys: String, CodingKey {
        case id, createdBy, createdAt, updatedAt, isDeleted, provenance
    }
}

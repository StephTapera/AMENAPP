import Foundation
import FirebaseFunctions
import FirebaseFirestore

// MARK: - ScriptureVerificationStatus

/// Segment-level audit trail for scripture references detected in prayer room transcripts.
/// Persisted as a field on each transcript chunk document in Firestore.
enum ScriptureVerificationStatus: String, Codable {
    /// References detected; async round-trip to verifyScriptureText CF not yet complete.
    case pending
    /// All detected references confirmed accurate by verifyScriptureText CF.
    case verified
    /// At least one reference did not match canonical text; escalated to GUARDIAN queue.
    case mismatch
    /// Backend could not resolve one or more references (unknown book, CF error, etc.).
    case unresolvable
    /// No scripture reference patterns detected in segment; no verification required.
    case notRequired
}

// MARK: - PrayerRoomModerationEngine

@MainActor
final class PrayerRoomModerationEngine {
    static let shared = PrayerRoomModerationEngine()

    private let moderationService: BereanRealtimeModerationService
    private let functions = Functions.functions()
    private lazy var db = Firestore.firestore()

    init(moderationService: BereanRealtimeModerationService? = nil) {
        self.moderationService = moderationService ?? BereanRealtimeModerationService()
    }

    func validatePrayerCaption(_ text: String, sessionId: String) async throws -> Bool {
        // Pass constitutionalMode: .guard to the moderateRealtimeTranscript CF (G-3).
        let passed = try await moderationService.validateTranscript(
            text,
            sessionId: sessionId,
            constitutionalMode: .guard
        )
        guard passed else { return false }

        // SECURITY FIX C-07: prayer room transcripts must also pass crisis detection.
        // Profanity/tone checks do not catch suicidal speech — assess here before
        // allowing the transcript to be persisted or broadcast.
        let riskService = WellnessRiskService.shared
        let assessments = riskService.assessLanguageRisk(
            text: text,
            isQuoted: false,
            isPublicPost: false,
            context: "prayer_room_transcript"
        )
        if !assessments.isEmpty {
            riskService.processLanguageRisk(assessments)
        }
        let riskLevel = riskService.currentRiskState.compositeRiskLevel
        if riskLevel == .imminentDanger || riskLevel == .highConcern {
            // Surface crisis intervention (already on MainActor); block the transcript.
            riskService.evaluateAndIntervene()
            return false
        }

        return true
    }

    /// Validates, persists, and asynchronously verifies any scripture references in the
    /// approved prayer caption segment (G-3).
    ///
    /// Flow:
    /// 1. If ScriptureReferenceValidator.requiresVerification returns false →
    ///    persist with scriptureVerification: .notRequired.
    /// 2. If references are detected:
    ///    a. Run structural validation on each detected ref.
    ///    b. Persist the segment immediately with scriptureVerification: .pending.
    ///    c. Async round-trip: call verifyScriptureText CF with detected refs.
    ///       - On success: update segment to .verified / .mismatch / .unresolvable.
    ///       - On mismatch: also escalate to /moderationQueue (GUARDIAN queue).
    ///    d. Segment is NEVER auto-deleted — human review only.
    func persistApprovedPrayerCaption(
        _ text: String,
        sessionId: String,
        language: BereanSupportedLanguage,
        targetLanguage: BereanSupportedLanguage? = nil,
        isFinal: Bool = true
    ) async throws {
        let requiresCheck = ScriptureReferenceValidator.requiresVerification(text)

        // Determine initial scripture verification status and extract references.
        let initialStatus: ScriptureVerificationStatus
        let detectedRefs: [String]

        if requiresCheck {
            detectedRefs = extractScriptureReferences(from: text)
            initialStatus = detectedRefs.isEmpty ? .notRequired : .pending
        } else {
            detectedRefs = []
            initialStatus = .notRequired
        }

        // Persist the segment. The CF persistRealtimeTranscriptChunk receives the
        // scriptureVerification field so it can be stored on the Firestore document.
        try await moderationService.persistApprovedChunk(
            sessionId: sessionId,
            text: text,
            kind: "prayer_room_caption",
            language: language,
            targetLanguage: targetLanguage,
            isFinal: isFinal,
            scriptureVerification: initialStatus
        )

        // If no scripture refs to verify, we're done.
        guard initialStatus == .pending, !detectedRefs.isEmpty else { return }

        // Async G-1 round-trip: do not block the caller.
        let capturedText = text
        let capturedRefs = detectedRefs
        Task {
            await self.runScriptureVerificationRoundTrip(
                sessionId: sessionId,
                text: capturedText,
                detectedRefs: capturedRefs
            )
        }
    }

    // MARK: - Private: Scripture Extraction

    /// Extracts all scripture reference strings from `text` using the same heuristic
    /// pattern as ScriptureReferenceValidator.requiresVerification, returning only those
    /// that pass structural (book + bounds) validation.
    private func extractScriptureReferences(from text: String) -> [String] {
        let pattern = #"[1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)?\s+\d+:\d+(?:-\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match -> String? in
            guard let r = Range(match.range, in: text) else { return nil }
            let candidate = String(text[r])
            // Filter to only known-valid refs (structural validation).
            let result = ScriptureReferenceValidator.validate(candidate)
            switch result {
            case .valid:
                return candidate
            case .unknownBook, .outOfRange, .malformed:
                // Include unknown-book / out-of-range refs for backend round-trip so
                // the CF can attempt resolution; malformed refs are discarded.
                if case .malformed = result { return nil }
                return candidate
            }
        }
    }

    // MARK: - Private: Async Round-Trip Verification (G-1)

    /// Calls the `verifyScriptureText` Firebase callable with all detected references.
    /// On completion, updates the persisted segment's `scriptureVerification` field and,
    /// on mismatch, escalates to the GUARDIAN moderation queue (/moderationQueue).
    ///
    /// The segment document is NEVER deleted automatically — human review only.
    private func runScriptureVerificationRoundTrip(
        sessionId: String,
        text: String,
        detectedRefs: [String]
    ) async {
        // Build claimed-texts map: for this path we treat the surrounding text as the
        // claimed text context. A richer implementation would extract the verse quote;
        // here we pass the full segment as a conservative over-approximation.
        var claimedTexts: [String: String] = [:]
        for ref in detectedRefs {
            claimedTexts[ref] = text
        }

        let report = await ScriptureReferenceValidator.verifyWithAPIPipeline(
            references: detectedRefs,
            claimedTexts: claimedTexts,
            translation: "ESV",
            mode: .guard
        )

        // Determine final status from report.
        let hasMismatches    = !report.mismatchRefs.isEmpty
        let hasUnresolvable  = !report.unresolvableRefs.isEmpty
        let finalStatus: ScriptureVerificationStatus

        if hasMismatches {
            finalStatus = .mismatch
        } else if hasUnresolvable && report.verifiedRefs.isEmpty {
            finalStatus = .unresolvable
        } else {
            finalStatus = .verified
        }

        // Update the persisted segment in Firestore.
        // Documents are written by persistRealtimeTranscriptChunk CF under:
        //   realtimeSessions/{sessionId}/chunks/{chunkId}
        // We query by sessionId + text to locate the chunk(s) written moments ago.
        await updateSegmentScriptureStatus(
            sessionId: sessionId,
            text: text,
            status: finalStatus,
            canonicalText: report.mismatchRefs.first?.canonicalText
        )

        // Mismatch: escalate to GUARDIAN moderation queue (/moderationQueue).
        // This is the same collection used by ModerationPipeline, AmenModerationService,
        // MessageSafetyGateway, MediaSafetyGateway, and AmenChildSafetyService.
        // DO NOT delete or censor the segment — humans review.
        if hasMismatches {
            await escalateToGuardianQueue(
                sessionId: sessionId,
                text: text,
                mismatchRefs: report.mismatchRefs
            )
        }
    }

    // MARK: - Private: Firestore Segment Update

    private func updateSegmentScriptureStatus(
        sessionId: String,
        text: String,
        status: ScriptureVerificationStatus,
        canonicalText: String?
    ) async {
        // Locate the chunk document(s) just written for this session + text.
        let chunksRef = db
            .collection("realtimeSessions")
            .document(sessionId)
            .collection("chunks")

        do {
            let snap = try await chunksRef
                .whereField("text", isEqualTo: text)
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()

            guard let doc = snap.documents.first else { return }

            var update: [String: Any] = [
                "scriptureVerification": status.rawValue,
                "scriptureVerifiedAt": FieldValue.serverTimestamp(),
            ]
            if let canonical = canonicalText {
                update["scriptureCanonicalText"] = canonical
            }

            try await doc.reference.updateData(update)
        } catch {
            // Non-fatal: the segment is still persisted with .pending status.
            print("PrayerRoomModerationEngine: failed to update scripture status — \(error.localizedDescription)")
        }
    }

    // MARK: - Private: GUARDIAN Queue Escalation

    /// Writes a mismatch event to /moderationQueue — the canonical GUARDIAN escalation
    /// collection shared with ModerationPipeline.queueForHumanReview (ModerationPipeline.swift:464),
    /// AmenModerationService (AmenModerationService.swift:100),
    /// MessageSafetyGateway (MessageSafetyGateway.swift:717),
    /// MediaSafetyGateway (MediaSafetyGateway.swift:465), and
    /// AmenChildSafetyService (AmenChildSafetyService.swift:324).
    private func escalateToGuardianQueue(
        sessionId: String,
        text: String,
        mismatchRefs: [ScriptureReferenceValidator.ScriptureMismatch]
    ) async {
        let mismatchPayload: [[String: String]] = mismatchRefs.map { m in
            ["ref": m.ref, "claimedText": m.claimedText, "canonicalText": m.canonicalText]
        }

        let data: [String: Any] = [
            "context": "prayer_room_transcript",
            "category": "scripture_mismatch",
            "sessionId": sessionId,
            "segmentText": text,
            "mismatchRefs": mismatchPayload,
            "riskScore": 0.6,    // Informational; not a safety-critical block.
            "status": "pending",
            "escalateImmediately": false,
            "source": "PrayerRoomModerationEngine",
            "constitutionalMode": BereanConstitutionalMode.guard.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
        ]

        do {
            try await db.collection("moderationQueue").addDocument(data: data)
        } catch {
            print("PrayerRoomModerationEngine: failed to write scripture mismatch to moderationQueue — \(error.localizedDescription)")
        }
    }
}

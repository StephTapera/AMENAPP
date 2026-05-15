#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - ChurchNoteProcessingStatus

@Suite("ChurchNoteProcessingStatus")
struct ChurchNoteProcessingStatusTests {

    // MARK: displayLabel

    @Test("All statuses have non-empty display labels")
    func allStatusDisplayLabels() {
        let statuses: [ChurchNoteProcessingStatus] = [
            .queued, .uploading, .processing, .draftReady,
            .approved, .rejected, .failed, .canceled,
        ]
        for status in statuses {
            #expect(!status.displayLabel.isEmpty, "displayLabel should not be empty for \(status)")
        }
    }

    @Test("draftReady label communicates review requirement")
    func draftReadyLabelMentionsReview() {
        let label = ChurchNoteProcessingStatus.draftReady.displayLabel.lowercased()
        #expect(label.contains("review") || label.contains("draft"),
                "draftReady label should mention review or draft: \(label)")
    }

    // MARK: isTerminal

    @Test("Terminal statuses: approved, rejected, failed, canceled")
    func terminalStatuses() {
        #expect(ChurchNoteProcessingStatus.approved.isTerminal)
        #expect(ChurchNoteProcessingStatus.rejected.isTerminal)
        #expect(ChurchNoteProcessingStatus.failed.isTerminal)
        #expect(ChurchNoteProcessingStatus.canceled.isTerminal)
    }

    @Test("Non-terminal statuses: queued, uploading, processing, draftReady")
    func nonTerminalStatuses() {
        #expect(!ChurchNoteProcessingStatus.queued.isTerminal)
        #expect(!ChurchNoteProcessingStatus.uploading.isTerminal)
        #expect(!ChurchNoteProcessingStatus.processing.isTerminal)
        #expect(!ChurchNoteProcessingStatus.draftReady.isTerminal)
    }

    // MARK: isActionable

    @Test("Only draftReady is actionable (requires user review)")
    func onlyDraftReadyIsActionable() {
        #expect(ChurchNoteProcessingStatus.draftReady.isActionable)
    }

    @Test("No other status is actionable")
    func noOtherStatusIsActionable() {
        let nonActionable: [ChurchNoteProcessingStatus] = [
            .queued, .uploading, .processing,
            .approved, .rejected, .failed, .canceled,
        ]
        for status in nonActionable {
            #expect(!status.isActionable, "\(status) should not be actionable")
        }
    }

    // MARK: Codable round-trip

    @Test("All statuses survive Codable round-trip")
    func codableRoundTrip() throws {
        let statuses: [ChurchNoteProcessingStatus] = [
            .queued, .uploading, .processing, .draftReady,
            .approved, .rejected, .failed, .canceled,
        ]
        for status in statuses {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ChurchNoteProcessingStatus.self, from: encoded)
            #expect(decoded == status)
        }
    }
}

// MARK: - ChurchNoteMediaSourceType

@Suite("ChurchNoteMediaSourceType")
struct ChurchNoteMediaSourceTypeTests {

    @Test("All source types have non-empty display labels")
    func allDisplayLabels() {
        for type_ in [ChurchNoteMediaSourceType.audio, .image, .video, .manual] {
            #expect(!type_.displayLabel.isEmpty)
        }
    }

    @Test("All source types have non-empty SF Symbols")
    func allSFSymbols() {
        for type_ in [ChurchNoteMediaSourceType.audio, .image, .video, .manual] {
            #expect(!type_.sfSymbol.isEmpty)
        }
    }

    @Test("audio uses mic symbol")
    func audioUsesMicSymbol() {
        #expect(ChurchNoteMediaSourceType.audio.sfSymbol.contains("mic"))
    }

    @Test("image uses camera symbol")
    func imageusesCameraSymbol() {
        #expect(ChurchNoteMediaSourceType.image.sfSymbol.contains("camera"))
    }

    @Test("Codable round-trip preserves all source types")
    func codableRoundTrip() throws {
        for type_ in [ChurchNoteMediaSourceType.audio, .image, .video, .manual] {
            let encoded = try JSONEncoder().encode(type_)
            let decoded = try JSONDecoder().decode(ChurchNoteMediaSourceType.self, from: encoded)
            #expect(decoded == type_)
        }
    }
}

// MARK: - ChurchNoteDraftField

@Suite("ChurchNoteDraftField")
struct ChurchNoteDraftFieldTests {

    @Test("All draft fields have non-empty display labels")
    func allDisplayLabels() {
        for field in ChurchNoteDraftField.allCases {
            #expect(!field.displayLabel.isEmpty)
        }
    }

    @Test("All draft fields have non-empty approval warnings")
    func allApprovalWarnings() {
        for field in ChurchNoteDraftField.allCases {
            #expect(!field.approvalWarning.isEmpty)
        }
    }

    @Test("Approval warning mentions review")
    func approvalWarningMentionsReview() {
        for field in ChurchNoteDraftField.allCases {
            let warning = field.approvalWarning.lowercased()
            #expect(warning.contains("review") || warning.contains("carefully"),
                    "Approval warning should prompt careful review: \(field)")
        }
    }

    @Test("There are exactly 5 draft field cases")
    func fiveDraftFields() {
        #expect(ChurchNoteDraftField.allCases.count == 5)
    }

    @Test("Draft field raw values match expected strings (allowlist parity with backend)")
    func rawValueParity() {
        #expect(ChurchNoteDraftField.transcriptText.rawValue  == "transcriptText")
        #expect(ChurchNoteDraftField.ocrText.rawValue          == "ocrText")
        #expect(ChurchNoteDraftField.summaryDraft.rawValue     == "summaryDraft")
        #expect(ChurchNoteDraftField.studyGuideDraft.rawValue  == "studyGuideDraft")
        #expect(ChurchNoteDraftField.prayerPromptsDraft.rawValue == "prayerPromptsDraft")
    }

    @Test("Codable round-trip for all draft fields")
    func codableRoundTrip() throws {
        for field in ChurchNoteDraftField.allCases {
            let encoded = try JSONEncoder().encode(field)
            let decoded = try JSONDecoder().decode(ChurchNoteDraftField.self, from: encoded)
            #expect(decoded == field)
        }
    }
}

// MARK: - ChurchNoteUploadState

@Suite("ChurchNoteUploadState")
struct ChurchNoteUploadStateTests {

    @Test("idle phase is not in-flight")
    func idleIsNotInFlight() {
        #expect(!ChurchNoteUploadState(phase: .idle).isInFlight)
    }

    @Test("preparing phase is in-flight")
    func preparingIsInFlight() {
        #expect(ChurchNoteUploadState(phase: .preparing).isInFlight)
    }

    @Test("uploading(progress:) phase is in-flight")
    func uploadingIsInFlight() {
        #expect(ChurchNoteUploadState(phase: .uploading(progress: 0.5)).isInFlight)
        #expect(ChurchNoteUploadState(phase: .uploading(progress: 0.0)).isInFlight)
        #expect(ChurchNoteUploadState(phase: .uploading(progress: 1.0)).isInFlight)
    }

    @Test("uploading100 phase is in-flight")
    func uploading100IsInFlight() {
        #expect(ChurchNoteUploadState(phase: .uploading100).isInFlight)
    }

    @Test("failed phase is not in-flight")
    func failedIsNotInFlight() {
        #expect(!ChurchNoteUploadState(phase: .failed(message: "Error")).isInFlight)
    }

    @Test("complete phase is not in-flight")
    func completeIsNotInFlight() {
        #expect(!ChurchNoteUploadState(phase: .complete(storagePath: "churchNotes/uid/note/audio/f.m4a")).isInFlight)
    }

    @Test("Phase equality — idle phases are equal")
    func idlePhaseEquality() {
        let a = ChurchNoteUploadState(phase: .idle)
        let b = ChurchNoteUploadState(phase: .idle)
        #expect(a.phase == b.phase)
    }

    @Test("Phase equality — different upload progress values are distinct")
    func uploadProgressDistinct() {
        let low  = ChurchNoteUploadState.Phase.uploading(progress: 0.2)
        let high = ChurchNoteUploadState.Phase.uploading(progress: 0.8)
        #expect(low != high)
    }
}

// MARK: - ChurchNoteProcessingJob.availableDraftFields

@Suite("ChurchNoteProcessingJob — availableDraftFields")
struct ChurchNoteProcessingJobAvailableFieldsTests {

    private func makeJob(
        transcriptText: String?    = nil,
        ocrText: String?           = nil,
        summaryDraft: String?      = nil,
        studyGuideDraft: String?   = nil,
        prayerPromptsDraft: String? = nil
    ) -> ChurchNoteProcessingJob {
        ChurchNoteProcessingJob(
            id: "job-1",
            userId: "uid-1",
            churchNoteId: "note-1",
            sourceType: .audio,
            storagePath: "churchNotes/uid-1/note-1/audio/f.m4a",
            fileSizeBytes: 1_000_000,
            durationSeconds: 600,
            status: .draftReady,
            progress: 100,
            transcriptText: transcriptText,
            ocrText: ocrText,
            extractedOutline: nil,
            summaryDraft: summaryDraft,
            studyGuideDraft: studyGuideDraft,
            prayerPromptsDraft: prayerPromptsDraft,
            safetyStatus: "passed",
            moderationStatus: "approved",
            errorCode: nil,
            errorMessage: nil,
            createdAt: nil,
            updatedAt: nil,
            completedAt: nil,
            approvedTranscriptText: nil,
            approvedOcrText: nil,
            approvedSummaryDraft: nil,
            approvedStudyGuideDraft: nil,
            approvedPrayerPromptsDraft: nil
        )
    }

    @Test("No fields available when all nil")
    func noFieldsWhenAllNil() {
        let job = makeJob()
        #expect(job.availableDraftFields.isEmpty)
    }

    @Test("transcriptText field available when set")
    func transcriptTextAvailable() {
        let job = makeJob(transcriptText: "Today's sermon was about grace.")
        let fields = job.availableDraftFields.map(\.field)
        #expect(fields.contains(.transcriptText))
    }

    @Test("ocrText field available when set")
    func ocrTextAvailable() {
        let job = makeJob(ocrText: "Board text: John 3:16")
        let fields = job.availableDraftFields.map(\.field)
        #expect(fields.contains(.ocrText))
    }

    @Test("Multiple fields available simultaneously")
    func multipleFieldsAvailable() {
        let job = makeJob(
            transcriptText: "Sermon transcript content here.",
            summaryDraft: "A concise summary of the sermon.",
            studyGuideDraft: "Study guide questions."
        )
        let fields = job.availableDraftFields.map(\.field)
        #expect(fields.contains(.transcriptText))
        #expect(fields.contains(.summaryDraft))
        #expect(fields.contains(.studyGuideDraft))
        #expect(!fields.contains(.ocrText))
        #expect(!fields.contains(.prayerPromptsDraft))
    }

    @Test("Empty string is excluded from available fields")
    func emptyStringExcluded() {
        let job = makeJob(transcriptText: "", ocrText: "Valid OCR text here.")
        let fields = job.availableDraftFields.map(\.field)
        #expect(!fields.contains(.transcriptText), "Empty transcriptText should be excluded")
        #expect(fields.contains(.ocrText))
    }

    @Test("Field text matches the original content")
    func fieldTextPreserved() {
        let text = "Sermon text: The grace of God is boundless."
        let job = makeJob(transcriptText: text)
        let pair = job.availableDraftFields.first { $0.field == .transcriptText }
        #expect(pair?.text == text)
    }

    @Test("All five fields available when all set")
    func allFiveFieldsAvailable() {
        let job = makeJob(
            transcriptText: "Transcript.",
            ocrText: "OCR text.",
            summaryDraft: "Summary.",
            studyGuideDraft: "Study guide.",
            prayerPromptsDraft: "Prayer prompts."
        )
        #expect(job.availableDraftFields.count == 5)
    }

    // MARK: - primaryDraftText

    @Test("primaryDraftText prefers transcriptText over ocrText")
    func primaryTextPrefersTranscript() {
        let job = makeJob(transcriptText: "Transcript", ocrText: "OCR")
        #expect(job.primaryDraftText == "Transcript")
    }

    @Test("primaryDraftText falls back to ocrText when no transcript")
    func primaryTextFallsBackToOCR() {
        let job = makeJob(ocrText: "OCR text")
        #expect(job.primaryDraftText == "OCR text")
    }

    @Test("primaryDraftText is nil when both nil")
    func primaryTextNilWhenBothNil() {
        let job = makeJob()
        #expect(job.primaryDraftText == nil)
    }

    // MARK: - isSafeForDisplay

    @Test("isSafeForDisplay is true when safetyStatus is 'passed'")
    func safeForDisplayWhenPassed() {
        var job = makeJob(transcriptText: "Content")
        // job.safetyStatus is set to "passed" in makeJob()
        #expect(job.isSafeForDisplay)
    }

    @Test("isSafeForDisplay is false when safetyStatus is 'flagged'")
    func notSafeForDisplayWhenFlagged() {
        let job = ChurchNoteProcessingJob(
            id: "job-flagged",
            userId: "uid-1",
            churchNoteId: "note-1",
            sourceType: .audio,
            storagePath: "churchNotes/uid-1/note-1/audio/f.m4a",
            fileSizeBytes: 1_000_000,
            durationSeconds: nil,
            status: .draftReady,
            progress: 100,
            transcriptText: "Flagged content.",
            ocrText: nil,
            extractedOutline: nil,
            summaryDraft: nil,
            studyGuideDraft: nil,
            prayerPromptsDraft: nil,
            safetyStatus: "flagged",
            moderationStatus: "review_required",
            errorCode: nil,
            errorMessage: nil,
            createdAt: nil,
            updatedAt: nil,
            completedAt: nil,
            approvedTranscriptText: nil,
            approvedOcrText: nil,
            approvedSummaryDraft: nil,
            approvedStudyGuideDraft: nil,
            approvedPrayerPromptsDraft: nil
        )
        #expect(!job.isSafeForDisplay)
    }
}

// MARK: - ChurchNoteDraftApprovalResult

@Suite("ChurchNoteDraftApprovalResult")
struct ChurchNoteDraftApprovalResultTests {

    @Test("Result stores all fields correctly")
    func storesFields() {
        let result = ChurchNoteDraftApprovalResult(
            jobId: "job-1",
            noteId: "note-1",
            draftField: .transcriptText,
            approvedText: "This is the approved sermon transcript.",
            sourceType: "audio"
        )
        #expect(result.jobId == "job-1")
        #expect(result.noteId == "note-1")
        #expect(result.draftField == .transcriptText)
        #expect(result.approvedText == "This is the approved sermon transcript.")
        #expect(result.sourceType == "audio")
    }

    @Test("User-edited text replaces original in result")
    func userEditReplacesOriginal() {
        let original = ChurchNoteDraftApprovalResult(
            jobId: "j", noteId: "n", draftField: .summaryDraft,
            approvedText: "AI-generated summary.", sourceType: "audio"
        )
        let userEdited = ChurchNoteDraftApprovalResult(
            jobId: original.jobId, noteId: original.noteId,
            draftField: original.draftField,
            approvedText: "User-corrected summary.",
            sourceType: original.sourceType
        )
        #expect(userEdited.approvedText == "User-corrected summary.")
        #expect(userEdited.approvedText != original.approvedText)
    }
}

// MARK: - ChurchNoteJobCreationRequest

@Suite("ChurchNoteJobCreationRequest")
struct ChurchNoteJobCreationRequestTests {

    @Test("Audio request stores all required fields")
    func audioRequestFields() {
        let req = ChurchNoteJobCreationRequest(
            noteId: "note-abc",
            sourceType: .audio,
            storagePath: "churchNotes/uid/note-abc/audio/recording.m4a",
            fileSizeBytes: 50_000_000,
            durationSeconds: 3600
        )
        #expect(req.noteId == "note-abc")
        #expect(req.sourceType == .audio)
        #expect(req.fileSizeBytes == 50_000_000)
        #expect(req.durationSeconds == 3600)
    }

    @Test("Image request has nil durationSeconds")
    func imageRequestNilDuration() {
        let req = ChurchNoteJobCreationRequest(
            noteId: "note-xyz",
            sourceType: .image,
            storagePath: "churchNotes/uid/note-xyz/images/scan.jpg",
            fileSizeBytes: 2_000_000,
            durationSeconds: nil
        )
        #expect(req.durationSeconds == nil)
        #expect(req.sourceType == .image)
    }
}

#else
import Foundation

// Stubs for environments where Testing framework is unavailable.
struct ChurchNotesMediaIntelligenceTests {}
struct ChurchNoteProcessingStatusTests {}
struct ChurchNoteMediaSourceTypeTests {}
struct ChurchNoteDraftFieldTests {}
struct ChurchNoteUploadStateTests {}
struct ChurchNoteProcessingJobAvailableFieldsTests {}
struct ChurchNoteDraftApprovalResultTests {}
struct ChurchNoteJobCreationRequestTests {}
#endif

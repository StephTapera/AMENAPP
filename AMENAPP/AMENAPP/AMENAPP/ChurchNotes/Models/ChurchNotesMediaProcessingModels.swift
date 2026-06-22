import Foundation
import FirebaseFirestore

// MARK: - Processing Job Status

enum ChurchNoteProcessingStatus: String, Codable, Equatable {
    case queued
    case uploading
    case processing
    case draftReady
    case approved
    case rejected
    case failed
    case canceled

    var displayLabel: String {
        switch self {
        case .queued:      return "In queue…"
        case .uploading:   return "Uploading…"
        case .processing:  return "Processing…"
        case .draftReady:  return "Draft ready — review required"
        case .approved:    return "Draft approved"
        case .rejected:    return "Draft rejected"
        case .failed:      return "Processing failed"
        case .canceled:    return "Canceled"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .approved, .rejected, .failed, .canceled: return true
        default: return false
        }
    }

    var isActionable: Bool {
        self == .draftReady
    }
}

// MARK: - Source Type

enum ChurchNoteMediaSourceType: String, Codable, Equatable {
    case audio
    case image
    case video
    case document
    case manual

    var displayLabel: String {
        switch self {
        case .audio:    return "Sermon Recording"
        case .image:    return "Photo / Scan"
        case .video:    return "Video"
        case .document: return "Document"
        case .manual:   return "Typed Note"
        }
    }

    var sfSymbol: String {
        switch self {
        case .audio:    return "mic.fill"
        case .image:    return "camera.fill"
        case .video:    return "video.fill"
        case .document: return "doc.richtext.fill"
        case .manual:   return "doc.text.fill"
        }
    }
}

// MARK: - Draft Field Type

enum ChurchNoteDraftField: String, Codable, Equatable, CaseIterable {
    case transcriptText
    case ocrText
    case summaryDraft
    case studyGuideDraft
    case prayerPromptsDraft

    var displayLabel: String {
        switch self {
        case .transcriptText:     return "Transcript"
        case .ocrText:            return "Extracted Text"
        case .summaryDraft:       return "Sermon Summary"
        case .studyGuideDraft:    return "Study Guide"
        case .prayerPromptsDraft: return "Prayer Prompts"
        }
    }

    var approvalWarning: String {
        "AI-assisted draft — review carefully before saving to your notes."
    }
}

// MARK: - Processing Job

/// Mirrors the server document at churchNotes/{noteId}/processingJobs/{jobId}.
/// This struct is read-only from the client — all server-owned fields
/// are populated by Cloud Functions, never by direct client writes.
struct ChurchNoteProcessingJob: Identifiable, Codable, Equatable {
    let id: String              // = jobId field
    let userId: String
    let churchNoteId: String
    let sourceType: ChurchNoteMediaSourceType
    let storagePath: String
    let fileSizeBytes: Int
    let durationSeconds: Double?

    // Server-owned status fields
    var status: ChurchNoteProcessingStatus
    var progress: Double

    // Server-owned output fields — never written by client
    var transcriptText: String?
    var ocrText: String?
    var extractedOutline: String?
    var summaryDraft: String?
    var studyGuideDraft: String?
    var prayerPromptsDraft: String?

    // Server-owned safety/moderation
    var safetyStatus: String?
    var moderationStatus: String?

    // Error info
    var errorCode: String?
    var errorMessage: String?

    // Timestamps
    var createdAt: Date?
    var updatedAt: Date?
    var completedAt: Date?

    // Approval tracking (set by backend approval callable)
    var approvedTranscriptText: Bool?
    var approvedOcrText: Bool?
    var approvedSummaryDraft: Bool?
    var approvedStudyGuideDraft: Bool?
    var approvedPrayerPromptsDraft: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "jobId"
        case userId, churchNoteId, sourceType, storagePath
        case fileSizeBytes, durationSeconds
        case status, progress
        case transcriptText, ocrText, extractedOutline
        case summaryDraft, studyGuideDraft, prayerPromptsDraft
        case safetyStatus, moderationStatus
        case errorCode, errorMessage
        case createdAt, updatedAt, completedAt
        case approvedTranscriptText = "approved_transcriptText"
        case approvedOcrText = "approved_ocrText"
        case approvedSummaryDraft = "approved_summaryDraft"
        case approvedStudyGuideDraft = "approved_studyGuideDraft"
        case approvedPrayerPromptsDraft = "approved_prayerPromptsDraft"
    }

    /// The primary draft text available for review, based on source type.
    var primaryDraftText: String? {
        transcriptText ?? ocrText
    }

    /// Returns available draft fields that have content for review.
    var availableDraftFields: [(field: ChurchNoteDraftField, text: String)] {
        var result: [(ChurchNoteDraftField, String)] = []
        if let t = transcriptText,     !t.isEmpty { result.append((.transcriptText,     t)) }
        if let o = ocrText,            !o.isEmpty { result.append((.ocrText,            o)) }
        if let s = summaryDraft,       !s.isEmpty { result.append((.summaryDraft,       s)) }
        if let g = studyGuideDraft,    !g.isEmpty { result.append((.studyGuideDraft,    g)) }
        if let p = prayerPromptsDraft, !p.isEmpty { result.append((.prayerPromptsDraft, p)) }
        return result
    }

    /// True if safety passed or is not yet determined (optimistic for UX — server is authoritative).
    var isSafeForDisplay: Bool {
        safetyStatus != "flagged"
    }
}

// MARK: - Upload State

/// Tracks local upload progress before the processing job exists on the server.
struct ChurchNoteUploadState: Equatable {
    enum Phase: Equatable {
        case idle
        case preparing
        case uploading(progress: Double)
        case uploading100
        case failed(message: String)
        case complete(storagePath: String)
    }
    var phase: Phase = .idle
    var localFileURL: URL?
    var mediaSourceType: ChurchNoteMediaSourceType = .audio

    var isInFlight: Bool {
        switch phase {
        case .preparing, .uploading, .uploading100: return true
        default: return false
        }
    }
}

// MARK: - Job Creation Request

struct ChurchNoteJobCreationRequest {
    let noteId: String
    let sourceType: ChurchNoteMediaSourceType
    let storagePath: String
    let fileSizeBytes: Int
    let durationSeconds: Double?
}

// MARK: - Draft Approval Result

struct ChurchNoteDraftApprovalResult {
    let jobId: String
    let noteId: String
    let draftField: ChurchNoteDraftField
    let approvedText: String
    let sourceType: String
}

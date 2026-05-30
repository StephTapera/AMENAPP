
//
//  ImportJobModels.swift
//  AMENAPP
//
//  Server-tracked import pipeline models.
//  These complement the existing ImportModels.swift (client-only local flow)
//  with a Firestore-backed job/candidate structure that survives app restarts
//  and feeds the Berean conversion gate.
//
//  Schema:
//    importJobs/{uid}/jobs/{jobId}           → ImportJob
//    importJobs/{uid}/jobs/{jobId}/candidates/{candidateId} → ImportCandidate
//

import Foundation
import FirebaseFirestore

// MARK: - ImportJob

struct ImportJob: Identifiable, Codable {
    @DocumentID var id: String?

    var source: ImportJobSource
    var status: ImportJobStatus
    var counts: ImportJobCounts
    var createdAt: Date
    var error: String?

    enum CodingKeys: String, CodingKey {
        case id, source, status, counts, createdAt, error
    }
}

enum ImportJobSource: String, Codable, CaseIterable {
    case instagram  = "instagram"
    case threads    = "threads"
    case facebook   = "facebook"
    case generic    = "generic"

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .threads:   return "Threads"
        case .facebook:  return "Facebook"
        case .generic:   return "Other Platform"
        }
    }

    var icon: String {
        switch self {
        case .instagram: return "camera.filters"
        case .threads:   return "bubble.left.and.bubble.right"
        case .facebook:  return "person.2"
        case .generic:   return "square.and.arrow.down"
        }
    }
}

enum ImportJobStatus: String, Codable {
    case uploading    = "uploading"
    case queued       = "queued"
    case parsing      = "parsing"
    case classifying  = "classifying"
    case ready        = "ready"
    case committing   = "committing"
    case done         = "done"
    case failed       = "failed"

    var displayLabel: String {
        switch self {
        case .uploading:   return "Uploading archive…"
        case .queued:      return "Queued for processing…"
        case .parsing:     return "Reading your posts…"
        case .classifying: return "Berean is reviewing…"
        case .ready:       return "Ready to review"
        case .committing:  return "Bringing posts over…"
        case .done:        return "Complete"
        case .failed:      return "Failed"
        }
    }

    var isTerminal: Bool {
        self == .done || self == .failed
    }

    var isProcessing: Bool {
        switch self {
        case .queued, .parsing, .classifying: return true
        default: return false
        }
    }
}

struct ImportJobCounts: Codable {
    var found: Int
    var candidates: Int
    var imported: Int

    init(found: Int = 0, candidates: Int = 0, imported: Int = 0) {
        self.found = found
        self.candidates = candidates
        self.imported = imported
    }
}

// MARK: - ImportCandidate

struct ImportCandidate: Identifiable, Codable {
    @DocumentID var id: String?

    var sourceType: ImportCandidateSourceType
    var originalText: String
    var mediaRefs: [String]             // Storage paths imports/{uid}/{jobId}/media/...
    var originalTimestamp: Date?
    var bereanClassification: BereanImportClassification?
    var provenance: ImportProvenance
    var userDecision: UserImportDecision

    enum CodingKeys: String, CodingKey {
        case id, sourceType, originalText, mediaRefs, originalTimestamp,
             bereanClassification, provenance, userDecision
    }

    var keepRecommended: Bool {
        bereanClassification?.keepRecommended ?? false
    }

    var isPerformative: Bool {
        bereanClassification?.performativeFlag ?? false
    }

    var displayText: String {
        if let draft = bereanClassification?.reconsecratedDraft, !draft.isEmpty {
            return draft
        }
        return originalText
    }
}

enum ImportCandidateSourceType: String, Codable {
    case post   = "post"
    case reel   = "reel"
    case story  = "story"
    case thread = "thread"
    case note   = "note"

    var icon: String {
        switch self {
        case .post:   return "doc.text"
        case .reel:   return "film"
        case .story:  return "clock"
        case .thread: return "bubble.left.and.bubble.right"
        case .note:   return "note.text"
        }
    }

    var displayLabel: String {
        switch self {
        case .post:   return "Post"
        case .reel:   return "Reel"
        case .story:  return "Story"
        case .thread: return "Thread"
        case .note:   return "Note"
        }
    }
}

// MARK: - BereanImportClassification

struct BereanImportClassification: Codable {
    var type: BereanContentType
    var keepRecommended: Bool
    var performativeFlag: Bool          // metric-bait / humble-brag / engagement farming
    var reconsecratedDraft: String?     // Berean rewrite stripped of performance

    static var fallback: BereanImportClassification {
        BereanImportClassification(type: .mundane, keepRecommended: false,
                                   performativeFlag: false, reconsecratedDraft: nil)
    }
}

enum BereanContentType: String, Codable {
    case testimony     = "testimony"
    case devotional    = "devotional"
    case scripture     = "scripture"
    case reflection    = "reflection"
    case promotional   = "promotional"
    case mundane       = "mundane"

    var displayLabel: String {
        switch self {
        case .testimony:   return "Testimony"
        case .devotional:  return "Devotional"
        case .scripture:   return "Scripture"
        case .reflection:  return "Reflection"
        case .promotional: return "Promotional"
        case .mundane:     return "General"
        }
    }

    var color: String {
        switch self {
        case .testimony:   return "purple"
        case .devotional:  return "blue"
        case .scripture:   return "indigo"
        case .reflection:  return "teal"
        case .promotional: return "orange"
        case .mundane:     return "gray"
        }
    }
}

// MARK: - ImportProvenance

struct ImportProvenance: Codable {
    var importedFrom: String        // "instagram", "threads", etc.
    var aiAssisted: Bool            // true if user accepted the reconsecrated draft
}

// MARK: - UserImportDecision

enum UserImportDecision: String, Codable {
    case pending  = "pending"
    case keep     = "keep"
    case discard  = "discard"
    case edited   = "edited"        // user modified the reconsecratedDraft
}

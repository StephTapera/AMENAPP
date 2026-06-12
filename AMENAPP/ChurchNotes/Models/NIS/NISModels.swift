// NISModels.swift
// AMEN — Notes Intelligence System
// Wave 0 Contracts — FROZEN after tag nis-contracts-v1
// All changes to this file require human approval per NIS build order §10.

import Foundation

// MARK: - NISDetection
// Mirrors: notes/{noteId}/detections/{detectionId}

struct NISDetection: Codable, Identifiable, Hashable {
    var id: String
    var type: NISDetectionType
    var span: NISDetectionSpan?
    var payload: NISPayload
    var confidence: Double
    var status: NISDetectionStatus
    var source: NISDetectionSource
    var createdAt: Date
    var resolvedAt: Date?
}

enum NISDetectionType: String, Codable, CaseIterable {
    case scriptureRef   = "scriptureRef"
    case scriptureQuote = "scriptureQuote"
    case person         = "person"
    case action         = "action"
    case prayer         = "prayer"
    case topic          = "topic"
}

enum NISDetectionStatus: String, Codable {
    case proposed  = "proposed"
    case accepted  = "accepted"
    case dismissed = "dismissed"
}

enum NISDetectionSource: String, Codable {
    case clientRegex    = "clientRegex"
    case serverPipeline = "serverPipeline"
    case migration      = "migration"
}

struct NISDetectionSpan: Codable, Hashable {
    var blockId: String
    var start: Int
    var end: Int
}

/// Flat payload for all detection types — all fields optional.
/// Mirrors the `payload: map` field in detections/{detectionId}.
struct NISPayload: Codable, Hashable {
    var book: String?
    var chapter: Int?
    var verseStart: Int?
    var verseEnd: Int?
    var translation: String?
    var matchedText: String?
    var similarityScore: Double?
    var name: String?
    var text: String?
    var topic: String?
    var rawText: String?
}

// MARK: - NISBirthContext
// Mirrors: notes/{noteId}/birthContext

struct NISBirthContext: Codable, Hashable {
    var createdAt: Date
    var churchId: String?
    var churchName: String?
    var seriesId: String?
    var locationMatched: Bool
    var confidence: Double
}

// MARK: - NISDistilledLayer
// Mirrors: notes/{noteId}/layers/distilled

struct NISDistilledLayer: Codable, Hashable {
    var keyPoints: [String]
    var scriptures: [NISScriptureRef]
    var takeaway: String
    var status: NISDistilledStatus
    var generatedBy: String
    var generatedAt: Date
    var approvedAt: Date?
}

enum NISDistilledStatus: String, Codable {
    case proposed = "proposed"
    case approved = "approved"
    case edited   = "edited"
}

struct NISScriptureRef: Codable, Hashable {
    var book: String
    var chapter: Int
    var verseStart: Int
    var verseEnd: Int?
    var translation: String
}

// MARK: - NISPrayer
// Mirrors: users/{uid}/prayers/{prayerId}

struct NISPrayer: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var status: NISPrayerStatus
    var sourceNoteId: String?
    var sourceDetectionId: String?
    var subjectName: String?
    var createdAt: Date
    var statusHistory: [NISPrayerStatusEntry]
}

enum NISPrayerStatus: String, Codable, CaseIterable {
    case requested  = "requested"
    case inProgress = "inProgress"
    case answered   = "answered"
    case archived   = "archived"

    var displayName: String {
        switch self {
        case .requested:  return "Requested"
        case .inProgress: return "In Progress"
        case .answered:   return "Answered"
        case .archived:   return "Archived"
        }
    }

    var icon: String {
        switch self {
        case .requested:  return "hands.sparkles"
        case .inProgress: return "arrow.circlepath"
        case .answered:   return "checkmark.seal.fill"
        case .archived:   return "archivebox.fill"
        }
    }
}

struct NISPrayerStatusEntry: Codable, Hashable {
    var status: NISPrayerStatus
    var at: Date
}

// MARK: - NISTopicSummary
// Mirrors: users/{uid}/topics/{topicId} — precomputed read model

struct NISTopicSummary: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var noteCount: Int
    var prayerCount: Int
    var verseCount: Int
    var sermonCount: Int
    var recentNoteIds: [String]
}

// MARK: - NISResurfaceItem
// Mirrors: users/{uid}/resurfaceQueue/{itemId}

struct NISResurfaceItem: Codable, Identifiable, Hashable {
    var id: String
    var noteId: String
    var reason: String
    var scheduledFor: Date
    var status: NISResurfaceStatus
}

enum NISResurfaceStatus: String, Codable {
    case pending  = "pending"
    case shown    = "shown"
    case snoozed  = "snoozed"
    case disabled = "disabled"
}

// MARK: - NISGraphEdge
// Mirrors: users/{uid}/graphEdges/{edgeId}

struct NISGraphEdge: Codable, Identifiable, Hashable {
    var id: String
    var from: NISGraphNode
    var to: NISGraphNode
    var weight: Double
    var createdAt: Date
    var sourceDetectionId: String?
}

struct NISGraphNode: Codable, Hashable {
    var type: NISGraphNodeType
    var nodeId: String
    var label: String?
}

enum NISGraphNodeType: String, Codable {
    case note      = "note"
    case topic     = "topic"
    case scripture = "scripture"
    case person    = "person"
    case church    = "church"
    case prayer    = "prayer"
}

// MARK: - NISMigrationJob
// Mirrors: migrations/{uid}/jobs/{jobId}

struct NISMigrationJob: Codable, Identifiable, Hashable {
    var id: String
    var status: NISMigrationStatus
    var totalItems: Int
    var processedItems: Int
    var classifiedSpiritual: Int
    var cursor: String?
    var createdAt: Date
    var updatedAt: Date
}

enum NISMigrationStatus: String, Codable {
    case queued  = "queued"
    case running = "running"
    case partial = "partial"
    case done    = "done"
    case failed  = "failed"
}

enum NISMigrationSource: String, Codable {
    case paste      = "paste"
    case shareSheet = "shareSheet"
    case fileImport = "fileImport"
}

// MARK: - NISProcessingState

enum NISProcessingState: Equatable {
    case idle
    case processing
    case done(detectionCount: Int)
    case error(String)
}

// MARK: - NIS note-level metadata fields
// These are stored inline on the note document (not subcollections).

struct NISNoteMetadata: Codable, Hashable {
    var pipelineVersion: String
    var lastProcessedAt: Date
    var detectionCount: Int
}

struct NISLayerIndex: Codable, Hashable {
    var hasDistilled: Bool
    var distilledUpdatedAt: Date?
}

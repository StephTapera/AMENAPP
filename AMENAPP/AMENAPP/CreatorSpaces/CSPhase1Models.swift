// CreatorSpacesModels.swift
// AMENAPP — Creator Spaces Phase 1 Shared Contracts
//
// These types are the seam every workstream composes along.
// Fields marked SERVER-OWNED must never be written from client code.
// Phase-2 fields are typed Optional and default to nil — never fabricate a value.

import Foundation
import FirebaseFirestore
import UIKit

// MARK: - Capture Mode

enum CSCaptureMode: String, CaseIterable, Identifiable {
    case presence = "presence"   // dual front+back simultaneous capture
    case truth    = "truth"      // single-cam, unedited chain enforced
    case audio    = "audio"      // audio-only with optional still

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .presence: return "Presence"
        case .truth:    return "Truth Camera"
        case .audio:    return "Audio"
        }
    }

    var systemIcon: String {
        switch self {
        case .presence: return "camera.on.rectangle.fill"
        case .truth:    return "checkmark.seal.fill"
        case .audio:    return "waveform"
        }
    }

    var description: String {
        switch self {
        case .presence: return "Front + back simultaneously"
        case .truth:    return "No synthetic edits allowed"
        case .audio:    return "Voice, sermon, or reflection"
        }
    }
}

// MARK: - Frame Layout

enum CSFrameLayout: String, Codable, CaseIterable {
    case pip     = "pip"
    case split   = "split"
    case stacked = "stacked"

    var displayName: String {
        switch self {
        case .pip:     return "Picture-in-Picture"
        case .split:   return "Split"
        case .stacked: return "Stacked"
        }
    }

    var systemIcon: String {
        switch self {
        case .pip:     return "pip.enter"
        case .split:   return "rectangle.split.2x1"
        case .stacked: return "rectangle.split.1x2"
        }
    }
}

// MARK: - Asset Type

enum CSAssetType: String, Codable {
    case presence  = "presence"
    case single    = "single"
    case video     = "video"
    case audio     = "audio"
    case creation  = "creation"
}

// MARK: - Media Visibility

enum CSDistribution: String, Codable {
    case dailyPortion = "daily_portion"
    case profileOnly  = "profile_only"
    case roomsOnly    = "rooms_only"
}

// MARK: - Asset Draft (client-side before upload)

struct CSAssetDraft {
    var type: CSAssetType
    var captureMode: CSCaptureMode
    var frontImage: UIImage?
    var backImage: UIImage?
    var audioURL: URL?
    var frameLayout: CSFrameLayout = .pip
    var caption: String = ""
    var scriptureRef: String? = nil       // e.g. "John 3:16"
    var emotionTags: [String] = []
    var distribution: CSDistribution = .dailyPortion
    var spaceId: String? = nil
    var eventId: String? = nil
    var editedWithAI: Bool = false
    var aiToolsUsed: [String] = []
}

// MARK: - Provenance Label (Firestore: provenanceLabels/{labelId})
// The "nutrition label" for every piece of media.
// Phase-2 fields are Optional and must remain nil until the real
// measurement exists — never populate with fabricated scores.

struct CSProvenanceLabel: Codable, Identifiable {
    var id: String                              // = labelId
    var assetId: String
    var capturedOnDevice: Bool                  // computable now
    var sourceCamera: String                    // computable now
    var captureMode: String                     // "presence" | "truth" | "audio"
    var timestampChain: [CSTimestampEvent]       // computable now
    var editHistory: [CSEditEvent]              // computable now; empty = unedited
    var editedWithAI: Bool                      // computable now
    var aiToolsUsed: [String]                   // disclosed tool names
    var aiAssistedPercent: Double?              // PHASE 2 — nil until measurable
    var syntheticElementsPresent: Bool?         // PHASE 2 — nil until real detection
    var authenticityConfidence: Double?         // PHASE 2 — derived score; nil until model exists
    var signature: String                       // HMAC; upgrade seam to C2PA later
    var createdAt: Date

    var isShotReal: Bool {
        capturedOnDevice && editHistory.isEmpty && !editedWithAI
    }
}

struct CSTimestampEvent: Codable {
    var event: String     // "captured" | "edited" | "ai_assist" | "published"
    var timestamp: Date
}

struct CSEditEvent: Codable {
    var tool: String
    var timestamp: Date
    var aiInvolved: Bool
}

// MARK: - Memory Node (Firestore: memoryNodes/{nodeId})

struct CSMemoryNode: Codable, Identifiable {
    var id: String             // = nodeId
    var assetId: String
    var authorId: String
    var edges: CSMemoryEdges
    var embeddingRef: String?  // Pinecone vector id — set server-side after upload
    var createdAt: Date
}

struct CSMemoryEdges: Codable {
    var people: [String] = []
    var events: [String] = []
    var spaces: [String] = []
    var scriptures: [String] = []
    var projects: [String] = []
}

// MARK: - Upload Result

struct CSUploadResult {
    var assetId: String
    var labelId: String
    var memoryNodeId: String?
}

// MARK: - GUARDIAN Safety Decision

enum CSGuardianDecision: String {
    case ok        = "ok"
    case warn      = "warn"
    case delay     = "delay"
    case escalate  = "escalate"
}

struct CSGuardianResult {
    var decision: CSGuardianDecision
    var reasons: [String]

    var isBlocking: Bool { decision == .escalate }
    var requiresRevision: Bool { decision == .warn }
    var isDelayed: Bool { decision == .delay }
}

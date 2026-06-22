// ONEProvenanceModels.swift
// ONE — Content Provenance + Reach Budget + Feed Models
// P0-F | FROZEN contracts. See CONTRACTS.md §6–8.

import Foundation

// MARK: - ONEProvenanceLabel

struct ONEProvenanceLabel: Codable, Sendable {
    let classification: ONEProvenanceClass
    let confidence: Float          // 0.0–1.0; values < 0.70 force .unknown
    let c2paPayload: Data?         // nil when C2PA unavailable (degrade gracefully)
    let attestedAt: Date?
    let processorNote: String?     // human-readable e.g. "Adobe Firefly"

    /// Honesty threshold. A label can never assert a confident class below this.
    static let confidenceThreshold: Float = 0.70

    /// Degrade at the source. Confidence below the honesty threshold can never
    /// assert a confident classification — the PERSISTED `classification` is forced
    /// to `.unknown`, so every reader (Firestore, Cloud Functions, future code)
    /// inherits the honesty, not just the rendered badge.
    init(classification: ONEProvenanceClass, confidence: Float,
         c2paPayload: Data?, attestedAt: Date?, processorNote: String?) {
        self.classification = confidence >= Self.confidenceThreshold ? classification : .unknown
        self.confidence = confidence
        self.c2paPayload = c2paPayload
        self.attestedAt = attestedAt
        self.processorNote = processorNote
    }

    private enum CodingKeys: String, CodingKey {
        case classification, confidence, c2paPayload, attestedAt, processorNote
    }

    /// Migration path: already-persisted raw values are re-normalized on decode, so a
    /// stored confident class with sub-threshold confidence reads back as `.unknown`.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            classification: try c.decode(ONEProvenanceClass.self, forKey: .classification),
            confidence: try c.decode(Float.self, forKey: .confidence),
            c2paPayload: try c.decodeIfPresent(Data.self, forKey: .c2paPayload),
            attestedAt: try c.decodeIfPresent(Date.self, forKey: .attestedAt),
            processorNote: try c.decodeIfPresent(String.self, forKey: .processorNote)
        )
    }

    /// Display-safe label. Now equal to the (already-normalized) `classification`;
    /// retained for call-site compatibility and defense in depth.
    var displayClassification: ONEProvenanceClass {
        confidence >= Self.confidenceThreshold ? classification : .unknown
    }

    static var unknown: ONEProvenanceLabel {
        ONEProvenanceLabel(
            classification: .unknown, confidence: 0.0,
            c2paPayload: nil, attestedAt: nil, processorNote: nil
        )
    }
}

// MARK: - ONEProvenanceClass

enum ONEProvenanceClass: String, Codable, Sendable {
    case captured    // direct camera capture, no edits
    case edited      // filters, crop, color grading
    case aiAssisted  // generative inpainting, upscale, enhancement
    case synthetic   // fully AI-generated
    case unknown     // insufficient signal; always the safe default

    var displayLabel: String {
        switch self {
        case .captured:   return "Captured"
        case .edited:     return "Edited"
        case .aiAssisted: return "AI-Assisted"
        case .synthetic:  return "AI-Generated"
        case .unknown:    return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .captured:   return "camera.fill"
        case .edited:     return "pencil.and.scribble"
        case .aiAssisted: return "sparkles"
        case .synthetic:  return "wand.and.stars"
        case .unknown:    return "questionmark.circle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .captured:   return "Camera captured, no AI"
        case .edited:     return "Edited with filters or tools"
        case .aiAssisted: return "AI-assisted creation"
        case .synthetic:  return "Fully AI-generated"
        case .unknown:    return "Provenance unknown"
        }
    }
}

// MARK: - ONEReachBudget

struct ONEReachBudget: Codable, Sendable {
    let momentID: String
    let originalAuthorUID: String
    var sharesRemaining: Int      // decrements per genuine human relay
    var totalRelays: Int
    var chainDepth: Int           // hops from origin
    let maxChainDepth: Int        // hard cap; default 5

    var hasReachRemaining: Bool { sharesRemaining > 0 && chainDepth < maxChainDepth }

    static func initial(momentID: String, authorUID: String) -> ONEReachBudget {
        ONEReachBudget(
            momentID: momentID,
            originalAuthorUID: authorUID,
            sharesRemaining: 10,
            totalRelays: 0,
            chainDepth: 0,
            maxChainDepth: 5
        )
    }
}

// MARK: - ONEFeedModeKind

enum ONEFeedModeKind: String, Codable, Sendable, CaseIterable {
    case close   // close friends + witnesses only
    case create  // creator drops + collaborative content
    case learn   // long-form, articles, scripture study
    case local   // geo-adjacent community
    case quiet   // curated slow feed; no video; low-motion

    var displayLabel: String {
        switch self {
        case .close:  return "Close"
        case .create: return "Create"
        case .learn:  return "Learn"
        case .local:  return "Local"
        case .quiet:  return "Quiet"
        }
    }

    var defaultSessionBudget: Int {
        switch self {
        case .close:  return 20
        case .create: return 15
        case .learn:  return 10
        case .local:  return 25
        case .quiet:  return 8
        }
    }

    var allowsVideo: Bool { self != .quiet }
    var allowsAutoplay: Bool { false }  // autoplay always off by default
}

// MARK: - ONEFeedSession

struct ONEFeedSession: Codable, Sendable {
    let mode: ONEFeedModeKind
    let sessionBudget: Int
    let autoplayEnabled: Bool  // always false on init; user must explicitly enable
    var itemsSeen: Int
    var startedAt: Date

    var isExhausted: Bool { itemsSeen >= sessionBudget }
    var remaining: Int { max(0, sessionBudget - itemsSeen) }

    static func start(mode: ONEFeedModeKind) -> ONEFeedSession {
        ONEFeedSession(
            mode: mode,
            sessionBudget: mode.defaultSessionBudget,
            autoplayEnabled: false,
            itemsSeen: 0,
            startedAt: Date()
        )
    }
}

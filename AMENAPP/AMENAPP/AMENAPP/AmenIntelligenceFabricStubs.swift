// AmenIntelligenceFabricStubs.swift
// AMEN — Stub types for the Intelligence Fabric pipeline.
// The actual preflight logic runs through the validateCovenantPostSafety
// Cloud Function. These stubs satisfy the compiler while that system
// is being built out server-side.

import Foundation

// MARK: - Surface

enum AmenFabricSurface {
    case group, dm, post, story, comment
}

// MARK: - Audit Event Type

enum AmenFabricAuditEventType {
    case composerPreflight
    case trustReviewRequired
}

// MARK: - Intelligence Snapshot

struct AmenIntelligenceSnapshot {
    struct Policy {
        enum Level { case allow, nudge, requireReview, restrict, crisisEscalation }
        var level: Level = .allow
        var composerSuggestion: String?
        var shouldPersistAudit: Bool = false
        var shouldVerifyFundraising: Bool = false
    }
    var policy: Policy = Policy()
}

// MARK: - Intelligence Fabric (no-op singleton)

@MainActor
final class AmenIntelligenceFabric {
    static let shared = AmenIntelligenceFabric()
    private init() {}

    func snapshot(
        for text: String,
        surface: AmenFabricSurface,
        sourceContext: String
    ) -> AmenIntelligenceSnapshot {
        return AmenIntelligenceSnapshot()
    }
}

// MARK: - Intelligence Fabric Store (no-op singleton)

@MainActor
final class AmenIntelligenceFabricStore {
    static let shared = AmenIntelligenceFabricStore()
    private init() {}

    func persist(
        snapshot: AmenIntelligenceSnapshot,
        contentId: String,
        contentType: String,
        metadata: [String: String]
    ) async {}

    func persistAuditEvent(
        _ type: AmenFabricAuditEventType,
        snapshot: AmenIntelligenceSnapshot,
        contentId: String,
        contentType: String,
        metadata: [String: String]
    ) async {}

    func activateSafetyMode(
        snapshot: AmenIntelligenceSnapshot,
        contentId: String,
        contentType: String,
        metadata: [String: String]
    ) async {}
}

// ProvenanceLabelMapper.swift
// AMENAPP
//
// Wave 4 — Provenance Labels.
//
// Derives a TrustProvenanceLabel from the canonical, creation-time MediaProvenance
// record (SocialOSModels). It does NOT introduce a second provenance store and it
// does NOT back-fill: the origin and edit history are read from the real record
// written when the content was created (§2.4). A direct constructor is provided
// for non-media content (text posts, Berean output) so its label can likewise be
// written at creation from the real pipeline path.
//
// Gated by AMENFeatureFlags.shared.provenanceLabelsEnabled at the render site.

import Foundation

enum ProvenanceLabelMapper {

    /// Maps the canonical media provenance record to the user-facing label.
    static func label(from provenance: MediaProvenance) -> TrustProvenanceLabel {
        TrustProvenanceLabel(
            contentId: provenance.postId.isEmpty ? provenance.mediaId : provenance.postId,
            origin: origin(from: provenance),
            editHistory: editHistory(from: provenance)
        )
    }

    /// Creation-time label for non-media content. Call at creation from the real
    /// pipeline — e.g. a human-typed post is .human, a Berean answer is .aiGenerated,
    /// an AI-helped draft is .aiAssisted.
    static func make(contentId: String, origin: ProvenanceOrigin) -> TrustProvenanceLabel {
        TrustProvenanceLabel(contentId: contentId, origin: origin, editHistory: [])
    }

    // MARK: - Origin derivation (from the real source + AI events)

    private static func origin(from p: MediaProvenance) -> ProvenanceOrigin {
        if p.sourceType == .aiGenerated || p.syntheticMediaStatus == .aiGeneratedMedia {
            return .aiGenerated
        }
        let aiTouched = p.sourceType == .aiAssisted
            || !p.aiEvents.isEmpty
            || p.editEvents.contains(where: { $0.aiAssisted })
            || p.syntheticMediaStatus == .aiAssistedMetadata
            || p.syntheticMediaStatus == .aiEditedMedia
        return aiTouched ? .aiAssisted : .human
    }

    // MARK: - Edit history (real events, time-ordered)

    private static func editHistory(from p: MediaProvenance) -> [ProvenanceEdit] {
        var edits: [ProvenanceEdit] = []

        for event in p.editEvents {
            let summary = event.tool.map { "\(event.editType) · \($0)" } ?? event.editType
            edits.append(ProvenanceEdit(
                actor: event.aiAssisted ? .ai : .human,
                at: iso8601.string(from: event.timestamp),
                summary: summary
            ))
        }

        for event in p.aiEvents {
            edits.append(ProvenanceEdit(
                actor: .ai,
                at: iso8601.string(from: event.timestamp),
                summary: "\(event.actionType): \(event.purpose)"
            ))
        }

        return edits.sorted { $0.at < $1.at }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

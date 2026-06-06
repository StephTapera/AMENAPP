// WorldResponseModels.swift
// AMENAPP — World Events as Christian Response: Firestore models
//
// WorldResponseEvent mirrors the shape of docs in the `world_response_queue`
// Firestore collection.  That collection is admin-populated — the app only reads.
//
// IntelligenceCard (from IntelligenceModels.swift) is the canonical card model.
// WorldResponseCardView accepts IntelligenceCard directly; tier == .global is
// the discriminator.  No separate card model is needed.

import Foundation

// MARK: - WorldResponseEvent

/// Mirrors a document in `world_response_queue/{eventId}`.
/// All fields must match what the admin writes and what worldResponse.js reads.
struct WorldResponseEvent: Codable, Identifiable {
    let id: String

    /// Human-readable headline for the event.
    let title: String

    /// Source attribution — REQUIRED.  Cards without a source are skipped.
    /// Example: "WORLD Magazine", "AP Religion"
    let source: String

    /// Event classification — drives lamentFrame in the card.
    /// Allowed values: "disaster", "conflict", "justice", "mission"
    let type: String

    /// true when the event is confirmed by multiple reliable sources.
    /// DEVELOPING (false) cards are capped at rankScore 40.
    let verified: Bool

    /// true when the event doc includes a vetted donation link.
    let hasDonationLink: Bool

    /// true when a Discussion thread has been opened for this event.
    let discussionEnabled: Bool

    /// true when there is a local angle (unlocks the SHOW_UP action).
    let hasLocalAngle: Bool

    /// Epoch milliseconds — when the admin created this event doc.
    let createdAt: Double

    /// Epoch milliseconds — when this event card should stop surfacing.
    let expiresAt: Double
}

// MARK: - WorldResponseSummaryBullets

/// Decoded shape of the AI model output stored temporarily during CF processing.
/// Not persisted to Firestore; used server-side only.
/// Mirrored here for documentation / contract alignment.
struct WorldResponseSummaryBullets: Codable {
    /// Facts that are well-sourced and publicly reported.
    let known: [String]

    /// Facts that are disputed, unclear, or still developing.
    /// These appear in the expandable "What's contested" section — NOT in summary bullets.
    let contested: [String]

    /// Practical ways the community can pray, give, or serve.
    let howToRespond: [String]
}

// CommunityObjectTypes.swift
// AMENAPP — CommunityOS / Core
//
// Phase 1 Core Spine: universal type definitions for the Community OS.
// All enums, the SpawnProvenance struct, capabilities, edges, and roles
// are defined here. These are the vocabulary shared by every CommunityOS layer.
//
// DO NOT import SwiftUI — this file is pure domain types.
// ContentAudience is defined in ContentOSModels.swift — not redefined here.

import Foundation

// MARK: - AmenObjectType

/// Every canonical object in the Amen graph. Raw values match Firestore `_type` fields.
/// Source: C1 §1 "Universal Object Types".
enum AmenObjectType: String, Codable, CaseIterable, Sendable {
    case user                 = "user"
    case organization         = "organization"
    case church               = "church"
    case team                 = "team"
    case space                = "space"
    case post                 = "post"
    case prayer               = "prayer"
    case discussion           = "discussion"
    case study                = "study"
    case event                = "event"
    case volunteerOpportunity = "volunteerOpportunity"
    case mentorship           = "mentorship"
    case job                  = "job"
    case churchNote           = "churchNote"
    case bereanInsight        = "bereanInsight"
    case mediaObject          = "mediaObject"
    case moment               = "moment"
    case actionThread         = "actionThread"
}

// MARK: - AmenIntent

/// The 11 canonical intents a user can apply to a source object.
/// Raw values match C2 §2 intent raw values.
enum AmenIntent: String, Codable, CaseIterable, Sendable {
    case share     = "share"
    case discuss   = "discuss"
    case pray      = "pray"
    case study     = "study"
    case teach     = "teach"
    case ask       = "ask"
    case invite    = "invite"
    case volunteer = "volunteer"
    case hire      = "hire"
    case mentor    = "mentor"
    case announce  = "announce"
}

// MARK: - SpawnProvenance

/// Immutable provenance block written at object-creation time.
/// Named `SpawnProvenance` (not `Provenance`) to avoid collision with
/// `ONEProvenanceLabel` (media authenticity struct in ONE/Core/).
/// Also avoids collision with `ActionThreadAuditEntry` in ActionThreadModels.swift.
/// See C1 §3 "Provenance — Inline on Every Spawnable Object".
///
/// IMPORTANT: `createdAt` is always set server-side via Cloud Function or
/// Firestore FieldValue.serverTimestamp(). The iOS client NEVER writes this field.
struct SpawnProvenance: Codable, Equatable, Sendable {
    /// `AmenObjectType.rawValue` of the parent, or `"direct"` for root objects.
    let sourceType: String
    /// Firestore document path of the parent (e.g. `/posts/abc123`).
    /// `nil` for root objects that have no parent.
    let sourceRef: String?
    /// UID of the original object's owner. `nil` for root objects.
    let sourceOwnerId: String?
    /// `AmenIntent.rawValue` that produced this object (e.g. `"discuss"`).
    /// Use `"direct"` when the object was created without a transform.
    let intent: String
    /// Server-side creation timestamp. Never set by the client.
    let createdAt: Date
}

// MARK: - ObjectCapability

/// The shared capability vocabulary for all Amen objects.
/// Source: C1 §2 "Shared Capability Set".
/// No object exposes capabilities beyond this set.
enum ObjectCapability: String, Codable, CaseIterable, Sendable {
    case view     = "view"
    case discuss  = "discuss"
    case pray     = "pray"
    case study    = "study"
    case share    = "share"
    case save     = "save"
    case invite   = "invite"
    case followUp = "follow_up"
}

// MARK: - AmenEdgeType

/// Relationship types for the `/edges` collection.
/// Source: C1 §4b "EdgeType enum".
enum AmenEdgeType: String, Codable, CaseIterable, Sendable {
    /// Object is owned/hosted by another (Post → Church, User → Space).
    case belongsTo   = "belongsTo"
    /// Object was created via a transform (Discussion ← Post via Discuss intent).
    case spawnedFrom = "spawnedFrom"
    /// Contextual association (ChurchNote ↔ Sermon, BereanInsight ↔ Scripture).
    case links       = "links"
    /// User follows User/Org/Space/Church/Creator.
    case follows     = "follows"
    /// User is actively praying for a Prayer or Person.
    case praysFor    = "praysFor"
}

// MARK: - AmenRole

/// RBAC roles as defined in C5 §1 "Role Definitions".
/// Raw values match the Firestore `role` field values from C5.
enum AmenRole: String, Codable, CaseIterable, Sendable {
    case owner          = "owner"
    case executiveAdmin = "executive_admin"
    case pastor         = "pastor"
    case leader         = "leader"
    case moderator      = "moderator"
    case volunteerLead  = "volunteer_lead"
    case contentManager = "content_manager"
    case eventManager   = "event_manager"
    case member         = "member"
    case visitor        = "visitor"
}

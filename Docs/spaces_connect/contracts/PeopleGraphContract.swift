// PeopleGraphContract.swift
// AMEN — SPACES_CONNECT_V1 / Phase −1 Contracts
//
// FROZEN 2026-05-31. Do not edit without SpacesConnect-Phase0 authorization.
//
// ─── Firestore Schema ────────────────────────────────────────────────────────
//
//  /users/{uid}/graph/edges/{edgeId}
//    type:       EdgeType  (string enum — see below)
//    targetUid:  String
//    privacy:    EdgePrivacy  (string enum — see below)
//    metadata:   Map          (role, since, notes, orgId, spaceId, etc.)
//    createdAt:  Timestamp
//
//  Privacy model:
//    private  → visible only to the edge owner
//    org      → visible to members of the same org
//    space    → visible to members of the same Space
//    public   → visible to anyone who can view the owner's profile
//    Default: private
//
//  Edge types from spec:
//    org, space, family, mentor, mentee, serves, prayedFor,
//    authoredNote, attendedEvent, hasSkill, milestone
//
//  Security rules:
//    read:  request.auth.uid == uid  || privacy check via allow function
//    write: request.auth.uid == uid  (edges are always owner-written)
//
//  Indexes required:
//    (targetUid ASC, createdAt DESC)    — "who points at me" queries
//    (type ASC, createdAt DESC)         — filter by edge type
//
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import FirebaseFirestore

// MARK: - EdgeType

/// Semantic classification of a relationship edge.
///
/// Naming note: `org` and `space` are structural memberships (foreign-key-like).
/// All others are semantic / relational connections.
enum EdgeType: String, Codable, CaseIterable, Hashable {
    /// User belongs to an org at `metadata["orgId"]`.
    case org
    /// User belongs to a Space at `metadata["spaceId"]`.
    case space
    /// Family relationship (parent, sibling, spouse). Role stored in `metadata["role"]`.
    case family
    /// This user mentors `targetUid`.
    case mentor
    /// This user is mentored by `targetUid`.
    case mentee
    /// This user serves `targetUid`'s ministry / org in role `metadata["role"]`.
    case serves
    /// This user has prayed for `targetUid` (from a prayer post or direct prayer).
    case prayedFor
    /// This user authored a note for / referencing `targetUid`
    /// (e.g. a sermon note that mentions a pastor).
    case authoredNote
    /// This user attended an event hosted or co-hosted by `targetUid`.
    case attendedEvent
    /// This user possesses skill `metadata["skillName"]` relevant to `targetUid`'s org/space.
    case hasSkill
    /// A milestone event shared between this user and `targetUid`
    /// (e.g. baptism together, first sermon). Description in `metadata["note"]`.
    case milestone
}

// MARK: - EdgePrivacy

/// Visibility scope for a graph edge.
///
/// Default: `.private`
/// Agents MUST gate all edge reads on the caller's privacy clearance;
/// never expose private edges to third parties.
enum EdgePrivacy: String, Codable, CaseIterable, Hashable {
    /// Visible only to the edge owner.
    case `private`
    /// Visible to members of the same org (requires orgId match in metadata or caller context).
    case org
    /// Visible to members of the same Space.
    case space
    /// Visible to any authenticated user who can view the owner's profile.
    case `public`
}

// MARK: - GraphEdgeMetadata

/// Flexible key-value bag stored in Firestore as a Map.
/// Well-known keys are listed below; agents may extend for their use-case
/// but must not break existing keys.
///
/// Well-known keys:
///   role:       String  — human-readable role label (e.g. "Lead Pastor", "Deacon", "Coach")
///   since:      String  — ISO 8601 date string of when relationship started (e.g. "2024-09")
///   notes:      String  — optional free-text annotation (max 500 chars, client-validated)
///   orgId:      String  — Firestore orgId for .org edges
///   spaceId:    String  — Firestore spaceId for .space edges
///   skillName:  String  — skill label for .hasSkill edges
///   eventId:    String  — event document ID for .attendedEvent edges
///   noteId:     String  — church note doc ID for .authoredNote edges
typealias GraphEdgeMetadata = [String: String]

// MARK: - PeopleGraphEdge

/// A single directed relationship edge from the owning user to `targetUid`.
///
/// Firestore path: `/users/{uid}/graph/edges/{edgeId}`
/// `@DocumentID id` is the `edgeId` — auto-assigned by Firestore on create.
struct PeopleGraphEdge: Identifiable, Codable, Hashable {
    /// Firestore document ID. SERVER-OWNED on creation.
    @DocumentID var id: String?

    /// The edge direction semantic type.
    var type: EdgeType

    /// UID of the target user this edge points to.
    var targetUid: String

    /// Visibility scope. Default: `.private`.
    var privacy: EdgePrivacy

    /// Flexible metadata bag (role, since, notes, orgId, spaceId, etc.).
    var metadata: GraphEdgeMetadata

    /// Creation timestamp. SERVER-OWNED.
    var createdAt: Timestamp

    // MARK: Helpers

    /// Returns the `orgId` stored in metadata, if present.
    var orgId: String? { metadata["orgId"] }

    /// Returns the `spaceId` stored in metadata, if present.
    var spaceId: String? { metadata["spaceId"] }

    static func == (lhs: PeopleGraphEdge, rhs: PeopleGraphEdge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - PeopleGraphEdgePage

/// Paginated result from a graph edge query.
struct PeopleGraphEdgePage {
    let edges: [PeopleGraphEdge]
    let cursor: DocumentSnapshot?
    let hasMore: Bool
}

// MARK: - PeopleGraphFilter

/// Query filter for fetching edges.
struct PeopleGraphFilter {
    var type: EdgeType?
    var privacy: EdgePrivacy?
    var targetUid: String?
}

// MARK: - PeopleGraphServiceProtocol

/// Contract for reading/writing the People Graph.
/// Implementation lives in PeopleGraphService (Phase 0+).
/// All write operations are idempotent by (ownerUid, targetUid, type).
protocol PeopleGraphServiceProtocol {
    /// Fetch edges for a given owner uid.
    func fetchEdges(
        for ownerUid: String,
        filter: PeopleGraphFilter,
        after cursor: DocumentSnapshot?
    ) async throws -> PeopleGraphEdgePage

    /// Upsert an edge. Idempotent by (ownerUid, targetUid, type).
    func upsertEdge(
        ownerUid: String,
        edge: PeopleGraphEdge
    ) async throws -> String

    /// Delete an edge by edgeId.
    func deleteEdge(
        ownerUid: String,
        edgeId: String
    ) async throws

    /// Return all edges pointing TO a targetUid (reverse lookup).
    /// Used for "who connected to me" surfaces. Requires a composite index.
    func fetchInboundEdges(
        targetUid: String,
        type: EdgeType?,
        limit: Int
    ) async throws -> [PeopleGraphEdge]
}

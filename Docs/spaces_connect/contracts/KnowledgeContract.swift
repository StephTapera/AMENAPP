// KnowledgeContract.swift
// AMEN — SPACES_CONNECT_V1 / Phase −1 Contracts
//
// FROZEN 2026-05-31. Do not edit without SpacesConnect-Phase0 authorization.
//
// ─── Firestore Schema ────────────────────────────────────────────────────────
//
//  /orgs/{orgId}/spaces/{spaceId}/knowledge/{unitId}
//    title:           String
//    content:         String             (plain-text body; max 50,000 chars)
//    source:          KnowledgeSource    (string enum)
//    refs:            Array<KnowledgeRef>  (scripture refs, people, events)
//    orgType:         OrgType            (string enum, denormalized for AI routing)
//    vectorNamespace: String             (Pinecone namespace: "{orgId}_{spaceId}")
//    seriesId:        String?            (links to a study series document)
//    tags:            [String]           (max 20, client-validated)
//    authorUid:       String             (SERVER-OWNED on create)
//    createdAt:       Timestamp          (SERVER-OWNED)
//    updatedAt:       Timestamp          (SERVER-OWNED)
//    embeddingStatus: EmbeddingStatus    (string enum)
//
//  /orgs/{orgId}/spaces/{spaceId}/knowledge/{unitId}/versions/{versionId}
//    content:    String
//    editedBy:   String     (uid)
//    editedAt:   Timestamp
//    changeNote: String?
//
//  Indexing strategy:
//    Firestore:  (spaceId ASC, createdAt DESC) for chronological list
//                (source ASC, createdAt DESC) for filtered views
//    Algolia:    index "knowledge_units" with orgId, spaceId, orgType, tags, title
//    Pinecone:   one namespace per Space = "{orgId}_{spaceId}"
//                vectors are 1536-d text embeddings of `content`
//                metadata keys stored with each vector:
//                  unitId, spaceId, orgId, orgType, source, authorUid, createdAt
//
//  Embedding lifecycle:
//    1. Client writes KnowledgeUnit with embeddingStatus = .pending
//    2. Firestore trigger Cloud Function "embedKnowledgeUnit" fires
//    3. CF embeds content → upserts into Pinecone namespace
//    4. CF flips embeddingStatus = .indexed (or .failed on error)
//    Client must never call Pinecone directly.
//
// ─── Naming Conflicts ────────────────────────────────────────────────────────
//
//  NO direct conflict: `KnowledgeUnit` does not exist anywhere in the current
//  codebase (searched 2026-05-31). Safe to introduce.
//
//  RELATED existing types (do not confuse):
//    ChurchNoteV2 (ChurchNoteSemanticModels.swift) — a personal note for one user;
//      KnowledgeUnit is an org-level canonical knowledge artifact.
//    StudyBlock (SpacesModels.swift) — a block inside a Space study;
//      KnowledgeUnit is the top-level document wrapping blocks for indexing.
//    SpaceStudy (SpacesModels.swift) — a structured study curriculum;
//      KnowledgeUnit can *reference* a SpaceStudy via refs[].id but is not the same.
//
//  OrgType and SpaceRole are defined in OrgSpaceHierarchyContract.swift.
//  This file does not redeclare them.
//
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import FirebaseFirestore

// MARK: - KnowledgeSource

/// The origin content type of a KnowledgeUnit.
/// Drives display formatting, AI system-prompt tuning, and Algolia faceting.
enum KnowledgeSource: String, Codable, CaseIterable, Hashable {
    /// A transcribed or summarized sermon (church/ministry).
    case sermonNote    = "SermonNote"
    /// A standard operating procedure document (business/school/nonprofit).
    case sop           = "SOP"
    /// A personal or community testimony (any org type).
    case testimony     = "Testimony"
    /// A formal study lesson in a curriculum (school/church/ministry).
    case lesson        = "Lesson"
    /// Notes from a meeting or sync (business/enterprise/leadership).
    case meeting       = "Meeting"
}

// MARK: - EmbeddingStatus

/// Processing state of the Pinecone vector embedding for this unit.
enum EmbeddingStatus: String, Codable, CaseIterable, Hashable {
    /// Written to Firestore; CF has not yet embedded.
    case pending
    /// Embedded and indexed in Pinecone. Searchable.
    case indexed
    /// Embedding attempt failed. Will retry on next CF trigger.
    case failed
}

// MARK: - KnowledgeRefType

/// The category of a cross-reference attached to a KnowledgeUnit.
enum KnowledgeRefType: String, Codable, CaseIterable, Hashable {
    /// A Bible scripture reference (book/chapter/verse).
    case scripture
    /// A reference to a user profile (e.g. the speaker).
    case person
    /// A reference to an event document.
    case event
    /// A reference to another KnowledgeUnit (semantic link).
    case knowledgeUnit
    /// A reference to an external URL.
    case externalLink
}

// MARK: - KnowledgeRef

/// A typed cross-reference attached to a KnowledgeUnit.
///
/// For scripture refs, `id` is the canonical reference string (e.g. "John 3:16").
/// For person refs, `id` is the user's uid.
/// For event/knowledgeUnit refs, `id` is the Firestore document id.
/// For externalLink refs, `id` is the URL string.
struct KnowledgeRef: Codable, Hashable, Identifiable {
    var id: String
    var type: KnowledgeRefType
    /// Human-readable label (e.g. "John 3:16", "Pastor James", "Sunday Service 2026-05-31").
    var label: String?
}

// MARK: - KnowledgeUnit

/// A canonical org-level knowledge artifact stored under an OrgSpace.
/// Firestore path: `/orgs/{orgId}/spaces/{spaceId}/knowledge/{unitId}`
///
/// KnowledgeUnit is the indexing unit for both Algolia (text search) and
/// Pinecone (semantic / vector search). One KnowledgeUnit = one Pinecone vector.
struct KnowledgeUnit: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var title: String
    /// Plain-text body. Max 50,000 chars (client-validated before write).
    var content: String

    var source: KnowledgeSource

    /// Cross-references: scripture, people, events, etc.
    var refs: [KnowledgeRef]

    /// Denormalized org type. Used by AI routing and Pinecone metadata.
    var orgType: OrgType

    /// Pinecone namespace for this unit: format is "{orgId}_{spaceId}".
    /// One namespace per Space — do not share namespaces across Spaces or orgs.
    var vectorNamespace: String

    /// Optional link to a study series document in the Space.
    var seriesId: String?

    /// Content tags for filtering. Max 20. Client-validated.
    var tags: [String]

    /// UID of the author. SERVER-OWNED on create.
    var authorUid: String

    /// SERVER-OWNED timestamps.
    var createdAt: Timestamp
    var updatedAt: Timestamp

    /// Processing state of the Pinecone embedding. Transitions: pending → indexed | failed.
    var embeddingStatus: EmbeddingStatus

    var unitId: String { id ?? "" }

    static func == (lhs: KnowledgeUnit, rhs: KnowledgeUnit) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Computed helpers

    /// Returns the expected Pinecone namespace string given orgId and spaceId.
    static func namespace(orgId: String, spaceId: String) -> String {
        "\(orgId)_\(spaceId)"
    }

    /// Returns true if this unit is ready for semantic search.
    var isSearchable: Bool { embeddingStatus == .indexed }
}

// MARK: - KnowledgeUnitVersion

/// An immutable version snapshot stored at
/// `/orgs/{orgId}/spaces/{spaceId}/knowledge/{unitId}/versions/{versionId}`
/// Written on each significant edit. Never deleted.
struct KnowledgeUnitVersion: Identifiable, Codable {
    @DocumentID var id: String?

    var content: String
    var editedBy: String
    var editedAt: Timestamp
    var changeNote: String?
}

// MARK: - KnowledgeQuery

/// Parameters for a semantic knowledge search within a Space's Pinecone namespace.
struct KnowledgeQuery: Codable {
    /// The natural-language search query.
    var queryText: String
    /// Maximum number of results to return from Pinecone.
    var topK: Int
    /// Pinecone namespace to search in.
    var namespace: String
    /// Optional source filter.
    var filterSource: KnowledgeSource?
    /// Minimum similarity score threshold (0.0–1.0). Defaults to 0.7.
    var minScore: Double
}

// MARK: - KnowledgeSearchResult

/// A single result from a semantic knowledge search.
struct KnowledgeSearchResult: Identifiable, Codable, Hashable {
    var id: String { unitId }
    var unitId: String
    var title: String
    var snippet: String      // AI-trimmed excerpt relevant to the query
    var score: Double        // Pinecone similarity score
    var source: KnowledgeSource
    var orgType: OrgType
}

// MARK: - KnowledgeServiceProtocol

/// Contract for CRUD + semantic search on KnowledgeUnits.
/// All Pinecone calls are server-side — the client never calls Pinecone directly.
protocol KnowledgeServiceProtocol {
    /// Write a new KnowledgeUnit. Returns the generated unitId.
    /// Sets embeddingStatus = .pending; CF handles indexing.
    func createUnit(
        orgId: String,
        spaceId: String,
        unit: KnowledgeUnit
    ) async throws -> String

    /// Update a KnowledgeUnit. Resets embeddingStatus = .pending.
    /// Automatically creates a version snapshot before overwriting.
    func updateUnit(
        orgId: String,
        spaceId: String,
        unitId: String,
        content: String,
        changeNote: String?
    ) async throws

    /// Fetch a page of KnowledgeUnits from a Space's knowledge subcollection.
    func fetchUnits(
        orgId: String,
        spaceId: String,
        source: KnowledgeSource?,
        after cursor: DocumentSnapshot?
    ) async throws -> (units: [KnowledgeUnit], cursor: DocumentSnapshot?, hasMore: Bool)

    /// Semantic search via Pinecone callable proxy.
    /// MUST route through "searchKnowledgeUnits" Cloud Function — never direct Pinecone.
    func semanticSearch(query: KnowledgeQuery) async throws -> [KnowledgeSearchResult]

    /// Delete a KnowledgeUnit. Also triggers CF to remove the Pinecone vector.
    /// NEVER hard-deletes versions — those are append-only.
    func deleteUnit(
        orgId: String,
        spaceId: String,
        unitId: String
    ) async throws
}

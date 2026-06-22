// =============================================================================
// functions/catalog/catalogSchema.js
//
// AMEN Catalog + Knowledge Network — Firestore schema documentation & validation
// OWNER:    Agent A (Catalog + Knowledge Network build, 2026-06-06)
// PURPOSE:  Single source of truth for all Catalog collection schemas.
//           Consumed by other agents (B–F) for Cloud Function callables and
//           iOS contract generation.
//
// EXPORTS:
//   WORK_TYPES               — valid values for Work.type
//   WORK_VISIBILITY_LEVELS   — valid values for Work.visibility
//   WORK_REVIEW_STATES       — valid values for Work.reviewState
//   INGESTION_JOB_STATUSES   — valid values for IngestionJob.status
//   validateWork(data)       — { valid: boolean, errors: string[] }
//   validateKnowledgeNode(data) — { valid: boolean, errors: string[] }
//   defaultWork(creatorId, provider) — Work with all defaults applied
//
// COLLECTIONS:
//   works/{workId}
//   knowledgeNodes/{nodeId}
//   ingestionJobs/{jobId}
//   verificationClaims/{claimId}
//   users/{uid}/followedTopics/{topicId}
// =============================================================================

'use strict';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/**
 * All valid content types a Work document may represent.
 * Matches the `type` field discriminant used in iOS CatalogWork struct.
 */
const WORK_TYPES = Object.freeze([
  'book',
  'album',
  'track',
  'podcast',
  'episode',
  'video',
  'sermon',
  'article',
  'course',
  'event',
]);

/**
 * Visibility levels for a Work document.
 * Default on creation is always 'private' (enforced by Firestore security rules).
 *
 * public        — any authenticated user can read
 * followers     — users who follow the creator
 * paid_members  — users with active catalog entitlement (users/{uid}/entitlements/catalog)
 * organization  — users sharing the same orgId claim as the work
 * private       — creator only
 */
const WORK_VISIBILITY_LEVELS = Object.freeze([
  'public',
  'followers',
  'paid_members',
  'organization',
  'private',
]);

/**
 * Review/publish state machine for a Work document.
 * Direction: imported → draft → review → approved → published
 *
 * 'imported'   — freshly ingested from provider; not yet reviewed
 * 'draft'      — creator is editing; not submitted for review
 * 'review'     — submitted to platform review pipeline
 * 'approved'   — approved by reviewer; ready to be published
 * 'published'  — live on the platform; publishedAt is set
 *
 * IMPORTANT: Transitions to 'approved' and 'published' are CF-only (Admin SDK).
 * Clients may move between 'imported', 'draft', and 'review' only.
 * Firestore security rules enforce this — reviewStateNotPublishedByClient().
 */
const WORK_REVIEW_STATES = Object.freeze([
  'imported',
  'draft',
  'review',
  'approved',
  'published',
]);

/**
 * Valid states for an IngestionJob document.
 * Status transitions are advanced by the ingestion CF only (never by clients).
 *
 * pending  — job created by client; CF has not yet started processing
 * running  — CF is actively ingesting items from the provider
 * done     — ingestion completed successfully
 * error    — ingestion failed; errorMessage field contains details
 */
const INGESTION_JOB_STATUSES = Object.freeze([
  'pending',
  'running',
  'done',
  'error',
]);

/**
 * Valid methods for a VerificationClaim.
 */
const VERIFICATION_CLAIM_METHODS = Object.freeze([
  'domain',
  'social_oauth',
  'email_domain',
  'org_admin',
  'manual',
]);

/**
 * Valid statuses for a VerificationClaim.
 * Clients may only create claims with status 'pending'.
 * CF/Admin SDK transitions to 'approved' or 'rejected'.
 */
const VERIFICATION_CLAIM_STATUSES = Object.freeze([
  'pending',
  'approved',
  'rejected',
]);

/**
 * Valid link kinds for a Work.links[] entry.
 */
const WORK_LINK_KINDS = Object.freeze([
  'read',
  'listen',
  'watch',
  'buy',
  'register',
]);

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

/**
 * Validates a Work document data object.
 *
 * @param {object} data — Plain object representing the Firestore document data.
 * @returns {{ valid: boolean, errors: string[] }}
 *
 * Schema:
 *   id             string (required)
 *   creatorId      string (required)
 *   type           WORK_TYPES member (required)
 *   title          string, non-empty (required)
 *   subtitle       string (optional)
 *   description    string (optional)
 *   coverUrl       string (optional)
 *   publishedAt    Timestamp | null — null unless reviewState == 'published'
 *   source         { provider: string, externalId: string, sourceUrl: string } (required)
 *   links          array of WorkLink objects (optional, defaults to [])
 *   topics         array of topic ID strings (optional, defaults to [])
 *   embeddingRef   string (optional)
 *   transcriptRef  string (optional)
 *   visibility     WORK_VISIBILITY_LEVELS member (required)
 *   reviewState    WORK_REVIEW_STATES member (required)
 *   ingestMode     'auto' | 'manual' (required)
 *   verifiedOwnership boolean (required)
 *   createdAt      Timestamp (required)
 *   updatedAt      Timestamp (required)
 *   deletedAt      Timestamp | null (optional, null = not deleted)
 */
function validateWork(data) {
  const errors = [];

  if (!data || typeof data !== 'object') {
    return { valid: false, errors: ['data must be a non-null object'] };
  }

  // Required string fields
  if (!data.id || typeof data.id !== 'string' || data.id.trim() === '') {
    errors.push('id is required and must be a non-empty string');
  }
  if (!data.creatorId || typeof data.creatorId !== 'string' || data.creatorId.trim() === '') {
    errors.push('creatorId is required and must be a non-empty string');
  }
  if (!data.title || typeof data.title !== 'string' || data.title.trim() === '') {
    errors.push('title is required and must be a non-empty string');
  }

  // Discriminant enums
  if (!WORK_TYPES.includes(data.type)) {
    errors.push(`type must be one of: ${WORK_TYPES.join(', ')}`);
  }
  if (!WORK_VISIBILITY_LEVELS.includes(data.visibility)) {
    errors.push(`visibility must be one of: ${WORK_VISIBILITY_LEVELS.join(', ')}`);
  }
  if (!WORK_REVIEW_STATES.includes(data.reviewState)) {
    errors.push(`reviewState must be one of: ${WORK_REVIEW_STATES.join(', ')}`);
  }
  if (data.ingestMode !== 'auto' && data.ingestMode !== 'manual') {
    errors.push("ingestMode must be 'auto' or 'manual'");
  }
  if (typeof data.verifiedOwnership !== 'boolean') {
    errors.push('verifiedOwnership must be a boolean');
  }

  // source sub-object
  if (!data.source || typeof data.source !== 'object') {
    errors.push('source is required and must be an object');
  } else {
    if (!data.source.provider || typeof data.source.provider !== 'string') {
      errors.push('source.provider is required and must be a string');
    }
    if (!data.source.externalId || typeof data.source.externalId !== 'string') {
      errors.push('source.externalId is required and must be a string');
    }
    if (!data.source.sourceUrl || typeof data.source.sourceUrl !== 'string') {
      errors.push('source.sourceUrl is required and must be a string');
    }
  }

  // links array validation (optional, but each entry must be valid if present)
  if (data.links !== undefined) {
    if (!Array.isArray(data.links)) {
      errors.push('links must be an array');
    } else {
      data.links.forEach((link, i) => {
        if (!WORK_LINK_KINDS.includes(link.kind)) {
          errors.push(`links[${i}].kind must be one of: ${WORK_LINK_KINDS.join(', ')}`);
        }
        if (!link.platform || typeof link.platform !== 'string') {
          errors.push(`links[${i}].platform is required and must be a string`);
        }
        if (!link.url || typeof link.url !== 'string') {
          errors.push(`links[${i}].url is required and must be a string`);
        }
      });
    }
  }

  // topics array (optional)
  if (data.topics !== undefined && !Array.isArray(data.topics)) {
    errors.push('topics must be an array of strings');
  }

  // publishedAt must be null unless reviewState == 'published'
  if (data.reviewState !== 'published' && data.publishedAt != null) {
    errors.push("publishedAt must be null unless reviewState is 'published'");
  }

  // Timestamp presence checks (accept Firestore Timestamp objects or numbers for test mocks)
  if (data.createdAt == null) {
    errors.push('createdAt is required');
  }
  if (data.updatedAt == null) {
    errors.push('updatedAt is required');
  }

  return { valid: errors.length === 0, errors };
}

/**
 * Validates a KnowledgeNode document data object.
 *
 * @param {object} data
 * @returns {{ valid: boolean, errors: string[] }}
 *
 * Schema:
 *   id         string (required)
 *   creatorId  string (required)
 *   topic      string (required)
 *   workRefs   string[] — array of workId strings (required)
 *   parentId   string (optional) — parent node for hierarchical topics
 */
function validateKnowledgeNode(data) {
  const errors = [];

  if (!data || typeof data !== 'object') {
    return { valid: false, errors: ['data must be a non-null object'] };
  }

  if (!data.id || typeof data.id !== 'string' || data.id.trim() === '') {
    errors.push('id is required and must be a non-empty string');
  }
  if (!data.creatorId || typeof data.creatorId !== 'string' || data.creatorId.trim() === '') {
    errors.push('creatorId is required and must be a non-empty string');
  }
  if (!data.topic || typeof data.topic !== 'string' || data.topic.trim() === '') {
    errors.push('topic is required and must be a non-empty string');
  }
  if (!Array.isArray(data.workRefs)) {
    errors.push('workRefs is required and must be an array of workId strings');
  } else if (data.workRefs.some((ref) => typeof ref !== 'string' || ref.trim() === '')) {
    errors.push('all entries in workRefs must be non-empty strings');
  }

  if (data.parentId !== undefined && data.parentId !== null) {
    if (typeof data.parentId !== 'string' || data.parentId.trim() === '') {
      errors.push('parentId must be a non-empty string if provided');
    }
  }

  return { valid: errors.length === 0, errors };
}

// ---------------------------------------------------------------------------
// Default factories
// ---------------------------------------------------------------------------

/**
 * Returns a new Work object with all required defaults applied.
 * Use this as the base for any Work created by an ingestion CF.
 *
 * Defaults:
 *   visibility      = 'private'   (must be explicitly published by creator)
 *   reviewState     = 'imported'  (entry point of the state machine)
 *   ingestMode      = 'auto'      (set to 'manual' for user-submitted works)
 *   verifiedOwnership = false     (set to true only after VerificationClaim approved)
 *   links           = []
 *   topics          = []
 *   publishedAt     = null
 *   deletedAt       = null
 *
 * @param {string} creatorId — UID of the creator who owns this work.
 * @param {string} provider  — Provider name (e.g. 'spotify', 'apple_books', 'youtube').
 * @returns {object} — Partial Work object ready for Firestore set().
 *                     Caller must add: id, type, title, source, createdAt, updatedAt.
 */
function defaultWork(creatorId, provider) {
  if (!creatorId || typeof creatorId !== 'string') {
    throw new Error('defaultWork: creatorId must be a non-empty string');
  }
  if (!provider || typeof provider !== 'string') {
    throw new Error('defaultWork: provider must be a non-empty string');
  }

  return {
    creatorId,
    // type, title, source, id — caller must supply these
    visibility: 'private',
    reviewState: 'imported',
    ingestMode: 'auto',
    verifiedOwnership: false,
    links: [],
    topics: [],
    publishedAt: null,
    deletedAt: null,
    source: {
      provider,
      externalId: '',   // caller must fill in
      sourceUrl: '',    // caller must fill in
    },
  };
}

// ---------------------------------------------------------------------------
// Firestore schema reference (for other agents)
// ---------------------------------------------------------------------------

/**
 * SCHEMA REFERENCE
 * ================
 *
 * works/{workId}
 * --------------
 * {
 *   id: string,
 *   creatorId: string,
 *   type: WORK_TYPES[n],
 *   title: string,
 *   subtitle?: string,
 *   description?: string,
 *   coverUrl?: string,
 *   publishedAt: Timestamp | null,         // null unless reviewState == 'published'
 *   source: {
 *     provider: string,
 *     externalId: string,
 *     sourceUrl: string,
 *   },
 *   links: [{
 *     kind: WORK_LINK_KINDS[n],
 *     platform: string,
 *     url: string,
 *     affiliateUrl?: string,
 *   }],
 *   topics: string[],                      // array of topicId strings
 *   embeddingRef?: string,                 // path to embedding vector doc
 *   transcriptRef?: string,                // path to transcript doc
 *   visibility: WORK_VISIBILITY_LEVELS[n], // default 'private'
 *   reviewState: WORK_REVIEW_STATES[n],    // default 'imported'
 *   ingestMode: 'auto' | 'manual',         // default 'auto'
 *   verifiedOwnership: boolean,            // default false
 *   createdAt: Timestamp,
 *   updatedAt: Timestamp,
 *   deletedAt?: Timestamp | null,          // null = not deleted; soft-delete only (I-1)
 * }
 *
 * knowledgeNodes/{nodeId}
 * -----------------------
 * {
 *   id: string,
 *   creatorId: string,
 *   topic: string,
 *   workRefs: string[],   // array of workId references
 *   parentId?: string,    // parent nodeId for hierarchical topics
 * }
 *
 * ingestionJobs/{jobId}
 * ---------------------
 * {
 *   id: string,
 *   creatorId: string,
 *   provider: string,
 *   status: INGESTION_JOB_STATUSES[n],
 *   cursor?: string,         // pagination cursor for incremental ingestion
 *   itemsFound: number,
 *   itemsImported: number,
 *   errorMessage?: string,
 *   createdAt: Timestamp,
 *   updatedAt: Timestamp,
 * }
 *
 * verificationClaims/{claimId}
 * ----------------------------
 * {
 *   creatorId: string,
 *   method: VERIFICATION_CLAIM_METHODS[n],
 *   status: VERIFICATION_CLAIM_STATUSES[n],  // client creates as 'pending' only
 *   evidence: string | object,               // URL, token, or evidence payload
 *   createdAt: Timestamp,
 * }
 *
 * users/{uid}/followedTopics/{topicId}  (CatalogSubscription)
 * ------------------------------------------------------------
 * {
 *   topicId: string,
 *   topicName: string,
 *   createdAt: Timestamp,
 * }
 */

// ---------------------------------------------------------------------------
// Module exports
// ---------------------------------------------------------------------------

module.exports = {
  // Constants
  WORK_TYPES,
  WORK_VISIBILITY_LEVELS,
  WORK_REVIEW_STATES,
  INGESTION_JOB_STATUSES,
  VERIFICATION_CLAIM_METHODS,
  VERIFICATION_CLAIM_STATUSES,
  WORK_LINK_KINDS,

  // Validators
  validateWork,
  validateKnowledgeNode,

  // Factories
  defaultWork,
};

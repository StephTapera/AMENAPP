// types.ts — Capabilities v1 wire-format types
//
// FROZEN after Wave 0 gate. Do not add, remove, rename, or retype anything here.
// File a CONTESTED blocker in Docs/Capabilities/BLOCKERS.md if a change is needed.
//
// See Docs/Capabilities/CONTRACTS.md §4 for the canonical type descriptions.
//
// Zod validation schemas live in each callable module (not here) — zod is a
// Lane B Wave 1 dependency; frozen types are plain TypeScript only.

// ---------------------------------------------------------------------------
// Core enums
// ---------------------------------------------------------------------------

export type ContextSource =
  | "calendar"
  | "location"
  | "contacts"
  | "prayerHistory"
  | "readingHistory"
  | "notesContent"
  | "messagesMeta"
  | "churchProfile";

export type ContextPolicy = "never" | "askEveryTime" | "whileUsing" | "always";

export type CapabilitySurface = "berean" | "messages" | "notes";

export type PrayerCategory = "health" | "work" | "spiritual" | "family" | "other";

export type PrayerStatus = "active" | "answered" | "archived";

export type PrayerFollowUpStatus = "pending" | "done" | "dismissed" | "prompted";

export type BibleTranslation = "BSB" | "WEB" | "KJV";

// ---------------------------------------------------------------------------
// Context Engine types
// ---------------------------------------------------------------------------

export interface ContextDecision {
  source: ContextSource;
  decision: "allowed" | "denied" | "promptRequired";
  reason?: "notGranted" | "backgroundDenied" | "notYetSupported";
  requestId: string;
}

export interface ContextAuditEntry {
  source: ContextSource;
  capabilityId: string;
  decision: "allowed" | "denied" | "promptRequired";
  requestId: string;
  at: string; // ISO 8601
}

// Internal (non-callable) resolveContextAccess types
export interface ResolveAccessInput {
  uid: string;
  capabilityId: string;
  sources: ContextSource[];
  invocationType: "foreground" | "background";
}

export interface ResolveAccessOutput {
  decisions: ContextDecision[];
  allAllowed: boolean;
}

// ---------------------------------------------------------------------------
// Callable request/response: contextEngine_getGrants
// ---------------------------------------------------------------------------

export type GetGrantsRequest = Record<string, never>;

export interface ContextGrantWire {
  source: ContextSource;
  policy: ContextPolicy;
  grantedAt: string;
  updatedAt: string;
  version: number;
}

export interface GetGrantsResponse {
  grants: ContextGrantWire[];
}

// ---------------------------------------------------------------------------
// Callable request/response: contextEngine_setGrant
// ---------------------------------------------------------------------------

export interface SetGrantRequest {
  source: ContextSource;
  policy: ContextPolicy;
}

export interface SetGrantResponse {
  source: ContextSource;
  policy: ContextPolicy;
  version: number;
  updatedAt: string;
}

// ---------------------------------------------------------------------------
// Callable request/response: contextEngine_getAuditLog
// ---------------------------------------------------------------------------

export interface GetAuditLogRequest {
  pageSize?: number;    // default 20, max 50
  startAfter?: string;
}

export interface GetAuditLogResponse {
  entries: ContextAuditEntry[];
  nextCursor?: string;
}

// ---------------------------------------------------------------------------
// Capability Registry
// ---------------------------------------------------------------------------

export interface CapabilityManifest {
  id: string;
  displayName: string;
  tagline: string;
  iconSymbol: string;
  surfaces: CapabilitySurface[];
  requiredContext: ContextSource[];
  optionalContext: ContextSource[];
  entryFunction: string;
  minAppVersion: string;
  status: "active" | "disabled";
  tier: "free" | "plus";
}

export interface CapabilityListRequest {
  surface: CapabilitySurface;
}

export interface CapabilityListResponse {
  capabilities: CapabilityManifest[];
}

// ---------------------------------------------------------------------------
// Prayer OS types
// ---------------------------------------------------------------------------

export interface PrayerSubjectWire {
  type: "person" | "topic";
  displayName: string;
  linkedContactRef?: string;
}

export interface PrayerReminderWire {
  rrule: string;
  nextFireAt: string; // ISO 8601
}

export interface PrayerFollowUpWire {
  dueAt: string; // ISO 8601
  status: PrayerFollowUpStatus;
  note?: string;
}

export interface PrayerCardWire {
  cardId: string;
  subject: PrayerSubjectWire;
  category: PrayerCategory;
  detail: string;
  status: PrayerStatus;
  createdAt: string;
  updatedAt: string;
  reminders: PrayerReminderWire[];
  followUps: PrayerFollowUpWire[];
}

// Callable: prayerOS_createCard
export interface PrayerCreateCardRequest {
  subject: PrayerSubjectWire;
  category: PrayerCategory;
  detail: string;       // max 2000 chars; encrypted server-side before Firestore write
  reminders?: PrayerReminderWire[];
  followUps?: PrayerFollowUpWire[];
}

export interface PrayerCreateCardResponse {
  cardId: string;
  dedupeWarning?: {
    existingCardId: string;
    displayName: string;
  };
}

// Callable: prayerOS_updateCard
export interface PrayerUpdateCardRequest {
  cardId: string;
  patch: {
    detail?: string;
    category?: PrayerCategory;
    status?: PrayerStatus;
    reminders?: PrayerReminderWire[];
    followUps?: PrayerFollowUpWire[];
  };
}

export interface PrayerUpdateCardResponse {
  updatedAt: string;
}

// Callable: prayerOS_listCards
export interface PrayerListCardsRequest {
  status?: PrayerStatus;  // default "active"
  pageSize?: number;      // default 20, max 50
  startAfter?: string;
}

export interface PrayerListCardsResponse {
  cards: PrayerCardWire[];
  nextCursor?: string;
}

// Callable: prayerOS_completeFollowUp
export interface PrayerCompleteFollowUpRequest {
  cardId: string;
  followUpIndex: number;
  note?: string;
}

export interface PrayerCompleteFollowUpResponse {
  updatedAt: string;
}

// ---------------------------------------------------------------------------
// Scripture Intelligence types
// ---------------------------------------------------------------------------

export interface ScriptureBlock {
  blockId: string;
  text: string;
}

export interface ScriptureDetection {
  blockId: string;
  range: { start: number; end: number };
  osisRef: string;
  display: string;
}

// Callable: scripture_detectReferences
export interface ScriptureDetectRequest {
  blocks: ScriptureBlock[]; // min 1, max 50
}

export interface ScriptureDetectResponse {
  detections: ScriptureDetection[];
}

// Callable: scripture_getVerses
export interface ScriptureGetVersesRequest {
  osisRefs: string[];             // min 1, max 20
  translation?: BibleTranslation; // default "BSB"
}

export interface VerseResult {
  osisRef: string;
  text: string;
  translation: BibleTranslation;
  display: string;
}

export interface ScriptureGetVersesResponse {
  verses: VerseResult[];
}

// Callable: scripture_searchVerses
export interface ScriptureSearchRequest {
  query: string;   // min 1, max 200 chars
  limit?: number;  // default 5, max 10
}

export interface ScriptureSearchResult {
  osisRef: string;
  display: string;
  snippet: string; // first 120 chars of verse text
}

export interface ScriptureSearchResponse {
  results: ScriptureSearchResult[];
}

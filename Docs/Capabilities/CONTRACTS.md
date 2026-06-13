# Capabilities v1 — Frozen Contracts

**STATUS: FROZEN (Wave 0)**
Do not modify this file post-freeze. File a `CONTESTED` blocker in BLOCKERS.md if a contract change is required.

Frozen at Wave 0 gate. All field names here are wire-format law.

---

## 1. Feature Flags

| Swift property | Remote Config key | Default |
|---|---|---|
| `capabilitiesCoreEnabled` | `capabilities_core` | `false` |
| `capabilityPickerEnabled` | `capability_picker` | `false` |
| `prayerOSEnabled` | `prayer_os` | `false` |
| `scriptureIntelligenceEnabled` | `scripture_intelligence` | `false` |
| `verseLookupInlineEnabled` | `verse_lookup_inline` | `false` |

All five flags default OFF. Flip individually in Firebase Remote Config after staging E2E verification passes.

---

## 2. Firestore Schema

### 2.1 Context Engine

```
users/{uid}/contextGrants/{sourceId}
  source: "calendar" | "location" | "contacts" | "prayerHistory" |
          "readingHistory" | "notesContent" | "messagesMeta" | "churchProfile"
  policy: "never" | "askEveryTime" | "whileUsing" | "always"
  grantedAt: Timestamp
  updatedAt: Timestamp
  version: number            // incremented on every policy change

users/{uid}/contextAuditLog/{autoId}
  source: string             // one of the source enum values above
  capabilityId: string       // capability that requested access
  decision: "allowed" | "denied" | "promptRequired"
  requestId: string          // UUID generated per resolveContextAccess call
  at: Timestamp
```

### 2.2 Capability Registry

```
capabilities/{capabilityId}
  id: string
  displayName: string
  tagline: string
  iconSymbol: string                           // SF Symbol name
  surfaces: ("berean" | "messages" | "notes")[]
  requiredContext: string[]                    // contextGrant source ids
  optionalContext: string[]
  entryFunction: string                        // callable function name
  minAppVersion: string
  status: "active" | "disabled"
  tier: "free" | "plus"

users/{uid}/capabilityState/{capabilityId}
  enabled: boolean
  installedAt: Timestamp
  lastUsedAt: Timestamp
```

### 2.3 Prayer OS

```
users/{uid}/prayerCards/{cardId}
  subject: {
    type: "person" | "topic"
    displayName: string
    linkedContactRef?: string                  // Firestore path, optional
  }
  category: "health" | "work" | "spiritual" | "family" | "other"
  detail: string                               // Tier C — encrypted at rest
  status: "active" | "answered" | "archived"
  createdAt: Timestamp
  updatedAt: Timestamp
  reminders: {
    rrule: string                              // RFC 5545 RRULE
    nextFireAt: Timestamp
  }[]
  followUps: {
    dueAt: Timestamp
    status: "pending" | "done" | "dismissed"
    note?: string
  }[]
```

### 2.4 Scripture Cache

```
scriptureCache/{translation}/{osisRef}
  text: string                                 // licensed verse text
  translation: string                          // "BSB" | "WEB" | "KJV"
  osisRef: string
  cachedAt: Timestamp
  expiresAt: Timestamp                         // 90 days per API.Bible terms
```

---

## 3. Callable Cloud Function Signatures

All callables are App Check enforced. All inputs validated with zod.

### 3.1 Context Engine

```typescript
// contextEngine_getGrants
// Returns all current grant states for the authenticated user.
Request: {}
Response: {
  grants: {
    source: ContextSource;
    policy: ContextPolicy;
    grantedAt: string; // ISO 8601
    updatedAt: string;
    version: number;
  }[];
}

// contextEngine_setGrant
// Upserts a context grant. Increments version atomically.
Request: {
  source: ContextSource;
  policy: ContextPolicy;
}
Response: {
  source: ContextSource;
  policy: ContextPolicy;
  version: number;
  updatedAt: string;
}

// contextEngine_getAuditLog
// Paginated audit log for the authenticated user only.
Request: {
  pageSize?: number;         // default 20, max 50
  startAfter?: string;       // Firestore document ID cursor
}
Response: {
  entries: ContextAuditEntry[];
  nextCursor?: string;       // undefined = no more pages
}
```

### 3.2 Capability Registry

```typescript
// capabilityRegistry_list
// Returns active capabilities for a surface, filtered by flag state.
// Flag state evaluated server-side via Remote Config Admin SDK.
Request: {
  surface: CapabilitySurface;
}
Response: {
  capabilities: CapabilityManifest[];
}
```

### 3.3 Prayer OS

```typescript
// prayerOS_createCard
Request: {
  subject: PrayerSubjectWire;
  category: PrayerCategory;
  detail: string;            // max 2000 chars; encrypted server-side before write
  reminders?: PrayerReminderWire[];
  followUps?: PrayerFollowUpWire[];
}
Response: {
  cardId: string;
  dedupeWarning?: {          // present if context allowed + existing card found
    existingCardId: string;
    displayName: string;
  };
}

// prayerOS_updateCard
Request: {
  cardId: string;
  patch: Partial<{
    detail: string;
    category: PrayerCategory;
    status: PrayerStatus;
    reminders: PrayerReminderWire[];
    followUps: PrayerFollowUpWire[];
  }>;
}
Response: { updatedAt: string }

// prayerOS_listCards
Request: {
  status?: PrayerStatus;     // default: "active"
  pageSize?: number;         // default 20, max 50
  startAfter?: string;
}
Response: {
  cards: PrayerCardWire[];
  nextCursor?: string;
}

// prayerOS_completeFollowUp
Request: {
  cardId: string;
  followUpIndex: number;
  note?: string;
}
Response: { updatedAt: string }
```

### 3.4 Scripture Intelligence

```typescript
// scripture_detectReferences
// Deterministic parser — no LLM, fast, free.
Request: {
  blocks: { blockId: string; text: string }[];
}
Response: {
  detections: {
    blockId: string;
    range: { start: number; end: number };  // char offsets in block text
    osisRef: string;                         // e.g. "Rom.6.1-Rom.6.4"
    display: string;                         // e.g. "Romans 6:1-4"
  }[];
}

// scripture_getVerses
Request: {
  osisRefs: string[];
  translation?: "BSB" | "WEB" | "KJV";  // default "BSB"
}
Response: {
  verses: {
    osisRef: string;
    text: string;
    translation: "BSB" | "WEB" | "KJV";
    display: string;                         // formatted reference label
  }[];
}

// scripture_searchVerses
// Keyword/reference search over known corpus.
Request: {
  query: string;             // reference string or keyword phrase
  limit?: number;            // default 5, max 10
}
Response: {
  results: {
    osisRef: string;
    display: string;
    snippet: string;         // first 120 chars of verse text
  }[];
}
```

---

## 4. Shared TypeScript Types (functions/src/capabilities/types.ts — FROZEN)

```typescript
export type ContextSource =
  | "calendar" | "location" | "contacts"
  | "prayerHistory" | "readingHistory"
  | "notesContent" | "messagesMeta" | "churchProfile";

export type ContextPolicy = "never" | "askEveryTime" | "whileUsing" | "always";

export type CapabilitySurface = "berean" | "messages" | "notes";

export type PrayerCategory = "health" | "work" | "spiritual" | "family" | "other";
export type PrayerStatus = "active" | "answered" | "archived";

export interface ContextDecision {
  source: ContextSource;
  decision: "allowed" | "denied" | "promptRequired";
  reason?: "notGranted" | "backgroundDenied" | "notYetSupported";
  requestId: string;
}

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
  status: "pending" | "done" | "dismissed";
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

export interface ContextAuditEntry {
  source: ContextSource;
  capabilityId: string;
  decision: "allowed" | "denied" | "promptRequired";
  requestId: string;
  at: string; // ISO 8601
}

export interface ScriptureDetection {
  blockId: string;
  range: { start: number; end: number };
  osisRef: string;
  display: string;
}

export interface VerseResult {
  osisRef: string;
  text: string;
  translation: "BSB" | "WEB" | "KJV";
  display: string;
}
```

---

## 5. Shared Swift Types (AMENAPP/AMENAPP/Capabilities/CapabilityModels.swift — FROZEN)

```swift
// CapabilitySurface
enum CapabilitySurface: String, Codable, CaseIterable {
    case berean, messages, notes
}

// ContextSource
enum ContextSource: String, Codable, CaseIterable {
    case calendar, location, contacts
    case prayerHistory, readingHistory
    case notesContent, messagesMeta, churchProfile
}

// ContextPolicy
enum ContextPolicy: String, Codable, CaseIterable {
    case never, askEveryTime, whileUsing, always
}

// ContextGrant — mirrors Firestore users/{uid}/contextGrants/{sourceId}
struct ContextGrant: Codable, Identifiable, Equatable {
    var id: String { source.rawValue }
    let source: ContextSource
    let policy: ContextPolicy
    let grantedAt: Date
    let updatedAt: Date
    let version: Int
}

// ContextDecision — returned by contextEngine callable internals
struct ContextDecision: Codable, Equatable {
    let source: ContextSource
    let decision: ContextDecisionKind
    let reason: ContextDenialReason?
    let requestId: String
}
enum ContextDecisionKind: String, Codable { case allowed, denied, promptRequired }
enum ContextDenialReason: String, Codable { case notGranted, backgroundDenied, notYetSupported }

// Capability — mirrors capabilities/{capabilityId}
struct Capability: Codable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let tagline: String
    let iconSymbol: String
    let surfaces: [CapabilitySurface]
    let requiredContext: [ContextSource]
    let optionalContext: [ContextSource]
    let entryFunction: String
    let minAppVersion: String
    let status: CapabilityStatus
    let tier: CapabilityTier
}
enum CapabilityStatus: String, Codable { case active, disabled }
enum CapabilityTier: String, Codable { case free, plus }

// PrayerCard — mirrors users/{uid}/prayerCards/{cardId}
struct PrayerCard: Codable, Identifiable, Equatable {
    let id: String
    let subject: PrayerSubject
    let category: PrayerCategory
    let detail: String
    let status: PrayerStatus
    let createdAt: Date
    let updatedAt: Date
    let reminders: [PrayerReminder]
    let followUps: [PrayerFollowUp]
}
struct PrayerSubject: Codable, Equatable {
    let type: PrayerSubjectType
    let displayName: String
    let linkedContactRef: String?
}
enum PrayerSubjectType: String, Codable { case person, topic }
enum PrayerCategory: String, Codable, CaseIterable {
    case health, work, spiritual, family, other
}
enum PrayerStatus: String, Codable { case active, answered, archived }
struct PrayerReminder: Codable, Equatable {
    let rrule: String
    let nextFireAt: Date
}
struct PrayerFollowUp: Codable, Equatable {
    let dueAt: Date
    let status: PrayerFollowUpStatus
    let note: String?
}
enum PrayerFollowUpStatus: String, Codable { case pending, done, dismissed }

// ScriptureRef — scripture detection result
struct ScriptureRef: Codable, Identifiable, Equatable {
    var id: String { osisRef }
    let blockId: String
    let rangeStart: Int
    let rangeEnd: Int
    let osisRef: String  // e.g. "Rom.6.1-Rom.6.4"
    let display: String  // e.g. "Romans 6:1-4"
}

// VerseCard — resolved verse for display and insertion
struct VerseCard: Codable, Identifiable, Equatable {
    var id: String { "\(translation.rawValue)-\(osisRef)" }
    let osisRef: String
    let text: String
    let translation: BibleTranslation
    let display: String
}
enum BibleTranslation: String, Codable, CaseIterable {
    case BSB, WEB, KJV
    var displayName: String {
        switch self {
        case .BSB: return "Berean Study Bible"
        case .WEB: return "World English Bible"
        case .KJV: return "King James Version"
        }
    }
}
```

---

## 6. Internal Context Engine API (TS, not client-facing)

```typescript
// functions/src/contextEngine/resolveContextAccess.ts

interface ResolveAccessInput {
  uid: string;
  capabilityId: string;
  sources: ContextSource[];
  invocationType: "foreground" | "background";
}

interface ResolveAccessOutput {
  decisions: ContextDecision[];
  // allAllowed: true if every requested source resolved to "allowed"
  allAllowed: boolean;
}

// Every call writes one contextAuditLog entry per source requested.
// "whileUsing" policies deny background invocations.
// Device-level sources (calendar, location) always return denied: "notYetSupported".
export function resolveContextAccess(input: ResolveAccessInput): Promise<ResolveAccessOutput>
```

---

## 7. Capability Registry Seeds

Three v1 capabilities seeded by `functions/scripts/seedCapabilities.ts`:

| id | displayName | surfaces | requiredContext |
|---|---|---|---|
| `prayer_os` | Prayer OS | berean, messages | prayerHistory |
| `scripture_intelligence` | Scripture Intelligence | notes | notesContent, readingHistory |
| `verse_lookup` | Verse Lookup | berean, messages, notes | readingHistory |

---

## 8. Capability Picker Behavior Contract

- `@` typed at a word boundary in a wired composer → picker appears
- Picker lists: `capabilities(for: surface).filter { $0.status == .active && flagFor($0.id) }`
- Selection dispatches to `CapabilityComposerCoordinator`
- Inline capabilities (Verse Lookup): search UI → result → insert into composer
- Sheet capabilities (Prayer OS): present as sheet, composer remains open in background
- Dismissal: swipe down, Escape, tap outside (all surface the picker dismiss, not the composer)
- VoiceOver: every row labeled `"\(displayName) — \(tagline)"`, trait `.button`
- Dynamic Type: all text uses text styles, no fixed font sizes
- Reduced motion: no spring animation on picker appearance, use `.easeInOut(duration: 0.2)`

---

## 9. Notification Routing Contract

Prayer OS follow-up and reminder notifications route via the **existing notification pipeline** (do not build a parallel FCM path). The `prayerOS_followUpSweep` scheduled function:
1. Finds `prayerCards` where `followUps[].status == "pending"` and `followUps[].dueAt <= now`
2. Calls the existing `sendNotification` internal function (same path used by action threads, prayer OS v1)
3. Deep link payload: `amen://capabilities/prayer-os/card/{cardId}`
4. Idempotency: marks `followUps[].status = "prompted"` before sending; sweep skips `"prompted"` status

---

## 10. Error Contract

All callables return Firebase `HttpsError` on failure. Client treats these error codes:
- `unauthenticated` → sign-in prompt
- `failed-precondition` (code `"flag_disabled"`) → capability silently hidden (flag OFF)
- `permission-denied` → capability degraded, no error shown to user (context denied)
- `invalid-argument` → developer bug, log to crash reporter
- `resource-exhausted` → show "try again later" toast

---

*FROZEN at Wave 0 gate. Commit hash appended when WAVE 0 gate is passed.*

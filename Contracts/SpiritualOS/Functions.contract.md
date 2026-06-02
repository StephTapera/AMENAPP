# Cloud Functions Contract — Spiritual OS
## STATUS: FROZEN · Do not edit without Lead Orchestrator sign-off

All new Firebase Cloud Functions v2 callables and scheduled functions are
documented here. Agents must consume these exact names and shapes.
No client-side model calls — all AI/model traffic goes through these proxies.

---

## Global Rules for All Functions

1. **App Check + Auth:** All callables set `enforceAppCheck: true` and verify `request.auth?.uid` before any logic. Throw `unauthenticated` if missing.
2. **Rate limiting:** Use the shared `callWithTimeout(ms: 10000)` helper (existing in codebase). Callables that call external AI APIs additionally enforce per-user rate limits via Firestore counter (max 30 AI calls/hour).
3. **No raw location stored:** Any CF that receives location data resolves it to an entity ID (churchId, eventId) and discards coordinates before writing to Firestore.
4. **Berean proxy:** Functions marked `[Berean]` proxy requests to Anthropic Claude. System prompt is server-side only. The client never sees the system prompt or the raw API key.
5. **Error codes:** Use Firebase `HttpsError` codes (`unauthenticated`, `permission-denied`, `invalid-argument`, `resource-exhausted`, `internal`). Never expose internal error details to the client.
6. **Aegis integration:** Functions marked `[Aegis]` call `aegisGuardian` or `aegisContentCheck` before writing content.

---

## Callable Functions

### `generateDailyDigest` [Berean] [Scheduled also]

**Trigger:** Callable (pull-to-refresh) + Scheduled (6 AM local via timezone-aware schedule).  
**Gating:** `enforceAppCheck: true`, Auth required.

```typescript
// Request
interface GenerateDailyDigestRequest {
  forceRefresh?: boolean;   // skip cache if true
}

// Response
interface GenerateDailyDigestResponse {
  ok: boolean;
  date: string;             // "2026-06-01"
  cachedAt: string | null;  // ISO timestamp if served from cache
}
```

**Logic:**
1. Check `users/{uid}/dailyDigest/{today}` — if exists and < 6h old, return cached.
2. Fetch: today's verse (Bible API), pending prayer requests, upcoming events (48h), unread mentions, pinned Berean sessions, birthdays.
3. Call Anthropic Claude to generate `greeting` string. System prompt includes user's first name, today's verse, time of day.
4. Write `DailyDigest` doc. Return `ok: true`.

---

### `getHubItems` 

**Trigger:** Callable (initial page load + pull-to-refresh; real-time listener handles updates).  
**Gating:** `enforceAppCheck: true`, Auth required.

```typescript
// Request
interface GetHubItemsRequest {
  pageSize?: number;        // default 25, max 50
  afterCursor?: string;     // Firestore document ID for pagination
  faithTagFilter?: string;  // "Prayer" | "Church" | etc. | null = all
}

// Response
interface GetHubItemsResponse {
  ok: boolean;
  items: HubItem[];
  nextCursor: string | null;
  unreadCount: number;
}
```

---

### `markHubItemRead`

**Trigger:** Callable.  
**Gating:** `enforceAppCheck: true`, Auth required.

```typescript
// Request
interface MarkHubItemReadRequest {
  itemId: string;
  action: "read" | "archive" | "pin" | "unpin";
}
// Response: { ok: boolean }
```

---

### `getLifePlannerEvents`

**Trigger:** Callable.  
**Gating:** `enforceAppCheck: true`, Auth required.

```typescript
// Request
interface GetLifePlannerEventsRequest {
  startDate: string;        // "YYYY-MM-DD"
  endDate: string;          // "YYYY-MM-DD", max 14 days ahead
}

// Response
interface GetLifePlannerEventsResponse {
  ok: boolean;
  events: LifePlannerEvent[];
  bereanSuggestions: BereanPlannerSuggestion[];
}

interface BereanPlannerSuggestion {
  eventId: string;
  suggestionText: string;  // "Men's study tonight — read Romans 12?"
  deepLink: string;
}
```

---

### `mirrorSpaceEventToPlanner` [Internal, triggered by Space event write]

**Trigger:** Firestore `onDocumentCreated` trigger on `spaces/{spaceId}/events/{eventId}`.  
**Logic:** For each member in `spaces/{spaceId}/members/`, write a mirrored `LifePlannerEvent` to `users/{uid}/lifePlannerEvents/`. Idempotent (upsert by `sourceId`).

---

### `createSpace` [Aegis]

**Trigger:** Callable.  
**Gating:** `enforceAppCheck: true`, Auth required.

```typescript
// Request
interface CreateSpaceRequest {
  name: string;             // max 60 chars
  description: string;      // max 500 chars
  coverTintHex: string;     // must be amenGold/amenPurple/amenBlue hex
  churchAffiliation?: string;
  liturgicalTagIds?: string[];
  privacy: "public" | "private" | "secret";
  encryptionEnabled?: boolean;
  moderationEnabled?: boolean;
  features: SpaceFeatures;
  addBereanAsMember?: boolean;
  initialMemberUids?: string[];  // max 50
}

// Response
interface CreateSpaceResponse {
  ok: boolean;
  spaceId: string;
  bereanMemberId: string | null;
}
```

**Logic:**
1. Validate all fields. Run `aegisContentCheck` on `name` + `description`.
2. Create `spaces/{spaceId}` document.
3. Write creator as `leader` in `spaces/{spaceId}/members/{uid}`.
4. If `addBereanAsMember: true`, create a synthetic `bereanMemberId` entry and set `bereanMemberId` on the Space.
5. If `initialMemberUids` provided, create member docs (role: `member`).
6. If `privacy == "private"` and `encryptionEnabled: true`, flag Space for E2E key setup.

---

### `getSpaceDashboard`

**Trigger:** Callable.  
**Gating:** `enforceAppCheck: true`, Auth required, caller must be Space member.

```typescript
// Request
interface GetSpaceDashboardRequest {
  spaceId: string;
}

// Response
interface GetSpaceDashboardResponse {
  ok: boolean;
  space: Space;
  members: SpaceMember[];        // up to 20 (full list via paginated sub-call)
  nextEvent: SpaceEvent | null;
  activePrayerRequests: SpacePrayerRequest[];  // max 5
  activeSeriesTitle: string | null;
  memberCount: number;
}
```

---

### `getCommandCenter`

**Trigger:** Callable (pull-to-refresh) + Scheduled (daily 7 AM).  
**Gating:** `enforceAppCheck: true`, Auth required.

```typescript
// Request: {} (empty, uses auth uid)

// Response
interface GetCommandCenterResponse {
  ok: boolean;
  commandCenter: CommandCenter;
}
```

---

### `generateSmartSuggestions` [Berean]

**Trigger:** Callable.  
**Gating:** `enforceAppCheck: true`, Auth required.  
**Rate limit:** Max 10 calls/hour per user (AI-backed).

```typescript
// Request
interface GenerateSmartSuggestionsRequest {
  currentSurface: SOSurface;
  contextMode: ContextMode;        // from client contextState
}

// Response
interface GenerateSmartSuggestionsResponse {
  ok: boolean;
  suggestions: Suggestion[];       // max 10
}
```

**Logic:** Sends minimal context (surface, mode, today's verse reference, user's active Space IDs, current time of day) to Claude. System prompt instructs Claude to return faith-native, gentle study/prayer prompts as structured JSON. Response is validated against `Suggestion[]` schema before write.

---

### `updateContextState` [Aegis]

**Trigger:** Callable (called by on-device Context Engine, not directly by UI views).  
**Gating:** `enforceAppCheck: true`, Auth required.

```typescript
// Request
interface UpdateContextStateRequest {
  // Client sends RESOLVED identifiers — never raw coordinates
  nearbyChurchId?: string | null;
  nearbyChurchName?: string | null;
  isDriving?: boolean;
  isTraveling?: boolean;
  timeOfDay?: "morning" | "midday" | "evening" | "night";
  dayOfWeek?: number;
  lastKnownEventCheckIn?: string | null;
  consentFlags?: {
    location?: boolean;
    motion?: boolean;
    calendar?: boolean;
  };
}

// Response: { ok: boolean; mode: ContextMode }
```

**Privacy:** CF computes `mode` and `subMode` server-side from the resolved identifiers. No raw location ever written to Firestore.

---

### `askBerean` [Berean] [Aegis]

**Trigger:** Callable (shared across all Berean surfaces).  
**Gating:** `enforceAppCheck: true`, Auth required.  
**Rate limit:** 30 AI calls/hour/user.

```typescript
// Request
interface AskBereanRequest {
  prompt: string;             // max 1000 chars
  surface: SOSurface;
  contextMode: ContextMode;
  spaceId?: string | null;
  imageBase64?: string | null;  // Vision OCR — max 4MB
  voiceTranscript?: string | null;
}

// Response
interface AskBereanResponse {
  ok: boolean;
  answer: string;
  scriptureReferences: string[];   // ["Romans 8:28", …]
  followUpPrompts: string[];       // max 3 gentle follow-ups
  sessionId: string;
}
```

**Logic:**
1. `aegisContentCheck` on prompt.
2. If `imageBase64` provided, run Vision OCR to extract text/verse reference before sending to Claude.
3. Call Claude with scripture-grounded system prompt. Response must cite at least one scripture reference.
4. Write session to `users/{uid}/bereanSessions/{sessionId}`.

---

## Scheduled Functions

| Function | Schedule | Purpose |
|---|---|---|
| `generateDailyDigest` | 6 AM local per user (timezone-aware) | Pre-generate daily briefing |
| `refreshCommandCenter` | Daily 7 AM | Aggregate formation stats |
| `expireSuggestions` | Every 6h | Remove stale `suggestions` docs |
| `mirrorSpaceEvents` | Firestore trigger | Keep `lifePlannerEvents` in sync |

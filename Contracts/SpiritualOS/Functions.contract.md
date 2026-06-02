# FROZEN — Cloud Functions Contract · Spiritual OS
> Version 1.0 · 2026-06-02 · Lead Orchestrator
> ⚠️ FROZEN. All new functions are v6 callables. App Check + Auth required on every function.
> Agents NEVER call AI models client-side. All model calls go through these server-side proxies.

---

## Universal Gating Requirements

Every function here MUST enforce:
1. `context.auth` present and valid (unauthenticated → reject)
2. App Check token validated (permission-denied if missing)
3. Caller UID must match `userId` in request payload (no cross-user reads)
4. Rate limiting via existing `rateLimiter.js` (max 60 calls/min per UID)

---

## getSpiritualDigest
Generates or retrieves current day's personalized digest.

Request:
```json
{ "userId": "string", "forceRefresh": "boolean (optional, default false)" }
```

Response:
```json
{
  "greeting": "string",
  "items": [{ "itemId", "type", "title", "body", "sourceRef", "priority", "isRead" }],
  "timeOfDay": "morning|afternoon|evening|night",
  "generatedAt": "ISO8601"
}
```

Proxies: Anthropic Claude (greeting + verse selection). Falls back to seeded verse if Claude unavailable.
Writes to: `spiritualOS_digest/{userId}/items/*`

---

## getHubItems
Returns paginated unified inbox stream.

Request:
```json
{
  "userId": "string",
  "lastItemId": "string|null",
  "pageSize": "number (max 30, default 20)",
  "filterType": "string|null"
}
```

Response: `{ "items": [...], "hasMore": boolean, "nextCursor": "string|null" }`

No AI proxying — purely Firestore reads from pre-written `spiritualOS_hub` items.

---

## getPlannerEvents
Returns planner events for a date range, merged from Space events + prayer plans.

Request:
```json
{
  "userId": "string",
  "startDate": "ISO8601",
  "endDate": "ISO8601",
  "includeBereanSuggestions": "boolean (default true)"
}
```

Response: `{ "events": [...], "suggestions": [{ "itemId", "promptLabel", "bereanNote", "targetDate" }] }`

AI proxying (optional): Claude for gentle bereanNote suggestions only when includeBereanSuggestions=true.

---

## getPlannerSuggestions
Generates AI formation suggestions for upcoming dates (dismissible nudges).

Request:
```json
{
  "userId": "string",
  "contextMode": "string",
  "upcomingEventTitles": ["string"]
}
```

Response: `{ "suggestions": [{ "surfaceContext", "promptLabel", "promptText", "priority" }] }`

Proxies: Anthropic Claude.
Hard rate: max 5 suggestions per user per day (CF-enforced, not just client-limited).
Writes to: `spiritualOS_suggestions/{userId}/items/*`
Formation rule: Claude prompt must be constrained to dismissible, invitational tone. No obligation or guilt language.

---

## getAssistantResponse
Berean assistant bar — handles text, voice, and vision (OCR verse detection) queries.

Request:
```json
{
  "userId": "string",
  "query": "string (max 1000 chars)",
  "queryType": "text|voice|vision",
  "surfaceContext": "home|hub|planner|space|commandCenter|assistantBar",
  "imageBase64": "string|null (vision only, max 2MB)",
  "contextMode": "string"
}
```

Response:
```json
{
  "answer": "string",
  "sources": [{ "type": "scripture|bereanNote|churchNote|external", "ref", "title", "snippet" }],
  "suggestedFollowUps": ["string (max 3)"],
  "aiDisclosureLabel": "string (required)"
}
```

Proxies: Anthropic Claude + Pinecone (bereanMemory/churchNotes vectors) + Algolia (scripture search).
Vision: image processed in-flight only — NOT stored. imageBase64 bytes are never persisted.

---

## updateContextState
Client pushes context mode updates to server for digest personalization.

Request:
```json
{
  "userId": "string",
  "mode": "default|worship|driving|travel|focus|rest",
  "isSundayChurchTime": "boolean",
  "isNearChurch": "boolean",
  "isDriving": "boolean",
  "isTraveling": "boolean",
  "userPermissions": { "locationEnabled", "motionEnabled", "geofenceOptIn", "audioAutoPlay": "boolean" }
}
```

Response: `{ "success": true }`
Writes to: `spiritualOS_context/{userId}` (upsert).
Privacy: Server never logs isNearChurch beyond the live document. No analytics pipeline receives this.

---

## dismissSuggestion
User dismisses a Berean suggestion or planner nudge.

Request: `{ "userId": "string", "itemId": "string", "collectionHint": "suggestions|planner" }`
Response: `{ "success": true }`
Writes: `isDismissed: true` on relevant document.

---

## pinHubItem
User pins or unpins a Hub item ("keep praying" gesture).

Request: `{ "userId": "string", "itemId": "string", "isPinned": "boolean" }`
Response: `{ "success": true }`
Writes: `isPinned` on `spiritualOS_hub/{userId}/items/{itemId}`.

---

## cleanupContextOnLogout
Wipes context state document on logout.

Request: `{ "userId": "string" }`
Response: `{ "success": true }`
Writes: Deletes `spiritualOS_context/{userId}`.
Wire-in: Must be called in existing logout sequence (AuthenticationManager or equivalent).

---

## AI Disclosure Requirement
Every response from `getAssistantResponse` and `getPlannerSuggestions` MUST include `aiDisclosureLabel`.
Client MUST display this via existing `AmenAIUsageLabel` component (`AMENAPP/AMENAPP/AIIntelligence/AmenAIUsageLabel.swift`).

---

## Existing Functions Consumed (NOT modified)
- `bereanFunctions` → AssistantBar scripture Q&A passthrough
- `mlNotificationIntelligence` → Hub item prioritization
- `prayerArcFunctions` → Planner prayer plan events
- `eventFunctions` → Planner Space event data
- `churchEnhancementFunctions` → Context Engine church location

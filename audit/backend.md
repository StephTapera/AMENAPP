# Backend / Cloud Functions Integrity Audit

**Date:** 2026-05-28  
**Scope:** `functions/` (JS, Gen2 default codebase) + `Backend/functions/src/` (TypeScript, "backend" codebase)  
**Auditor:** Claude Code automated audit  

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| `functions/contentModeration.js:32` | Blocker | Gen1 / No App Check | `moderateContent` uses Gen1 `functions.https.onCall()` — no App Check enforcement, no `enforceAppCheck` option at all. Any non-app HTTP client can call it. |
| `functions/dist-notifications/AMENAPP/AMENAPP/CloudFunction_NotificationRoutingPipeline.js:598` | Blocker | Gen1 / No Auth | `composeNotificationPayload`, `dispatchPush`, `recordNotificationOpen`, `markNotificationRead` are Gen1 callables with **no `context.auth` check** in the handlers. Any caller can forge notification payloads. |
| `AMENAPP/BereanVoiceViewModel.swift:280,336` | Blocker | Ghost Function | iOS calls `bereanVoiceProxy` and `ttsProxy` via `httpsCallable()` — **neither function exists anywhere in `functions/` or `Backend/functions/src/`**. Feature flags `berean_voice_proxy_enabled` and `tts_proxy_enabled` default `true`, so the UI calls these on every voice session, gets `NOT_FOUND`, and the voice feature silently fails. |
| `AMENAPP/CarPlay/BereanDriveSessionService.swift:109,136,165,201,234` | Blocker | Ghost Functions | CarPlay calls five functions that do not exist: `bereanDriveRespond`, `bereanDriveSummarize`, `bereanDrivePrayerSession`, `bereanDriveChurchSearch`, `bereanDriveMessageSafetyReview`. All used in live CarPlay driving mode. |
| `functions/openAIFunctions.js:9,30,62,117` | High | No App Check | `openAIProxy`, `whisperProxy`, `transcribeAudio`, `smartSuggestionsProxy` all have `enforceAppCheck: false`. JS codebase versions of these are still deployed (even though they're commented out in `index.js`, the file itself is deployable). The TypeScript versions in `Backend/functions/src/` correctly use `enforceAppCheck: true`; confirm only TS versions are live. |
| `functions/bereanFunctions.js:853,925,978` | High | No App Check | `bereanSermonWeekPlan`, `bereanSpiritualGraphAnalysis`, `bereanSeasonalPrompt` use `enforceAppCheck: false` while holding `OPENAI_API_KEY`. Auth check present but App Check absent means any legitimate user token (stolen/leaked) can drive unlimited LLM spend. |
| `functions/aiPromptFeatures.js:52,91,137,181,219` | High | No App Check | `vibeMatch`, `digestBrain`, `spiritGraph`, and two more callables all use `enforceAppCheck: false`. These functions are **not imported or exported** from `functions/index.js` (orphaned modules) but would be exploitable if deployed directly. |
| `functions/amenStudioAI.js` | High | Orphaned Module | `studioGenerateContent` and `studioJournalPrompt` are defined here and called by iOS (confirmed calls in callables list), but **`amenStudioAI.js` is never imported in `functions/index.js`**. These functions are not deployed — every iOS call to `studioGenerateContent` / `studioJournalPrompt` will return NOT_FOUND. |
| `functions/bereanFunctions.js (line ~976)` | High | Orphaned Module | `bereanSpiritualGraphAnalysis` and `bereanSeasonalPrompt` are defined in `bereanFunctions.js` but **not exported from `functions/index.js`**. They are dead code unless explicitly deployed standalone. |
| `firestore.rules: /prayers/{prayerId}` | High | Privacy Leak | `allow list: if isSignedIn()` permits any authenticated user to collection-scan all prayers without a `userId` filter. Client SDK does add a `where("userId","==",uid)` query, but the rule permits collection-level listing, enabling enumeration of all users' prayer titles and content by crafting a different query. Fix: `allow list: if isSignedIn() && resource.data.userId == request.auth.uid`. |
| `firestore.rules: /bereanSessions/{docId}` | High | Privacy Leak | Same pattern — `allow list: if isSignedIn()` without ownership check on the collection scan. All users' Berean session metadata (question topics, timestamps, model choices) are enumerable. |
| `firestore.rules: /churchJourneys, /churchInteractions, /churchVisits, /churchMemberships` | High | Privacy Leak | All four collections use `allow list: if isSignedIn()` with no ownership constraint. These contain spiritually sensitive location, attendance, and membership data that should be owner-only. |
| `firestore.rules: /notificationDigests, /notificationEngagement` | High | Privacy Leak | `allow list: if isSignedIn()` — any signed-in user can enumerate digest documents (including their `typeCounts` that reveal another user's notification patterns). |
| `firestore.rules: /hashtags/{tagId}` | Med | Over-Permissive Write | `allow update: if isSignedIn()` with no field restriction allows any user to overwrite any hashtag document completely — including clearing post counts, overwriting descriptions, or poisoning the tag. Should be limited to atomic counter increment via CF only. |
| `functions/adminClaims.js:107` | Med | No App Check | `bootstrapFirstAdmin` uses `enforceAppCheck: false`. The `ADMIN_UIDS` env-var guard is functionally correct but the absence of App Check means the function surface is visible to non-app callers. Low severity in practice, but should match all other admin callables. |
| `functions/heyfeedFunctions.js:175,232,254,275` | Med | No App Check | `submitHeyFeedNLRequest`, `removeHeyFeedNLPreference`, `resetHeyFeedNLPreferences`, `parseHeyFeedIntent` all use `enforceAppCheck: false`. Auth check is present. |
| `functions/anonymousBerean.js:18` | Med | No App Check | `anonymousBereanQuery` is explicitly anonymous (no auth required by design) AND has no App Check — rate limit is only `maxInstances: 10`, not per-IP or per-token. Question length is capped at 500 chars but there is no request-level rate limiting. A burst of concurrent requests can drive Anthropic API cost. |
| `functions/authenticationHelpers.js:196,284` | Low | No App Check (intentional) | `checkUsernameAvailability` and a secondary helper have `enforceAppCheck: false` with comment "Allow pre-auth callers." Acceptable for pre-login flow, but worth tracking. |
| `functions/bereanFeaturesFunctions.js:283` | Low | No App Check | One callable in this module uses `enforceAppCheck: false` — review whether it is still used by iOS. |
| `firestore.rules: /prayers/{prayerId} update` | Med | Counter Spoofing | `allow update: if isSignedIn() && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['prayerCount'])` — any signed-in user can set `prayerCount` to any value on any prayer document. Correct fix: move counter writes to a callable (e.g., `onPrayerAnswered`) and block client writes to `prayerCount` entirely. |
| `functions/index.js: Object.assign(exports, require('./dist-notifications/...'))` | Med | Gen1 Mixed Into Gen2 Deploy | The `dist-notifications` pipeline injects four Gen1 callables (`composeNotificationPayload`, `dispatchPush`, `recordNotificationOpen`, `markNotificationRead`) into the Gen2 codebase via `Object.assign(exports, ...)`. Gen1 and Gen2 functions cannot share a deployment in the same codebase entry point without explicit version annotation, and App Check is unavailable for Gen1. |
| `functions/index.js:1449` | Low | Duplicate Export | `translateText` is exported twice: once from `translationFunctions.js` at line 987, and again from `mediaInteractionFns` (Healthy Immersive Media) at line 1449. The second assignment silently overwrites the first. If the two implementations differ, the wrong one may be live. |

---

## Not Fully Wired

### Ghost Functions — iOS calls functions that do not exist in either backend codebase

These functions are called via `httpsCallable()` in live iOS code and have **no corresponding export** in `functions/index.js` or `Backend/functions/src/index.ts`:

| Callable Name | iOS Source File | Notes |
|---------------|-----------------|-------|
| `bereanVoiceProxy` | `BereanVoiceViewModel.swift:280` | Feature-flag `berean_voice_proxy_enabled` defaults `true`; silently fails every voice session |
| `ttsProxy` | `BereanVoiceViewModel.swift:336` | Companion TTS call to voice feature |
| `bereanDriveRespond` | `CarPlay/BereanDriveSessionService.swift:109` | CarPlay primary Berean response |
| `bereanDriveSummarize` | `CarPlay/BereanDriveSessionService.swift:136` | CarPlay summarization |
| `bereanDrivePrayerSession` | `CarPlay/BereanDriveSessionService.swift:165` | CarPlay prayer mode |
| `bereanDriveChurchSearch` | `CarPlay/BereanDriveSessionService.swift:201` | CarPlay church search |
| `bereanDriveMessageSafetyReview` | `CarPlay/BereanDriveSessionService.swift:234` | Safety review for CarPlay messages |
| `studioGenerateContent` | iOS Studio callables | Defined in `amenStudioAI.js` but not imported in `index.js` |
| `studioJournalPrompt` | iOS Studio callables | Same — dead module |
| `spiritGraph` | iOS (confirmed in callable list) | Defined in `aiPromptFeatures.js` but not imported in `index.js` |
| `vibeMatch` | iOS (confirmed in callable list) | Same orphaned module |
| `digestBrain` | iOS (confirmed in callable list) | Same orphaned module |
| `trueSourceSign` | iOS (confirmed in callable list) | Defined in `trueSource.js`, not imported in `index.js` |

### Orphaned JS modules — defined but never imported in `functions/index.js`

These JS files exist in `functions/` and export callables, but are never `require()`-d in `index.js`. They are **not deployed**:

`amenStudioAI.js`, `aiPromptFeatures.js`, `bereanFeaturesFunctions.js` (partial), `trueSource.js`, `synapticFunctions.js`, `livingMemory.js`, `feedContextFunctions.js`, `discoverFunctions.js`, `bereanShield.js`, `testimonyFeatures.js`, `testimonyPrayerFeatures.js`, `accountDeactivation.js`, `aiModeration.js`, `aiProactiveFeatures.js`, `alignmentPipeline.js`, `denormalizeUserPrivacy.js`, `moderateMediaContent.js`, `studioExport.js`, `studioImageGeneration.js`, `v2functions.js`, `242hub.js`, `maintenanceSchedulers.js`, `mentorshipFunctions.js`, `phoneAuthOnly.js`, `semanticEmbeddings.js`

### Functions exported but never called by iOS (deployed but unreachable from client)

These are internal Firestore triggers or scheduled jobs — not callable — so they are correctly deployed without iOS stubs. No action needed: `onUserFollow`, `onUserUnfollow`, `onCommentCreate`, `onPostCreate`, `onAmenCreate`, `onAmenDelete`, `onRepostCreate`, `onPostCreatedML`, `onPostDeletedML`, `weeklyCheckin`, `communityDigest`, etc.

However, the following **callables** are exported in `index.js` but have no confirmed iOS caller and appear to be server-internal or admin-only:
- `exportEngagementData` — no iOS caller found; if callable, any auth'd user could trigger a bulk data export
- `backfillUsernameLookup` — admin one-time callable, should be restricted to admin claim
- `unblockPhoneNumber` — admin operation, verify admin-claim guard is enforced inside the handler

---

## Fix Recommendations

### 1. Blocker — Create `bereanVoiceProxy` and `ttsProxy` (or disable their feature flags)

`BereanVoiceViewModel.swift` calls both on every voice interaction when `berean_voice_proxy_enabled = true`. Either:

**Option A — Create the functions:**
```typescript
// Backend/functions/src/bereanVoiceProxy.ts
export const bereanVoiceProxy = onCall({ secrets: [anthropicApiKey], enforceAppCheck: true }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required");
  // ... Anthropic Claude voice response
});

export const ttsProxy = onCall({ enforceAppCheck: true }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required");
  // ... Google Cloud TTS or OpenAI TTS
});
```

**Option B — Hard-disable the feature flags in Remote Config until functions are built:**
Set `berean_voice_proxy_enabled = false` and `tts_proxy_enabled = false` in Firebase Remote Config.

### 2. Blocker — Create CarPlay BereanDrive functions or disable CarPlay feature flag

`BereanDriveSessionService.swift` calls five functions that don't exist. This causes silent failures when users use CarPlay. Add stubs (matching the pattern in `Backend/functions/src/stubs/missingFunctions.ts`) for each:

```typescript
export const bereanDriveRespond = onCall({ region: "us-central1", enforceAppCheck: true }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Auth required");
  throw new HttpsError("failed-precondition", "CarPlay AI is coming soon.");
});
// Repeat for: bereanDriveSummarize, bereanDrivePrayerSession, bereanDriveChurchSearch, bereanDriveMessageSafetyReview
```

### 3. Blocker — Migrate Gen1 notification pipeline to Gen2

`dist-notifications/...CloudFunction_NotificationRoutingPipeline.js` exports Gen1 callables with no auth or App Check checks. The long-term fix is to compile the TypeScript source (`AMENAPP/AMENAPP/CloudFunction_NotificationRoutingPipeline.ts`) as a Gen2 function with:
```javascript
const { onCall } = require("firebase-functions/v2/https");
// Add: enforceAppCheck: true, and add if (!context.auth) ... guard in each handler
```

Short-term: add auth guards to each handler in the compiled JS.

### 4. High — Fix `prayers` list rule to prevent enumeration

```js
// firestore.rules — CURRENT (insecure):
match /prayers/{prayerId} {
  allow list: if isSignedIn();
}

// FIXED:
match /prayers/{prayerId} {
  allow list: if isSignedIn() && resource.data.userId == request.auth.uid;
}
```

Apply the same fix to: `/bereanSessions`, `/churchJourneys`, `/churchInteractions`, `/churchVisits`, `/churchMemberships`, `/notificationDigests`, `/notificationEngagement`.

**Note:** Firestore rules evaluate `resource.data` per-document during a list query if the query includes a matching `where()` clause. Clients that correctly pass `.where("userId", "==", uid)` will still succeed after this change. Only malicious/unconstrained queries will be denied.

### 5. High — Import orphaned modules or remove them

For each un-imported JS file that contains callable functions iOS calls:

```javascript
// functions/index.js — add these requires and exports
const amenStudioAI = require("./amenStudioAI");
exports.studioGenerateContent = amenStudioAI.studioGenerateContent;
exports.studioJournalPrompt = amenStudioAI.studioJournalPrompt;

const trueSource = require("./trueSource");
exports.trueSourceSign = trueSource.trueSourceSign;
```

For modules not called by iOS (`242hub`, `seedBible`, `seedJobListings`, `accountDeactivation`, etc.), confirm they are not intended to be deployed and remove or archive them to reduce deploy size and confusion.

### 6. High — Enforce App Check on `openAIFunctions.js` callables

Confirm that **only** the TypeScript versions (`Backend/functions/src/openAIProxy.ts`, `whisperProxy.ts`) are deployed. The JS versions in `functions/openAIFunctions.js` correctly have `enforceAppCheck: false` (they are the legacy versions now superseded). Verify the JS `openAIProxy` and `whisperProxy` are commented out in `index.js` (confirmed at lines 1117–1118). Do not re-enable them.

For `transcribeAudio` and `smartSuggestionsProxy` which remain in the JS codebase (exported at lines 1119–1120), upgrade them to `enforceAppCheck: true` or migrate to TypeScript:

```javascript
exports.transcribeAudio = onCall({ secrets: [openAIKey], enforceAppCheck: true, timeoutSeconds: 120, memory: "512MiB" }, ...);
exports.smartSuggestionsProxy = onCall({ secrets: [openAIKey], enforceAppCheck: true }, ...);
```

### 7. Med — Fix `prayerCount` counter spoofing

Remove client update permission on `prayerCount` in Firestore rules:

```js
// firestore.rules — CURRENT:
allow update: if isSignedIn() && (
  resource.data.userId == request.auth.uid ||
  request.resource.data.diff(resource.data).affectedKeys().hasOnly(['prayerCount'])
);

// FIXED — remove the prayerCount bypass:
allow update: if isSignedIn() && resource.data.userId == request.auth.uid;
```

Move the `prayerCount` increment to the `onPrayerAnswered` or a new `incrementPrayerCount` callable that validates the caller is not the prayer owner.

### 8. Med — Fix duplicate `translateText` export

In `functions/index.js` line 987 and line 1449 both assign `exports.translateText`. The second assignment (healthyImmersiveMedia's version) silently replaces the first (translationFunctions.js version). Rename one:

```javascript
// Line 1449: rename the media-specific variant
exports.translateCaptionsText = healthyImmersiveMedia.translateText; // was: exports.translateText
```

And update any iOS call sites that use it for caption translation specifically to call `translateCaptionsText`.

### 9. Med — Restrict `hashtags` update rule

```js
// firestore.rules — CURRENT:
match /hashtags/{tagId} {
  allow update: if isSignedIn();  // any user can overwrite any hashtag
}

// FIXED:
match /hashtags/{tagId} {
  allow create: if isSignedIn();
  // Updates (postCount increments, etc.) must go through a Cloud Function
  allow update: if false;
}
```

### 10. Low — Add per-IP rate limiting to `anonymousBereanQuery`

The current `maxInstances: 10` cap limits concurrency but not per-caller abuse. Add a lightweight rate limit:

```javascript
exports.anonymousBereanQuery = onCall(
  { maxInstances: 10, enforceAppCheck: false },  // App Check added below
  async (request) => {
    // Add: IP-based rate limit via checkRateLimit helper
    const ip = request.rawRequest?.ip ?? "unknown";
    const limited = await isRateLimited(`anon_berean_${ip}`, "query", 20, 60 * 60 * 1000); // 20/hr
    if (limited) throw new HttpsError("resource-exhausted", "Rate limit exceeded");
    ...
  }
);
```

---

## Gen2 / Gen1 Inventory

| Function | Codebase | Gen | Region | Trigger | Auth Guard | App Check |
|----------|----------|-----|--------|---------|------------|-----------|
| `bereanBibleQA` | JS default | Gen2 | us-central1 | callable | yes | yes |
| `bereanGenericProxy` | TS backend (stub) | Gen2 | us-central1 | callable | yes | no (stub) |
| `openAIProxy` | TS backend | Gen2 | us-central1 | callable | yes | yes |
| `whisperProxy` | TS backend | Gen2 | us-central1 | callable | yes | yes |
| `moderateContent` | JS default | **Gen1** | us-central1 | callable | yes | **no** |
| `composeNotificationPayload` | JS dist-notifications | **Gen1** | us-central1 | callable | **no** | **no** |
| `dispatchPush` | JS dist-notifications | **Gen1** | us-central1 | callable | **no** | **no** |
| `processActivityEvent` | JS dist-notifications | **Gen1** | us-central1 | Firestore trigger | n/a | n/a |
| `transcribeAudio` | JS default | Gen2 | us-central1 | callable | yes | **no** |
| `smartSuggestionsProxy` | JS default | Gen2 | us-central1 | callable | yes | **no** |
| `bereanSermonWeekPlan` | JS default | Gen2 | us-central1 | callable | yes | **no** |
| `heyfeedFunctions (4x)` | JS default | Gen2 | us-central1 | callable | yes | **no** |
| `anonymousBereanQuery` | JS default | Gen2 | us-central1 | callable | none (by design) | **no** |
| `translateText` | JS default | Gen2 | us-central1 | callable | yes | **no** |
| `bootstrapFirstAdmin` | JS default | Gen2 | us-central1 | callable | yes (ADMIN_UIDS) | **no** |
| `bereanChatProxy` | TS backend | Gen2 | (default) | callable | yes | yes |
| `onUserFollow` | JS default | Gen2 | us-central1 | Firestore trigger | n/a | n/a |
| `sendDailyNotificationDigest` | JS default | Gen2 | us-central1 | Scheduled | n/a | n/a |
| `onRealtimeCommentCreate` | JS default | Gen2 | us-central1 | RTDB trigger | n/a | n/a |
| `onMessageSent` | JS default | Gen2 | us-central1 | Firestore trigger | n/a | n/a |

All functions in `Backend/functions/src/` are Gen2 (using `firebase-functions/v2/https`). All functions in `functions/*.js` that use `require("firebase-functions/v2/...")` are Gen2; those using `require("firebase-functions")` directly are Gen1 (`contentModeration.js`, `dist-notifications` pipeline).

---

## Firestore Path Mismatch Notes

- `prayers/{prayerId}` — iOS queries via `db.collection("prayers").where("userId","==",uid)`. The rule allows `list: if isSignedIn()` without an ownership filter, meaning the server does not enforce the query predicate at the rule level. Any query without `.where("userId","==",uid)` will succeed.
- `rateLimits/{uid}/windows/{windowKey}` — rule is `allow read, write: if false` (correct, server-only). JS `rateLimiter.js` uses Admin SDK to write here, which bypasses rules.
- `rateLimitCounters` — used in `postAndCommentFunctions.js` via Admin SDK, but no Firestore rule is present for this collection. Firestore denies all client reads/writes by default (no rule = deny), which is correct since only Admin SDK writes here.

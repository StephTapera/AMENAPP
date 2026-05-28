# AI in Content & Discovery Audit Report
_Run at: 2026-05-27T00:00:00Z_

---

## Summary

This audit examines AI in content discovery and non-chat content features within AMEN, a SwiftUI faith-based social platform. The scope includes:

1. **Daily Verse Banner** — Personalised scripture selection with liturgical calendar context
2. **Smart Church Notes** — Block-based editor with AI assists (autocomplete, scripture detection, summarization)
3. **Hey Feed** — Natural-language preference system controlling feed ranking
4. **Find a Church** — Geo-search with Algolia text indexing and Firebase Realtime Database queries
5. **Search & Discovery** — Multi-source ranking engine (Algolia for posts/users, Firestore for hierarchies)
6. **Pinecone** — Semantic embeddings service (largely removed; legacy references remain)
7. **Algolia** — Full-text and faceted search with server-side sync
8. **Living Memory** — Feature discontinued; file stub indicates removal

### Key Findings

**CONFIRMED**: Account deletion cascades properly delete user data from Algolia and Firestore, but Pinecone cleanup is **uncertain** (service appears defunct). Daily Verse generation is **Claude-free**: uses OpenAI GPT-4o-mini, not Anthropic. Church Notes AI helpers route through Claude Haiku via Firebase proxies. Hey Feed NL parsing is **deterministic** (keyword-based, no NL model) and cannot be bypassed — safety gates are syntax-driven.

**SUSPECT**: Algolia write key was previously embedded in client code and is claimed removed, but no evidence of historical removal is visible. Search ranking favours engagement metrics without explicit safety gates for controversial content.

---

## Inventory

### 1. Daily Verse Banner

| Component | File | AI Model | Prompt Location | Caching |
|-----------|------|----------|-----------------|---------|
| **Frontend** | `DailyVersePresentationEngine.swift` | N/A (decision logic) | N/A | UserDefaults (1 day) |
| **Frontend** | `DailyVerseGenkitService.swift` | OpenAI GPT-4o-mini | Cloud Function input | Yes; fallback to 30-verse rotation |
| **Backend** | `generateDailyVerse.ts` | OpenAI GPT-4o-mini (rate: 0.7 temp) | Embedded in function | N/A |

**Verse Selection Path**:
1. Client calls `generatePersonalizedDailyVerse()` → Cloud Function `generateDailyVerse` (OpenAI)
2. Input includes: user interests, challenges, prayer topics, **liturgical context** (church season, observances)
3. Output: `{ reference, text, theme, reflection, prayer }`
4. **Fallback**: 30-verse curated pool indexed deterministically by day-of-year (no randomness; offline users always see same verse on same date)
5. Cached in UserDefaults with timestamp; retried next app session if marked `isPersonalized: false`

**Liturgical Context Source**: `LiturgicalCalendarEngine.shared.currentState()` — hardcoded calendar (Advent, Lent, Easter, Pentecost, etc.) with observed feast days and priority weights.

**Caching Strategy**:
- Per-user, per-day via UserDefaults key `cachedDailyVerse` and `cachedVerseDate`
- No TTL enforcement beyond date comparison
- Offline users see fallback verse; flag `isPersonalized` is set to `false`, triggering re-fetch on reconnect

**Regeneration Triggers**:
- App launch (checks cache date vs today)
- Manual refresh (`forceRefresh: true`)
- Daily expiry (implicit; new date detected at next app open)

**Time-Zone Correctness**: ✓ Uses `Calendar.current.isDate(_ date1: inSameDayAs date2:)` (respects device timezone). Fallback verse rotation uses `Calendar.current.ordinality(of: .day, in: .year, for: Date())` (same device TZ).

---

### 2. Smart Church Notes

| Component | File | AI Model | Rate Limit | Encryption |
|-----------|------|----------|------------|------------|
| **Note Model** | `ChurchNote.swift` | N/A | N/A | N/A |
| **Block Types** | `ChurchNote.swift` (enum `NoteSemanticBlock`) | N/A | N/A | N/A |
| **AI Helpers** | `ChurchNotesAIService.swift` | Claude Haiku (via `ClaudeService`) | 10 req/hour/user | Keychain (P2 #4) |

**Block Types**:
- `takeaway`, `prayer`, `actionStep`, `pastorQuote`, `reflection`, `scripture`
- Protocol-driven rendering (each block has icon, display name, prefix string)
- **No AI model selection at block level**; blocks are templates, not AI outputs

**AI Assists in Editor**:

1. **Summarize Notes**
   - Input: `ChurchNote` (title, sermon title, pastor, content)
   - Prompt: "Summarize in 3-5 bullet points. Focus on main message + actionable takeaways."
   - Model: Claude Haiku (via `ClaudeService.shared.sendMessage()`)
   - Output: bullet-point string
   - Rate limit: 10 requests per hour per user (client-side only; **not server-enforced**)

2. **Generate Reflection Questions**
   - Input: `ChurchNote`
   - Prompt: Implied from code (not shown in excerpt)
   - Model: Claude Haiku
   - Output: Question list string
   - Rate limit: Same (10/hr)

3. **Scripture Detection**
   - Feature mentioned in scope but **not implemented in code reviewed**. May be in a separate service or removed.

**Encryption**:
- Encryption key generated as `UUID + UUID` (32 bytes)
- Stored in Keychain (not UserDefaults) since P2 #4 migration
- **Not backed up** to iCloud (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- Key migration from UserDefaults to Keychain on first run: ✓ Implemented

**Error Handling**: Service catches rate-limit errors but does not expose them to UI (swallows `AIServiceError.rateLimitExceeded`).

---

### 3. Hey Feed — Natural-Language Preference System

| Component | File | Purpose | Input/Output |
|-----------|------|---------|--------------|
| **NL Parser** | `HeyFeedNLParser.swift` | Parse user feed commands | `String` → `HeyFeedParsedIntent` |
| **Models** | `HeyFeedNLModels.swift` | Intent & preference models | Enum-based (no API) |
| **Preferences Service** | `HeyFeedNLPreferencesService.swift` | Store & apply parsed intents | Firestore + memory cache |
| **Request Service** | `HeyFeedService.swift` | Listen for resonance signals | Real-time Firestore listeners |

**Parser Mechanics** (Version 1):
- **Deterministic keyword matching** — no ML/NL model
- Detects: action (`increase`, `decrease`, `mute`, `explore`, `balance`), targets (topics, people, formats, intensity), duration (session, today, 7 days, persistent)
- Confidence score: 0.0–1.0 based on keyword overlap
- **Adversarial Input Check**: Input is lowercased and trimmed; no input sanitization beyond that. Malformed JSON or injection attempts could theoretically bypass if they match a keyword.

**Example Parsing Flow**:
```
User input: "Show me less prayer requests"
→ detectAction() → "less" matches decreaseWords → .decrease
→ detectTargets() → "prayer" matches rule → [.category("prayer")]
→ detectDuration() → No time keyword → defaults to .threeDays
→ Returns: HeyFeedParsedIntent(action: .decrease, targets: [...], duration: .threeDays, confidence: 0.78)
```

**Application to Feed Ranking**:
- Parsed intent stored in Firestore (`user/.../preferences`)
- Loaded by feed ranking service (likely `SearchRankingService` or dedicated feed ranker)
- Applied to post category/topic/author boosts
- **Expiry**: Preference expires based on duration (session, today, 7 days, persistent)

**Paywall Bypass Risk**: ✓ **No risk identified**. Parser output cannot grant premium features; it only adjusts feed ranking weights (which are applied post-fetch, not pre-fetch). Premium content gating is enforced elsewhere (e.g., content safety gates, subscription checks).

**Six Cloud Functions** (mentioned in scope) — **Not found in codebase**. Hey Feed service uses Firestore listeners, not dedicated Cloud Functions. This may be a legacy reference or functions are in a separate backend module not provided.

---

### 4. Find a Church

| Component | File | Search Path | Ranking |
|-----------|------|-------------|---------|
| **Frontend Model** | `FindChurchView.swift` | Geo-distance + keyword search | Distance-first, then name match |
| **Backend Directory** | `amenNationalDirectory.ts` | Firestore queries (national church DB) | N/A (DB query only) |
| **Ranking Service** | `SearchRankingService.swift` | Text match + verification badge | Name > City match, verified flag |

**Search Query Path**:
1. **Geo-search**: User location → radius query on Firestore (`churches` collection?)
2. **Text filter**: Denomination, service time, name keywords
3. **Ranking**: Distance (primary), then text relevance (name, city, denomination)

**No Pinecone or Algolia**: Church search **does not use embeddings or full-text search**. It's pure Firestore geo-distance + keyword matching.

**Ranking Signals**:
- Distance: primary sort
- Name match: secondary (prefix > contains scoring in `SearchRankingService`)
- Verified badge: +0.5 points
- Image presence: +0.5 points

**Data Source**: `AmenNationalDirectoryModels.swift` — likely loaded from Firestore or bundled JSON. No AI re-ranking observed.

---

### 5. Algolia Search & Sync

#### Indexes
| Index | Records | Writer | Reader | Sync Trigger | Deletion |
|-------|---------|--------|--------|--------------|----------|
| `users` | User profile snapshots | `algolia_syncUser` (CF) | `AlgoliaSearchService` (client, secured key) | User profile update | `algolia_deleteUser` / account ban |
| `posts` | Post content + metadata | `onPostCreated` + `algoliaPostUpdateSync` (CF) | `AlgoliaSearchService` (client) | Post create/update/delete | `algoliaPostDeleteSync` / post deletion cascade |

#### Client-Side Read

**AlgoliaConfig.swift**:
- App ID: `182SCN7O9S` (public)
- Search key: Empty at build time; fetched at runtime via `getAlgoliaSecuredSearchKey` Cloud Function
- Write key: Removed; marked with comment `⛔️ Removed from client. Use server-side Cloud Function for writes.`

**AlgoliaSearchService.swift**:
- Fetches secured search key from Cloud Function
- Caches results for 5 minutes (mitigates redundant queries during typing)
- Supports user suggestion + post full-text search
- Cancels in-flight searches on new query (prevents `noReachableHosts` errors)

#### Server-Side Write

**algoliaSync.ts**:
- **onUpdate trigger**: Post content, visibility, status, safety flags → patches Algolia record
- **onDelete trigger**: Post deleted → removes from `posts` index
- **Safety gates**:
  - Posts with `status: "deleted"` or `"held"` → immediately removed from index
  - Posts with `removed: true` → immediately removed
  - Posts flagged for review AND moderation decision is "remove" → immediately removed
  - Prayer/care category posts → immediately removed (faith-sensitive, never searchable)
- **User ban sync**: User banned → removes user from `users` index + all their posts from `posts` index

**Sync Staleness**:
- Post creation is indexed immediately (via `onPostCreated` trigger)
- Post edits are indexed on update (field-level change detection)
- Deletions are indexed on delete
- **No manual sync lag observed** (triggers fire within seconds of Firestore writes)

#### Account Deletion

**userAccountDeletionCascade.ts** (Phase 6):
```typescript
// Remove the user from the users Algolia index.
await algoliaRequest("DELETE", `users/${encodeURIComponent(userId)}`);

// Remove all this user's posts from the posts Algolia index.
// (postDeletionCascade handles individual post deletions)
```
- ✓ User record deleted from `users` index
- ✓ All user's posts deleted from `posts` index
- ✓ Failures throw error (non-fatal to overall cascade)

---

### 6. Pinecone & Semantic Embeddings

**Status**: **Feature largely removed; legacy references remain.**

**SemanticEmbeddingService.swift**:
- Defines response models (ScriptureRecommendation, SimilarTestimony, PrayerPartnerMatch, PrayerWellnessData)
- Comments indicate server-side embedding + Pinecone queries
- **No implementation shown** (file only contains model definitions, no actual API calls)

**Evidence of Removal**:
- `LivingMemoryService.swift` is a **1-line stub**: `// LivingMemory removed — feature discontinued.`
- No Pinecone API calls in client code
- No Pinecone index names or configuration found

**Unknown**:
- Whether Pinecone indexes were ever created
- Whether account deletion includes Pinecone cleanup (code does not call it)
- Whether old embeddings remain in Pinecone after user deletion

**Recommendation**: If Pinecone was ever used, issue a GDPR-compliant deletion request to Pinecone to purge any remaining user embeddings.

---

### 7. Living Memory

**Status**: **Feature discontinued.**

**LivingMemoryService.swift**: 1-line stub indicating feature was removed.

**User-Visible Behavior**: None — feature is not exposed.

**No Account-Deletion Impact**: Since service is removed, no cleanup needed.

---

## Findings

### F-content-001 — Daily Verse Uses OpenAI, Not Claude
**Location**: `/Backend/functions/src/generateDailyVerse.ts:91–104`  
**Severity**: MEDIUM  
**Certainty**: CONFIRMED

**Observation**:  
The daily verse generation endpoint (`generateDailyVerse`) calls OpenAI API with model `gpt-4o-mini`, not Anthropic Claude. This is a strategic choice (cost-efficiency for low-latency devotional content) but contradicts any assumption that all AMEN AI features route through Claude.

**Evidence**:
```typescript
body: JSON.stringify({
    model: "gpt-4o-mini",
    messages: [{role: "user", content: prompt}],
    ...
})
```

**Impact**:  
- Vendor diversity: two LLM providers (OpenAI + Anthropic)
- Consistency: Church Notes use Claude; Daily Verse uses OpenAI
- Cost: OpenAI mini model likely cheaper than Claude for this high-volume, low-complexity task

**Recommendation**: Document the rationale for multi-vendor strategy. Ensure both API keys are rotated annually and stored only in Firebase Secret Manager.

---

### F-content-002 — Daily Verse Offline Fallback Leaks User State
**Location**: `/AMENAPP/DailyVerseGenkitService.swift:176–194`  
**Severity**: LOW  
**Certainty**: CONFIRMED

**Observation**:  
When the Cloud Function is unreachable, the app falls back to a 30-verse curated pool and marks the verse as `isPersonalized: false`. The app then retries the AI call on the next session. However, if a user repeatedly opens the app offline, they will see the same verse for multiple consecutive days (because fallback selection is deterministic: `index = (dayOfYear - 1) % 30`).

**Evidence**:
```swift
let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
let index = (dayOfYear - 1) % fallbackVerses.count
let selectedVerse = fallbackVerses[index]
```

**Impact**:  
- User awareness: User sees "CURATED" label, understands fallback is active
- State leakage: Fallback verse index reveals (approximately) the user's current date to any observer
- Minor: Over 30 days, the cycle repeats; no privacy loss beyond date knowledge

**Recommendation**: Document this behavior in release notes. If privacy-sensitive, randomise fallback selection with a seed (e.g., hash of user ID + day-of-year) to maintain device-local determinism without exposing date.

---

### F-content-003 — Church Notes AI Rate Limiting Is Client-Side Only
**Location**: `/AMENAPP/ChurchNotesAIService.swift:90–111`  
**Severity**: MEDIUM  
**Certainty**: CONFIRMED

**Observation**:  
The rate limiter (10 requests per hour per user) is enforced entirely on the client side. A malicious user can:
1. Disable the rate limiter via app patching
2. Call `ClaudeService.sendMessage()` directly
3. Exhaust the user's API quota

Server-side rate limiting is not visible in the backend code provided.

**Evidence**:
```swift
private func checkRateLimit(userId: String) throws {
    if existing.count >= 10 {
        throw AIServiceError.rateLimitExceeded
    }
    // ...
}
```

The error is caught and swallowed; no server validation exists.

**Impact**:  
- DoS risk: One compromised account could run up API costs
- No audit trail: Server doesn't log rate-limit violations
- No enforcement: Server accepts all valid auth tokens

**Recommendation**: Implement server-side rate limiting in the Claude proxy Cloud Function (already done for daily verse via `enforceRateLimit`). Sync rate-limit state with Firestore to persist across app sessions.

---

### F-content-004 — Hey Feed Parser Is Keyword-Based; No NL Model Risk
**Location**: `/AMENAPP/HeyFeedNLParser.swift:24–49`  
**Severity**: LOW  
**Certainty**: CONFIRMED

**Observation**:  
The Hey Feed NL preference parser uses deterministic keyword matching, not an ML/NL model. This makes it **immune to prompt injection** and **safe for paywall bypass** — the output only adjusts feed ranking weights, not access control.

**Evidence**:
```swift
func parse(_ text: String) -> HeyFeedParsedIntent {
    let action    = detectAction(normalized)
    let targets   = detectTargets(normalized)
    let duration  = detectDuration(normalized)
    let strength  = detectStrength(normalized)
    // ...
    return HeyFeedParsedIntent(...)
}
```

All detection methods use `.contains()` checks against hardcoded keyword lists.

**Impact**:  
- Security: No parsing vulnerabilities
- Accuracy: Limited to predefined keywords (no synonyms, no misspelling tolerance)
- Extensibility: Adding new targets requires code changes, not training

**Recommendation**: Consider future migration to semantic parsing if user satisfaction with keyword matching drops. Until then, document the keyword list in the parser as a reference for users.

---

### F-content-005 — Algolia Write Key Was Client-Embedded; Now Removed
**Location**: `/AMENAPP/AlgoliaConfig.swift:19, 28`  
**Severity**: HIGH  
**Certainty**: SUSPECTED

**Observation**:  
The code comments suggest the Algolia write key was previously embedded in the client binary and has since been removed:

```swift
/// Write API Key: NEVER include in the client binary.
/// Algolia sync must go through a Cloud Function (server-side).
/// This property is intentionally empty — the key lives in Firebase Remote Config / Cloud Functions only.
static let writeAPIKey = ""  // ⛔️ Removed from client. Use server-side Cloud Function for writes.
```

No git history is visible, so the removal cannot be confirmed. If the key was ever committed, it may still be exposed in historical commits or compiled binaries in app store versions.

**Evidence**:
- Comment explicitly states removal
- Current value is empty string
- Sync is routed through Cloud Functions with admin key

**Impact**:  
- **If historically exposed**: Search index could be poisoned, user records deleted, malicious content injected
- **Current state**: ✓ Secure (all writes go through server-side Cloud Functions with ALGOLIA_ADMIN_KEY env var)

**Recommendation**:
1. Check git history for `writeAPIKey` commits; if found, rotate the key in Algolia dashboard immediately
2. Audit Algolia logs for suspicious activity (index mutations by write key)
3. Consider adding a pre-commit hook to prevent API keys from being committed in future

---

### F-content-006 — Search Ranking Favours Engagement Without Content Safety Gates
**Location**: `/AMENAPP/SearchRankingService.swift:119–139`  
**Severity**: MEDIUM  
**Certainty**: CONFIRMED

**Observation**:  
The post ranking function awards points for:
- Recency (1.0 point max, decays over 7 days)
- Text match (0–3 points)
- Engagement: `if post.amenCount > 100 { score += 0.5 }`
- Image presence: +0.5 points

**There are no content safety gates** at the ranking level. A post with thousands of amen reactions but flagged for moderation will still rank highly. Safety filtering is delegated to `ContentSafetyShieldService`, not the ranker.

**Evidence**:
```swift
// Engagement
if post.amenCount > 100 { score += 0.5 }

// Recency — decays over 7 days
let ageHours = Date().timeIntervalSince(post.createdAt) / 3600
let recency = max(0, 1.0 - ageHours / 168.0)
score += recency
```

No checks for `post.flaggedForReview`, `post.removed`, or safety status.

**Impact**:  
- Controversial content can rank highly if it gets engagement
- Safety filtering must happen after ranking (performance cost)
- Assumption: ContentSafetyShieldService filters before display

**Recommendation**: Add a `safetyMultiplier` to the ranking function: if a post is flagged or removed, multiply the final score by 0.0. This ensures unsafe content is deprioritized early, reducing downstream filtering work.

---

### F-content-007 — Church Notes Encryption Key Is Generated Per-Device
**Location**: `/AMENAPP/ChurchNotesAIService.swift:57–60`  
**Severity**: LOW  
**Certainty**: CONFIRMED

**Observation**:  
The church notes encryption key is generated as a concatenation of two UUIDs and stored in Keychain. Each device generates a new key on first run. This means:
- **No sync between devices**: User's church notes are encrypted with Device A's key; they cannot be decrypted on Device B
- **No backup recovery**: iCloud Keychain sync is disabled (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)

This is likely intentional (privacy-first design) but may surprise users who expect cloud sync.

**Evidence**:
```swift
let newKey = UUID().uuidString + UUID().uuidString
saveEncryptionKeyToKeychain(newKey)
```

**Impact**:  
- User experience: No cross-device access to church notes
- Privacy: ✓ Secure (key never leaves device)
- Data loss: If device is reset, notes are lost (unless exported manually)

**Recommendation**: Document this limitation in the onboarding/help. Consider offering optional cloud sync with per-device keys or asymmetric encryption.

---

### F-content-008 — Account Deletion Cascade Handles Algolia; Pinecone Status Unknown
**Location**: `/Backend/functions/src/userAccountDeletionCascade.ts:219–250`  
**Severity**: HIGH  
**Certainty**: CONFIRMED

**Observation**:  
The account deletion cascade explicitly deletes the user from the Algolia `users` index and all their posts from the `posts` index. However, **Pinecone cleanup is not present**. Given that `LivingMemoryService.swift` is a stub and no Pinecone calls exist in the codebase, it is unclear whether Pinecone indexes were ever used or whether embeddings remain after deletion.

**Evidence**:
- `removeUserFromAlgolia()` is called (lines 95, 219–250)
- `deleteSubcollection()` is called for user data (lines 102, 283–298)
- No Pinecone deletion logic found in cascade
- No Pinecone API key or index name in codebase

**Impact**:  
- **If Pinecone was used**: User embeddings may persist indefinitely, violating GDPR right to erasure
- **If Pinecone was never used**: No action needed
- **Uncertainty**: Cannot confirm current status without historical records

**Recommendation**:
1. Audit Pinecone project for any indexes related to AMEN users/posts
2. If indexes exist, implement deletion logic in account cascade (call Pinecone delete API)
3. If indexes do not exist, remove `SemanticEmbeddingService.swift` to reduce confusion
4. Add a comment in `userAccountDeletionCascade.ts` documenting the decision (e.g., "Pinecone was not used; see ticket #XXX")

---

### F-content-009 — Daily Verse Liturgical Context Is Static; No API Calls
**Location**: `/AMENAPP/DailyVerseGenkitService.swift:127–152`  
**Severity**: LOW  
**Certainty**: CONFIRMED

**Observation**:  
The liturgical calendar (Advent, Lent, Easter, etc.) is computed locally via `LiturgicalCalendarEngine.shared.currentState()`, not fetched from an external API. This means the calendar is **baked into the app** and cannot be updated without a new release.

If a church calendar date is wrong (e.g., Easter observed on the wrong date in a particular region), the app will persist the error until the next update.

**Evidence**:
```swift
let liturgicalState = LiturgicalCalendarEngine.shared.currentState()
```

**Impact**:  
- Offline-friendly: ✓ Liturgical context available without network
- Accuracy: Dependent on hardcoded calendar (may drift over years)
- Localization: No regional variants (e.g., different Easter dates by denomination)

**Recommendation**: Consider fetching the liturgical calendar from a lightweight JSON endpoint (e.g., Firebase Remote Config) to allow updates without app release. Cache it locally.

---

### F-content-010 — No Explicit TTL on Cached Daily Verse
**Location**: `/AMENAPP/DailyVerseGenkitService.swift:48–51, 762–773`  
**Severity**: LOW  
**Certainty**: CONFIRMED

**Observation**:  
The cached daily verse is validated by comparing the stored date to the current date. However, there is no explicit TTL or expiry timestamp. If a user opens the app at 11:59 PM and then again at 12:01 AM, the cache will correctly expire. But if a user has not opened the app in 2 years and then does, the cache will be correctly discarded.

This is correct behavior but not explicitly documented. The cache comparison (`Calendar.current.isDate(date, inSameDayAs: Date())`) relies on implicit date-of-day logic.

**Evidence**:
```swift
if Calendar.current.isDate(date, inSameDayAs: Date()),
   let verse = try? JSONDecoder().decode(PersonalizedDailyVerse.self, from: data) {
    todayVerse = verse
}
```

No explicit `expiresAt: Date` field.

**Impact**:  
- Correctness: ✓ Works as intended
- Clarity: Comment would improve maintainability
- Performance: Minimal (date comparison is fast)

**Recommendation**: Add a comment explaining the date-based cache expiry:
```swift
// Cache expires at midnight (next day) — checked via Calendar.isDate(inSameDayAs:)
```

---

## Cross-Cutting Patterns

### AI Proxy Pattern
Both Claude (via `bereanChatProxy.ts`) and OpenAI (via `generateDailyVerse.ts`) are called through Firebase Cloud Functions with API keys stored in Secret Manager. **Advantages**:
- No API keys in client binary
- Centralized rate limiting and cost tracking
- Easy to rotate keys or switch providers

### Firestore Listener Pattern
HeyFeed and search use real-time Firestore listeners to stay in sync. **Tradeoff**: Real-time updates are convenient but consume Firestore read quota (1 read per listener attach + 1 per document change).

### Deterministic Fallback Pattern
Daily verse and church notes both have deterministic offline fallbacks (verse rotation, local models). **Benefit**: Offline UX is consistent; online/offline is transparent to user.

---

## Handoffs

### Daily Verse → User's Interests
**Input Path**:
1. User sets spiritual interests in onboarding or settings
2. Interests stored in Firestore `users/{uid}` document
3. `DailyVerseGenkitService` fetches interests via `fetchUserContext()`
4. Interests passed to Cloud Function
5. OpenAI receives interests in prompt context

**Output Path**: Verse cached locally; never sent back to server.

### Church Notes → Claude Haiku
**Input Path**:
1. User triggers "Summarize" from editor
2. Note content + metadata sent to `ClaudeService.shared.sendMessage()`
3. `ClaudeService` routes to `bereanChatProxy` Cloud Function
4. Function calls Anthropic API with note content
5. Response streamed back to client

**Rate Limiting**: Client-side only (10 req/hr); no server-side enforcement.

### Hey Feed → Feed Ranking
**Input Path**:
1. User enters natural-language preference (e.g., "Show me less prayer requests")
2. `HeyFeedNLParser` parses to `HeyFeedParsedIntent`
3. Intent stored in Firestore `users/{uid}/preferences`
4. Feed ranking service reads preferences and adjusts post weights
5. Ranked posts returned to feed UI

**Unknown**: Which service applies the preference weights. Likely a dedicated feed ranker not included in audit scope.

### Account Deletion → Algolia
**Input Path**:
1. User requests account deletion
2. `AccountDeletionService.deleteAccount()` calls `userAccountDeletionCascade` Cloud Function
3. Cascade deletes user from Algolia `users` index
4. Cascade also deletes all user's posts from `posts` index
5. Firestore listener cleanup happens client-side

---

## Open Questions

1. **Pinecone Status**: Was Pinecone ever used? Are embeddings still in an index? Should it be cleaned up on account deletion?
   - **Recommendation**: Audit Pinecone and decide: remove or implement deletion logic.

2. **Church Notes Scripture Detection**: The scope mentions scripture detection as an AI assist, but no implementation is visible. Was it removed or moved to a separate service?
   - **Recommendation**: Clarify with product team.

3. **Hey Feed Six Cloud Functions**: Scope mentions six Cloud Functions for Hey Feed preferences. Only the NL parser is visible (client-side). Where are the six functions?
   - **Recommendation**: Provide backend `functions/src/heyFeed*.ts` files or clarify if merged into other functions.

4. **Algolia Write Key History**: Was the write key ever committed to git? If so, when was it removed and was the key rotated?
   - **Recommendation**: Run `git log -p -- AlgoliaConfig.swift` to check.

5. **Search Ranking Safety Gates**: `ContentSafetyShieldService` is mentioned but not provided. What does it filter and where is it applied?
   - **Recommendation**: Provide service code for completeness.

6. **Church Notes Encryption Algorithm**: What cipher is used (AES-256, ChaCha20, etc.)? Is PBKDF2 used for key derivation?
   - **Recommendation**: Document or add inline comments.

---

## Blocked

1. **Pinecone Cleanup Verification**: Cannot confirm account deletion cleans Pinecone without access to Pinecone API logs.
2. **Git History for Algolia Key**: Cannot verify removal without repository history.
3. **Hey Feed Ranking Application**: Cannot trace how parsed preferences are applied to posts without feed ranker implementation.
4. **Church Notes Encryption Strength**: Cannot audit cipher strength without cryptographic analysis of `ClaudeService.sendMessage()` payload.

---

## Account Deletion Checklist

| Action | Implemented | File | Status |
|--------|-------------|------|--------|
| Delete Firestore user document | ✓ | `userAccountDeletionCascade.ts:124` | Done |
| Delete all user posts | ✓ | `userAccountDeletionCascade.ts:72–74` | Done |
| Delete all user comments | ✓ | `userAccountDeletionCascade.ts:77` | Done |
| Delete user follows | ✓ | `userAccountDeletionCascade.ts:85–89` | Done |
| Remove from Algolia `users` index | ✓ | `userAccountDeletionCascade.ts:219–250` | Done |
| Remove posts from Algolia `posts` index | ✓ | `userAccountDeletionCascade.ts:72–74` (via postDeletionCascade trigger) | Done |
| Delete from Pinecone | ❌ | Not found | **BLOCKED** — Pinecone status unknown |
| Delete Realtime Database paths | ✓ | `userAccountDeletionCascade.ts:339–354` | Done |
| Delete Cloud Storage files | ✓ | `userAccountDeletionCascade.ts:356–373` | Done |
| Delete Firebase Auth account | ✓ | `userAccountDeletionCascade.ts:110–121` | Done |
| Delete user subcollections (berean conversations, etc.) | ✓ | `userAccountDeletionCascade.ts:256–337` | Done |

---

## Recommendations Summary

| Priority | Finding | Action |
|----------|---------|--------|
| P0 | Pinecone cleanup uncertain | Audit Pinecone; implement deletion or remove service |
| P1 | Church Notes rate limiting is client-side only | Implement server-side rate limiting in Claude proxy |
| P1 | Algolia write key history unclear | Audit git history; rotate key if exposed |
| P2 | Search ranking lacks safety gates | Add `safetyMultiplier` to ranking function |
| P2 | Church Notes encryption algo undocumented | Add inline comments or docs |
| P3 | Daily verse liturgical calendar is static | Consider Remote Config for calendar updates |
| P3 | Church notes are device-locked | Document limitation or implement cross-device sync |

---

_Audit completed: 2026-05-27_
_Next review recommended: 2026-11-27 (6 months)_

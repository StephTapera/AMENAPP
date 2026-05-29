# Data Model & Persistence Audit

_Audited 2026-05-28 · Branch: audit/2026-05-28_

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| `BereanChatView.swift:333` | **Blocker** | Schema Mismatch | `buildAllBereanHistory` orders by `"lastUpdated"` but `persistExchange` writes `"lastUpdated"` while `BereanConversationService` uses `"updatedAt"`. The field name is inconsistent: BereanChatViewModel writes `lastUpdated`, BereanConversationService writes `updatedAt`, and Cloud Function (premiumBereanCallables.ts:200) writes `updatedAt` + `lastMessageAt`. Cross-session history query will silently return unsorted (or empty) results when field is absent. |
| `AMENAPP/BereanChatView.swift:203,749` vs `Backend/functions/src/berean/repositories/ConversationRepository.ts:13` | **Blocker** | Orphaned Writes / Schema Divergence | iOS client writes conversations to `users/{uid}/bereanConversations/{id}` (subcollection). Cloud Function `ConversationRepository` reads/writes to a top-level `berean_conversations/{id}` collection with no `userId` subcollection path. `premiumBereanCallables.ts:192` writes to the iOS path. Three different schemas exist in parallel — none is authoritative. Conversations persisted server-side via `ConversationRepository` are never read by the iOS client. |
| `Backend/functions/src/berean/controllers/premiumBereanCallables.ts:203` | **Blocker** | Orphaned Writes | `bereanAsk` writes user messages to `users/{uid}/bereanMessages/{id}` (flat subcollection off the user doc, NOT inside the conversation). `BereanChatView` reads from `users/{uid}/bereanConversations/{id}/messages`. Messages written by the Cloud Function are never read by the app. |
| `AMENAPP/PostsManager.swift:356` | **High** | Schema Mismatch | `Post.PostVisibility.everyone` has `rawValue = "Everyone"` (capital E). Firestore queries throughout the app filter with `whereField("visibility", isEqualTo: "everyone")` (lowercase). `FirebasePostService._performCreatePost` correctly normalises to lowercase before writing, but any code path that encodes a `Post` struct directly (e.g. Firestore batch writes, unit tests, server-side Cloud Functions reading the `Post` type) will write `"Everyone"`. Legacy documents in Firestore may have `"Everyone"`, causing them to be invisible to all feed queries. |
| `AMENAPP/MediaMetadataDraftModels.swift:437–459` | **High** | Missing Fields (Not Persisted) | `mediaMetaDocument(for:)` does not persist `perMediaCaption`, `altText`, `captionModeration`, `scriptureRefs`, or `reflectionPrompt` — the five per-media caption fields added in System 24. These fields are authored in `CreatePostView` and stored on the in-memory `PostMediaItem`, but the `MediaMetadataPersistenceService` mirror document omits them entirely. They are silently lost after app restart. |
| `AMENAPP/HeyFeedService.swift:171–173` | **High** | Missing Firestore Index | `attachActiveRequestsListener` queries `heyfeed_requests` with `whereField("isActive", isEqualTo: true)` + `.order(by: "resonanceScore", descending: true)`. No composite index exists for `(isActive, resonanceScore)` in either `firestore.indexes.json`. This query will fail at runtime in production with a "requires an index" error and the entire HeyFeed feature will be blank. |
| `AMENAPP/HeyFeedService.swift:228–230` | **High** | Missing Firestore Index | `attachPastoralSignalsListener` queries `pastoral_care_signals` with `whereField("isAcknowledged", isEqualTo: false)` + `.order(by: "urgencyScore", descending: true)`. No index for this collection exists in `firestore.indexes.json`. Runtime failure for pastoral care signals. |
| `AMENAPP/HeyFeedService.swift:198–202` | **High** | Missing Firestore Index | `attachMyResonancesListener` queries `heyfeed_resonance` with `whereField("userId", …)` + `.order(by: "createdAt", descending: true)`. No composite index for this collection exists in either index file. Runtime failure. |
| `AMENAPP/BereanMemoryService.swift:45–52` | **High** | Missing Firestore Index | `startObserving` queries `users/{uid}/bereanMemory` with `whereField("isUserVisible", isEqualTo: true)` + `.order(by: "lastReferencedAt", descending: true)`. No composite index for this subcollection exists in `firestore.indexes.json`. Silent failure (listener never fires in production). |
| `AMENAPP/SemanticSearchService.swift:49–53` | **High** | Missing Composite Index | Queries `posts` with `whereField("createdAt", isGreaterThan: …)` + `whereField("visibility", isEqualTo: "everyone")` + `.order(by: "createdAt", …)`. Firestore requires an index for inequality filter + equality filter + orderBy. The existing `(visibility, createdAt)` index does NOT include an inequality range filter — the actual query uses both range and equality, which is a different index shape. Will fail in production. |
| `AMENAPP/ChurchNotesFeatureModels.swift` (entire file) | **High** | Orphaned Structs — Never Persisted | `AIInsights`, `ScriptureDNAResult`, `CrossRef`, `OriginalWord`, `DuetBlock`, `LiveChurch`, `GrowthDataPoint`, `DuetCommunityNote` are all `Codable` but are never written to or read from Firestore anywhere in the codebase. They exist only as in-memory types. If the Church Notes intelligence features depend on these being persisted, the persistence layer is entirely missing. |
| `AMENAPP/PostsManager.swift:606` (comment) | **High** | Orphaned Write (mediaItems) | `Post.mediaItems`, `witnessMedia`, `smartAttachment`, `hasSmartAttachment`, `attachmentCount`, `primaryAttachmentId`, and `publicationVisibility` are explicitly excluded from Codable decode/encode as "client-only fields". However, `MediaMetadataPersistenceService` writes to `posts/{id}/mediaMeta/{mediaItemId}` subcollection but the parent `Post` document in the feed query never returns a `mediaItems` array. Feed consumers calling `FirebasePostService` receive `post.mediaItems = nil` unconditionally, regardless of whether media was uploaded. Rich media posts will always render without media items unless the caller separately queries `mediaMeta`. No code path joins these back on feed load. |
| `AMENAPP/FirebasePostService.swift:862–869` | **Med** | Denormalization Drift | `authorName`, `authorUsername`, `authorInitials`, and `authorProfileImageURL` are written at post creation time from `UserDefaults` cache. If the user later changes their display name or profile photo, all existing posts retain the stale denormalized values. No batch update job or Cloud Function trigger exists to propagate user profile changes to authored posts. Feed will show outdated author display names. |
| `AMENAPP/BereanChatView.swift:281–316` | **Med** | Schema Fragmentation | Legacy schema stores messages as an embedded `messages: [[String: Any]]` array in the conversation document. New schema stores messages in a `messages` subcollection. Both read paths exist in `loadExistingSession` and `buildAllBereanHistory`. Legacy documents use `"timestamp"` key; new messages use `"createdAt"`. A document decoded via the legacy path silently uses `.now` as a fallback if `timestamp` is absent. Mixed-schema sessions in Firestore will yield scrambled message ordering. |
| `AMENAPP/BereanConversationService.swift:25–55` | **Med** | Missing CodingKeys | `BereanConversation` and `BereanConversationMessage` use synthesized `Codable` (no custom `CodingKeys`). The iOS property names are camelCase but `BereanConversationService` writes Firestore documents using manual dictionary literals with slightly different key names (e.g. the service writes `"memoryScopeName"` matching the property, but `BereanChatView` writes `"mode"` for the same concept as `"modeName"` in the struct). Firestore auto-decode via `try doc.data(as: BereanConversation.self)` would silently zero-out mismatched fields. |
| `AMENAPP/HeyFeedService.swift:299` | **Med** | Idempotency Gap | `recordResonance` uses `merge: false` on `resonanceRef.setData(…)`. A race between two rapid taps (double-tap) will silently overwrite the previous resonance doc without error, but `resonanceCount` on the request doc is incremented with no duplicate guard. If the first write completes and the second replaces it, the counter will be +1 higher than the actual resonance count. Should use a transaction to increment only if the document did not previously exist. |
| `AMENAPP/FirebasePostService.swift:611–615` | **Med** | Idempotency TTL Too Short | The idempotency key for post creation is derived from `Int(Date().timeIntervalSince1970)` (1-second precision). If a user taps "Post", the app is backgrounded during the background-priority Task, relaunched, and the user taps again more than 1 second later, a duplicate post will be created. The server-side `idempotencyKey` field provides a second guard, but there is no Cloud Function that checks for existing documents with the same key before writing. |
| `AMENAPP/ChurchNotesChecklistService.swift:127–131` | **Med** | Pagination Missing | Reads `users/{uid}/churchNotes/{noteId}/checklists` with no `.limit()` call. A church note with hundreds of checklist items will load them all at once. |
| `AMENAPP/BereanRAGService.swift:175–262` | **Med** | Orphaned Collection | Writes to `users/{uid}/bereanSessions/{id}` but `BereanConversationService` and `BereanChatView` never read from `bereanSessions`. This appears to be a legacy or duplicate persistence path for Berean sessions. The RAG service creates session documents that are never surfaced to the user. |
| `AMENAPP/BereanContextMemoryService.swift:76–80` | **Med** | Dual Berean Memory Paths | Writes to both `users/{uid}/bereanMemory` (same as `BereanMemoryService`) AND `users/{uid}/bereanContext/profile`. `BereanMemoryService` and `BereanContextMemoryService` are parallel services writing to overlapping paths without coordination. Risk of stale reads if one service's writes overwrite the other's. |
| `AMENAPP/AMENAPP/BereanModelPickerComponents.swift:90` vs `AMENAPP/BereanModeEngine.swift:205` | **Med** | Schema Drift — bereanSettings | `BereanModelPickerComponents` and `BereanModeEngine` both write to `users/{uid}/bereanSettings/preferences` but with different field sets. No shared schema document exists. Whichever service writes last wins; the other service's fields may be clobbered if either uses `setData` without `merge: true`. |
| `AMENAPP/PostsManager.swift:487–509` | **Low** | Missing Fields in CodingKeys | `Post.CodingKeys` does not include `mediaItems`, `witnessMedia`, `smartAttachment`, `hasSmartAttachment`, `attachmentCount`, `primaryAttachmentId`, `publicationVisibility`, `aiUsage`, `trueSource`, `feedContext`, `authorIsPrivate`, `authorIsVerified`, `authorVerificationType`, `dynamicReplyPreviewCandidates`, `flaggedForReview`, `removed`, `lowTrustAuthor`, `isPinned`, `pinnedAt`, `pinnedExpiresAt`, `poll`, `threadId`, `threadIndex`, `isThreadHead`, `threadPostCount`, `hasSensitiveContent`, `sensitiveContentReason`. These are silently set to nil/default on decode. Fields written server-side (e.g. `removed`, `flaggedForReview`) will never be reflected in the feed unless explicitly mapped. |
| `AMENAPP/HeyFeedService.swift:300` | **Low** | Firestore Path vs Collection | `HeyFeedResonance` is stored at `heyfeed_resonance/{uid}_{postId}` (document-per-user-post) but the listener queries the collection with `whereField("userId", …)`. Using the composite document ID is efficient for point reads but makes it impossible to query "all resonances for a given post" by postId without a full collection scan or a separate index. |
| `AMENAPP/SermonRelevanceEngine.swift:162` | **Low** | Cross-User bereanConversations Read | `SermonRelevanceEngine` reads from `bereanConversations` using a query that does not scope to the current user. If Firestore security rules are not tight, this could read other users' conversations. Requires verification of security rules. |
| `firestore.indexes.json` (root) | **Low** | Duplicate Index Definitions | Several indexes appear in both `AMENAPP/firestore.indexes.json` and the root `firestore.indexes.json` (e.g. `notifications`, `follows`, `conversations`, `savedPosts`, `prayerRequests`, `churchNotes`). During `firebase deploy --only firestore:indexes`, duplicates are harmless but increase deploy time and create confusion about which file is authoritative. Only one `firestore.indexes.json` should be deployed. |

---

## Not Fully Wired

### Berean Conversation Persistence — Three Schemas in Conflict

| Path | Written By | Read By |
|------|-----------|---------|
| `users/{uid}/bereanConversations/{id}` | `BereanChatView.persistExchange`, `premiumBereanCallables.ts` | `BereanChatView.loadExistingSession`, `BereanAIAssistantView` |
| `users/{uid}/bereanConversations/{id}/messages` (subcollection) | `BereanChatView.persistExchange` | `BereanChatView.loadExistingSession` (new path), `BereanConversationService.messagesRef` |
| `users/{uid}/bereanMessages/{id}` (flat, off user doc) | `premiumBereanCallables.ts:203` | **Nobody** |
| `berean_conversations/{id}` (top-level) | `ConversationRepository.ts` | **Nobody on iOS** |
| `berean_messages/{id}` (top-level) | `ConversationRepository.ts`, `generateStructuredResponse.ts` | **Nobody on iOS** |

The `ConversationRepository` top-level path and `users/{uid}/bereanMessages` flat path are orphaned writes — no iOS read path ever accesses them.

### PostMediaItem Per-Media Caption Fields — Never Persisted

Fields on `PostMediaItem` that are built in the `CreatePostView` composer and exist in-memory but have NO write path to Firestore:
- `perMediaCaption` (System 24 user-authored caption per frame)
- `altText` (accessibility)
- `captionModeration` (server-derived, but read path on iOS expects it from Firestore)
- `scriptureRefs` (per-frame scripture links)
- `reflectionPrompt` (per-frame faith reflection)

`MediaMetadataPersistenceService.mediaMetaDocument(for:)` writes the `mediaMeta` subcollection but omits all five fields.

### `Post.mediaItems` — Written to Subcollection, Never Joined on Feed Load

`MediaMetadataPersistenceService.persistMetadataMirror` writes rich media metadata to `posts/{id}/mediaMeta/{mediaId}` subcollections. However, `FirebasePostService.createPost` and all snapshot listeners decode `Post` with `mediaItems = nil` (explicitly set in `init(from decoder:)`). No code queries `mediaMeta` during feed load or profile load. The subcollection data is written but never read back.

### ChurchNotesFeatureModels — Codable Structs with No Persistence

`AIInsights`, `ScriptureDNAResult`, `CrossRef`, `OriginalWord`, `DuetBlock`, `LiveChurch`, `GrowthDataPoint`, `DuetCommunityNote` are declared `Codable` in `ChurchNotesFeatureModels.swift` but have no associated Firestore read or write path in the codebase. These represent Church Notes "smart features" (AI insights, scripture DNA, community duet) that are modeled but not connected to any backend.

### Living Memory / Embeddings

`LivingMemoryCard.swift` contains only the comment `// LivingMemory removed — feature discontinued.` No embedding write path exists. The `firestore.indexes.json` (root) defines a vector index on `items.embedding` (dimension 768), but no iOS code or Cloud Function writes embeddings to an `items` collection. The index is orphaned.

### HeyFeed Missing Indexes

The `heyfeed_requests`, `heyfeed_resonance`, and `pastoral_care_signals` collections have no entries in either `firestore.indexes.json`. All three real-time listeners attached at app start will fail immediately in production.

---

## Fix Recommendations

### Fix 1 (Blocker) — Unify Berean Conversation Schema

Choose one canonical path: `users/{uid}/bereanConversations/{id}` (iOS-native). Update `ConversationRepository.ts` to write to this subcollection path. Remove the orphaned writes to `users/{uid}/bereanMessages` and top-level `berean_conversations`/`berean_messages`. Standardise the timestamp field to `updatedAt` (already used by `BereanConversationService`); remove `lastUpdated` from `BereanChatView.persistExchange` and query (line 333 — change `order(by: "lastUpdated"…)` to `order(by: "updatedAt"…)`).

### Fix 2 (Blocker) — Add Missing Firestore Indexes

Add to `firestore.indexes.json`:

```json
{ "collectionGroup": "heyfeed_requests", "queryScope": "COLLECTION",
  "fields": [{"fieldPath":"isActive","order":"ASCENDING"},{"fieldPath":"resonanceScore","order":"DESCENDING"}] },
{ "collectionGroup": "heyfeed_resonance", "queryScope": "COLLECTION",
  "fields": [{"fieldPath":"userId","order":"ASCENDING"},{"fieldPath":"createdAt","order":"DESCENDING"}] },
{ "collectionGroup": "pastoral_care_signals", "queryScope": "COLLECTION",
  "fields": [{"fieldPath":"isAcknowledged","order":"ASCENDING"},{"fieldPath":"urgencyScore","order":"DESCENDING"}] },
{ "collectionGroup": "bereanMemory", "queryScope": "COLLECTION",
  "fields": [{"fieldPath":"isUserVisible","order":"ASCENDING"},{"fieldPath":"lastReferencedAt","order":"DESCENDING"}] }
```

### Fix 3 (High) — Persist Per-Media Caption Fields

In `MediaMetadataPersistenceService.mediaMetaDocument(for:)`, add the five missing fields:

```swift
"perMediaCaption": item.perMediaCaption as Any,
"altText": item.altText as Any,
"scriptureRefs": item.scriptureRefs,
"reflectionPrompt": item.reflectionPrompt as Any,
// captionModeration is server-written — omit from client writes
```

### Fix 4 (High) — Join mediaItems on Feed Load

In `FirebasePostService`, after decoding a post from a snapshot, query `posts/{id}/mediaMeta` and populate `post.mediaItems`. Alternatively, denormalise a `mediaItemsSummary` array onto the top-level post document at write time so a single document read is sufficient.

### Fix 5 (High) — Fix Post.PostVisibility Raw Values

Change `Post.PostVisibility.everyone.rawValue` to `"everyone"` (lowercase), and likewise `followers` → `"followers"`, `community` → `"community"`. Update the `toPost()` mapping in `FirestorePost` to remove the redundant switch (since rawValues now match Firestore strings). Run a one-time Firestore migration script to rewrite legacy documents with `visibility = "Everyone"` to `"everyone"`.

### Fix 6 (Med) — Standardise bereanSettings Write

Create a shared schema for `bereanSettings/preferences`. Both `BereanModelPickerComponents` and `BereanModeEngine` should use `setData(…, merge: true)` and operate on non-overlapping field namespaces. Document the full field set in a `BereanPreferencesSchema.swift` constants file.

### Fix 7 (Med) — Resonance Idempotency via Transaction

Replace `resonanceRef.setData(resonanceData, merge: false)` + `requestRef.updateData(increment)` with a Firestore transaction that reads the resonance doc first, increments only if it did not previously exist, and no-ops on duplicate taps.

### Fix 8 (Low) — Consolidate firestore.indexes.json

Pick one authoritative `firestore.indexes.json` (the root file is more complete). Remove the `AMENAPP/firestore.indexes.json` or make it a symlink. Update `firebase.json` to point to the canonical file.

### Fix 9 (Low) — Remove Orphaned bereanSessions Path

`BereanRAGService` writes to `users/{uid}/bereanSessions`. If this data is not needed, remove the writes. If it is a planned future feature, add a Firestore read path or mark it with a `// TODO: wire read path` comment to prevent confusion.

---

## Acceptance Checklist

- [ ] `BereanChatView` `order(by: "lastUpdated"…)` changed to `order(by: "updatedAt"…)`
- [ ] `premiumBereanCallables.ts` messages written inside `bereanConversations/{id}/messages` subcollection, not `bereanMessages`
- [ ] `ConversationRepository.ts` reads/writes `users/{uid}/bereanConversations/{id}` (not top-level `berean_conversations`)
- [ ] Four new composite indexes deployed and verified in Firebase Console
- [ ] `perMediaCaption`, `altText`, `scriptureRefs`, `reflectionPrompt` visible in `mediaMeta` subcollection after post creation
- [ ] Feed `post.mediaItems` populated after load (not always `nil`)
- [ ] `Post.PostVisibility.everyone.rawValue == "everyone"` (lowercase); legacy migration script run
- [ ] HeyFeed active requests listener returns results in production (no index error in Crashlytics/logs)
- [ ] `heyfeed_resonance` resonance count consistent after rapid double-tap test
- [ ] Single authoritative `firestore.indexes.json` deployed

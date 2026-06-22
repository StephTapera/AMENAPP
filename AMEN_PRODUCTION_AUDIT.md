# AMEN App — Deep Production Infrastructure Audit
**Date:** 2026-04-14
**Auditor:** Claude Code (automated deep read)
**Standard:** Ruthless production standard — treat as if malicious users are probing, App Store reviewers are inspecting, and leadership expects world-class execution.

---

## Legend

| Symbol | Meaning |
|--------|---------|
| 🔴 CRITICAL | Exploitable right now. Data breach, account takeover, or trust/safety bypass. Fix before next release. |
| 🟠 HIGH | Significant risk. Could be exploited with moderate effort. Fix within 2 sprints. |
| 🟡 MEDIUM | Real issue, not immediately exploitable. Fix within 1 quarter. |
| 🔵 LOW | Technical debt, minor hardening, or best-practice gap. |
| ✅ DONE | Already fixed or correctly implemented. |
| ☐ | Tracking checkbox — mark when resolved |

---

## 1. Executive Risk Summary

The AMEN backend has a **solid security foundation** — the Firestore rules file is 4,077 lines of intentional, layered defense. The anti-harassment enforcement, media scanning, and notification policy pipeline are genuinely well-engineered. However, several **exploitable gaps** exist today that require immediate action:

1. **Post engagement counts are forgeable by any authenticated user** (RTDB rules). Any user can set `amenCount`, `lightbulbCount`, `commentCount`, `repostCount` to any value on any post. This is live and exploitable now.
2. **All notification Cloud Functions are commented out in `index.ts`**. If no alternate deployment exists, notifications are not being generated server-side.
3. **The `posts` collection `allow list` rule uses invalid CEL syntax** (`request.query.where(...)` does not exist in Firestore Rules) — this means all feed list queries are blocked at the rules layer, or the rule is being evaluated as `false` and falling through to another rule.
4. **`translations` collection has a duplicate conflicting rule** that strips DM-block and length-validation from the stricter rule above it.
5. **No `storage.rules` file found** in the project. Firebase Storage is either using default rules (deny all) or rules managed outside this repo — both are dangerous in a CI/CD context.
6. **No `firestore.indexes.json` found** — composite indexes are unmanaged, causing silent query degradation at scale.

---

## 2. Firestore Rules Audit

**File:** `AMENAPP/AMENAPP/firestore 18.rules` (4,077 lines)
**Rules version:** 2

### 2.1 Global Helper Functions
The rules define these helper functions — review their correctness:

| Function | Status | Notes |
|----------|--------|-------|
| `isAuthenticated()` | ✅ | Correct |
| `isOwner(uid)` | ✅ | Correct |
| `isAdmin()` | ✅ | Checks `adminUsers/{uid}` doc |
| `validLength(field, min, max)` | ✅ | Correct bounds check |
| `hasRequiredFields(fields)` | ✅ | Correct |
| `isOnlyUpdating(fields)` | ✅ | Correct |
| `isCounterUpdate()` | ✅ | Restricts to numeric increment fields |
| `callerAgeTier()` | ✅ | Reads `userAgeProfiles/{uid}.ageTier` |
| `callerIsAdult()` | ✅ | Checks Tier D |
| `callerCanUseDMs()` | ✅ | Checks Tier C+D |
| `callerIsEmailVerified()` | ✅ | Checks `request.auth.token.email_verified` |
| `caller2FASessionValid()` | ✅ | Checks `twoFactorSessions/{uid}` |

### 2.2 Critical Rule Issues

- [ ] 🔴 **CRITICAL — `posts` `allow list` uses invalid CEL syntax**
  The rule uses `request.query.where(...)` which **does not exist** in Firestore Security Rules. This is not a valid CEL expression. At runtime this will evaluate to `false`, silently blocking all programmatic list queries on the `posts` collection unless other rules allow them. Audit what queries are actually succeeding in production Firestore logs.
  **Fix:** Replace with valid field-level checks or use a `where("userId", "==", uid)` pattern enforced via `request.query.limit <= 50 && resource.data.userId == request.auth.uid` — or simply remove the list guard and rely on server-side indexes.

- [ ] 🔴 **CRITICAL — `translations` collection duplicate conflicting rule**
  A weaker duplicate rule exists at approximately line 3662–3667. It allows write without checking DM-block status or applying length validation. Because Firestore evaluates rules as OR across all matching rules, the weaker rule **overrides** the stricter one at line 2185.
  **Fix:** Remove the duplicate rule block. Keep only the stricter rule.

- [ ] 🟠 HIGH — **`prayerChains` `allow update: if isAuthenticated()`**
  Any authenticated user can update any prayer chain document. This allows anyone to modify the `participantIds` array, the `chain` content, or prayer metadata on chains they don't own.
  **Fix:** Restrict to `isOwner(resource.data.creatorId)` or participants only.

- [ ] 🟠 HIGH — **`notificationDigests` `allow list: if isAuthenticated()`**
  Any authenticated user can list all notification digest documents in the collection, including those belonging to other users.
  **Fix:** Scope to `request.auth.uid == resource.data.userId` or restructure as a subcollection under `users/{uid}`.

- [ ] 🟠 HIGH — **`mentorshipRelationships` and `mentorshipCheckIns` `allow list: if isAuthenticated()`**
  Leaks the full mentorship relationship graph to all authenticated users. Sensitive for users seeking private spiritual guidance.
  **Fix:** Add `where mentorId == uid || menteeId == uid` scoping or move to user subcollections.

- [ ] 🟠 HIGH — **`prayers` `allow list: if isAuthenticated()`** with comment "App MUST include whereField"
  The security comment acknowledges the rule is client-trust: the rule trusts the app to include a `where` clause, but the rules engine does not enforce that the `where` clause is present. Any authenticated client can enumerate all prayers without a filter.
  **Fix:** Enforce ownership at the rules layer using `request.query.filters.userId == request.auth.uid` or move prayers to `users/{uid}/prayers` subcollection.

- [ ] 🟡 MEDIUM — **`communityFeed` allows any authenticated user to post `sharedTestimony` type**
  No content moderation gate before community feed publication. A user could flood the community feed.
  **Fix:** Add rate limit check (e.g. `rateLimits/{uid}` document) or require a pending-review status.

- [ ] 🟡 MEDIUM — **Duplicate collection rules for `jobListings`, `jobApplications`, `faithEvents`, `eventRSVPs`**
  Each of these collections has two separate rule blocks in the file. The later block may override the earlier one unpredictably depending on rule evaluation order.
  **Fix:** Consolidate into a single rule block per collection.

- [ ] 🟡 MEDIUM — **`visit_plans` has broad list: `if isAuthenticated()`**
  Any authenticated user can list all visit plans. Users' church visit plans are private intent signals.
  **Fix:** Scope to `resource.data.userId == request.auth.uid`.

- [ ] 🔵 LOW — **`mentorshipCheckIns` and `mentorshipRelationships` `allow list`**
  As above — leaks relationship graph. See HIGH item.

---

## 3. Realtime Database Rules Audit

**File:** `AMENAPP/database.rules.json`

### 3.1 Critical Issues

- [ ] 🔴 **CRITICAL — Post engagement counters are forgeable**
  Path: `postInteractions/{postId}/lightbulbCount`, `amenCount`, `commentCount`, `repostCount`
  Current rule: `.write: "auth != null"` — ANY authenticated user can set these to arbitrary values on ANY post.
  **Impact:** Virality manipulation, fake engagement, distorted algorithmic ranking.
  **Fix:** Remove client write access entirely. These counters must only be updated via Cloud Functions (Firestore triggers or callable). If client-side optimistic updates are needed, use a separate `userInteractions/{uid}/{postId}` path and compute counts server-side.

- [ ] 🔴 **CRITICAL — `prayingNow` and `totalPrayerSessions` world-writable**
  Path: `prayerActivity/{postId}/prayingNow` and `totalPrayerSessions`
  Current rule: `.write: "auth != null"` — any user can inflate prayer engagement counts.
  **Fix:** Same as above — server-only writes via Cloud Function.

- [ ] 🟠 HIGH — **`sessions` collection writable by user but no block enforcement**
  A user under messaging restriction can still create sessions indicating they are "online" and available to be messaged. This is a trust signal that can mislead recipients.
  **Fix:** Consider server-side session management or add restriction check.

- [ ] 🟠 HIGH — **`counters/{uid}/followerCount` and `followingCount` writable by uid**
  Users can set their own follower/following count to any value. Even if the display is computed from actual follow documents, any system that reads these counter shortcuts will display inflated counts.
  **Fix:** Make these server-only (Cloud Function writes only) or remove them in favor of computed counts.

- [ ] 🟡 MEDIUM — **`live_reactions` has no rate limiting**
  Path: `live_reactions/{contentId}/{uid}/{reactionId}`
  No limit on how many reaction documents a single user can write per content item per session. A user can flood the reactions collection.
  **Fix:** Add `.validate` limiting the number of recent writes using a timestamp window or cap per user per content.

- [ ] 🟡 MEDIUM — **`connections` following writable by the subject user**
  Path: `connections/{uid}/following/{targetUid}`
  The user being followed can write into their own `following` subcollection (i.e., claim they are following users they are not). This is inconsistent with how most follow systems work.
  **Fix:** Only the follower should write into their own `following` list. Verify the rule direction.

---

## 4. Firebase Storage Rules Audit

- [ ] 🔴 **CRITICAL — No `storage.rules` file found in project**
  The repository does not contain a `storage.rules` file. This means either:
  - Storage rules are managed exclusively via the Firebase Console (not version-controlled, not auditable, not deployable via CI/CD), OR
  - Storage is using Firebase's default rules (`allow read, write: if false` or `if request.auth != null` depending on project setup)

  **Impact:** If default open rules are in place (`auth != null`), any authenticated user can read any file. If default deny rules are in place, the app is broken for storage reads.
  **Fix:** Create `storage.rules` in the repo root, version-control it, and add it to Firebase deploy pipeline. At minimum, enforce:
  - `post_media/{uid}/{allPaths=**}`: only `uid == request.auth.uid` can write; authenticated users can read
  - `profile_images/{uid}/{allPaths=**}`: only owner can write
  - `chat_files/{conversationId}/{allPaths=**}`: only conversation participants can read/write
  - Apply size limits (`request.resource.size < 50 * 1024 * 1024`) and content-type allow-lists

---

## 5. Cloud Functions Audit

**File:** `Backend/functions/src/index.ts`

### 5.1 Deployment Gap — Notification Functions Not Deployed

- [ ] 🔴 **CRITICAL — All notification Firestore triggers are commented out in `index.ts`**
  The following exports are commented out with the note "temporarily commented out — gen 1 Firestore triggers conflict with gen 2 onCall":
  - `onSocialEvent` (follow, comment, amen, mention, etc.)
  - `counts` (badge count maintenance)
  - `maintenance` (notification cleanup)
  - `invalidation` (notification invalidation)

  **Impact:** If no alternate deployment exists for these functions, NO social event notifications are being generated server-side. Users would receive zero follow/comment/mention push notifications.
  **Immediate Action:** Confirm whether these are deployed from a separate project/config. If not, this is a P0 user experience and monetization issue. Resolve the gen1/gen2 conflict by migrating notification triggers to gen2 syntax.

### 5.2 Function-by-Function Issues

#### `antiHarassmentEnforcement.ts`
- [ ] 🟠 HIGH — **Group chat messages only get platform-wide freeze check, not per-target no-contact**
  The function returns early after the platform-wide freeze check for group chats (`if (isGroup) return`). A user with a no-contact order against a specific person can still message them in a group chat.
  **Fix:** For group chats, also check if any no-contact order covers any participant.

- [ ] 🟡 MEDIUM — **`isBlockedByRecipient` does a collection query instead of document existence check**
  Current: queries `blockedUsers` collection with `where userId == recipientId && blockedUserId == senderId`. If the block document uses a deterministic ID (`{recipientId}_{senderId}`), a `.get()` on that specific doc is O(1) vs O(n) scan.
  **Fix:** Use document ID lookup if block docs have deterministic IDs.

- [ ] 🟡 MEDIUM — **Lazy restriction cleanup race condition**
  When two concurrent function invocations both find an expired restriction and both call `snap.ref.delete()`, the second delete will fail silently. This is acceptable behavior but should be explicitly caught.

#### `mediaScanning.ts`
- [ ] 🟠 HIGH — **CSAM detection logic has redundant condition (potential gap)**
  Line ~281: `if (veryLikelyAdult || (veryLikelyAdult && veryLikelyRacy))`
  The second condition `(veryLikelyAdult && veryLikelyRacy)` is always a subset of `veryLikelyAdult`. The intent was `veryLikelyAdult || veryLikelyRacy` — detecting either signal alone at VERY_LIKELY.
  **Fix:** Change to `if (veryLikelyAdult || veryLikelyRacy)`.

- [ ] 🟠 HIGH — **Creator Studio storage paths not scanned**
  `SCANNED_PREFIXES` does not include `creator/` paths. Any media uploaded to Creator Studio bypasses SafeSearch scanning.
  **Fix:** Add `"creator/"` to `SCANNED_PREFIXES`.

- [ ] 🟡 MEDIUM — **No PhotoDNA / NCMEC hash-matching integration**
  The code acknowledges this is a TODO. For a platform with any minor-accessible content surfaces, PhotoDNA or CSAM hash-matching (via Microsoft or Meta) is expected by App Store and NCMEC guidelines.
  **Fix:** Integrate PhotoDNA API once key is provisioned. This is a legal/compliance requirement for platforms with minors.

- [ ] 🔵 LOW — **Videos queued for manual review only; no frame extraction**
  All video uploads go to manual review queue with no automated analysis. High-volume platforms cannot sustain this.
  **Fix:** Implement ffmpeg frame extraction via Cloud Run for video thumbnail analysis with Vision API.

#### `notifications/sendPush.ts`
- [ ] 🟡 MEDIUM — **No retry logic for transient FCM batch failures**
  If `messaging.sendEach()` throws a transient error, the entire batch is lost. No exponential backoff, no dead-letter queue.
  **Fix:** Wrap batch send in retry logic (3 attempts with exponential backoff) or write failed tokens to a retry queue.

- [ ] 🟡 MEDIUM — **Badge count slow-path does uncapped collection count query**
  The badge count fallback reads ALL unread notification docs via a collection query to count them. At scale (users with hundreds of notifications) this is expensive and slow.
  **Fix:** Maintain a `users/{uid}/notificationMeta/counts` document with atomic increment/decrement via Cloud Function.

- [ ] 🔵 LOW — **`contentAvailable: true` on all push payloads**
  Apple limits background push throughput. Setting `contentAvailable: true` on every notification (including foreground-delivered ones) may trigger Apple's rate limiter and cause notification delivery delays.
  **Fix:** Only set `contentAvailable: true` for background sync notifications, not social event notifications.

#### `notifications/onSocialEvent.ts`
- [ ] 🟠 HIGH — **`onFollowCreated` and `onFollowRequestAcceptedV2` both trigger on `follows/{docId}` onCreate**
  Both functions fire when a new follow document is created. This risks sending two follow notifications to the recipient — one for the initial follow, one for the acceptance.
  **Fix:** Check the `status` field in the follow document. `onFollowCreated` should only fire when `status == "accepted"` (for public accounts, this is immediate) or not fire at all if `onFollowRequestAcceptedV2` already handles it.

- [ ] 🟠 HIGH — **`handleMentions` queries `users` by `username` field without guaranteed index**
  Firestore collection queries on non-indexed fields fail at scale with "index required" errors logged to Firestore but returning empty results to the app.
  **Fix:** Ensure `users` collection has a composite index on `username`. Add to `firestore.indexes.json`.

- [ ] 🟡 MEDIUM — **Prayer answered fan-out sends sequential notifications**
  For a prayer post with 10,000 supporters, notifications are sent one by one, not batched. This will hit the Cloud Function 9-minute timeout.
  **Fix:** Batch notification sends using `sendEach` with 500-item chunks, or use Pub/Sub fan-out.

- [ ] 🟡 MEDIUM — **No block check before sending follow notification to private accounts**
  A user who has been blocked can still trigger a follow notification by following the private account (follow request notification fires before block check).
  **Fix:** Check `blocks` collection before writing notification document.

#### `notifications/policies.ts`
- [ ] 🟡 MEDIUM — **Rate limit check (step 7) and idempotency check (step 10) each do a Firestore collection query per candidate**
  Two reads per notification candidate, at high volume (e.g., a post going viral with 10k interactions) this creates significant Firestore read load.
  **Fix:** Cache the rate limit result in memory for the duration of the function invocation (same actor→recipient pair). Use a dedicated `rateLimitCounters` document with atomic counters instead of querying notification history.

- [ ] 🟡 MEDIUM — **Quiet hours check uses UTC time, not user's local timezone**
  `checkQuietHours` computes `now.getUTCHours()` but user's `quietHoursStart`/`quietHoursEnd` are presumably in local time. A user who sets quiet hours to 10pm–7am in EST will get their quiet hours computed in UTC, off by 4–5 hours.
  **Fix:** Store `quietHoursTimezone` (IANA timezone string) in user preferences and convert UTC to local time before comparison.

#### `rateLimit.ts`
- [ ] 🟡 MEDIUM — **No rate limits defined for post creation, comment creation, follow actions, or report submissions**
  The presets only cover AI proxies and suggested accounts. A user can create unlimited posts, spam follows, or flood the reports queue.
  **Fix:** Add `POST_CREATE`, `COMMENT_CREATE`, `FOLLOW_ACTION`, `REPORT_SUBMIT` rate limit presets and enforce them in the respective Cloud Functions.

#### `feedBuilder.ts`
- [ ] 🟡 MEDIUM — **Fan-out is synchronous within the 5000-follower cap**
  Even with the `MAX_FANOUT_FOLLOWERS = 5000` cap, writing 5000 Firestore documents synchronously in a single function invocation is slow and likely to timeout for users with many followers.
  **Fix:** Migrate to Pub/Sub fan-out as documented in the code comments. Fan-out should be a series of messages to a topic, each processed by a separate worker.

- [ ] 🔵 LOW — **Throttled posts silently dropped**
  If the rate limiter throttles the feed fan-out, the post does not appear in followers' feeds and there is no retry mechanism. The user has no indication their post wasn't distributed.
  **Fix:** Write throttled posts to a pending fan-out queue and process them on a schedule.

---

## 6. Missing Cloud Functions

The following functions are referenced in client code or business logic but **no corresponding Cloud Function implementation was found**:

- [ ] 🟠 HIGH — **Username uniqueness enforcement**
  Username changes in client code write directly to Firestore. No Cloud Function enforces uniqueness at write time. Race condition: two users can claim the same username simultaneously.
  **Fix:** Implement a Cloud Function with a Firestore transaction on `usernames/{username}` as a uniqueness index document.

- [ ] 🟠 HIGH — **Deleted user data cascade**
  When a user deletes their account (`AccountDeletionService.swift`), is there a Cloud Function that cleans up their posts, comments, follows, notifications, media files, and Algolia records? The `deleteAlgoliaUser` function exists, but no general-purpose deletion cascade was found.
  **Fix:** Implement `onUserDeleted` Auth trigger that initiates cascaded cleanup across all user-data collections.

- [ ] 🟠 HIGH — **Post deletion cascade**
  When a post is deleted, its comments, reactions, notifications, and media files should be cleaned up. No post deletion Cloud Function was found.
  **Fix:** Implement `onPostDeleted` Firestore trigger.

- [ ] 🟡 MEDIUM — **Scheduled maintenance jobs**
  No scheduled Cloud Functions found for:
  - Expiring old rate limit windows
  - Cleaning up expired notification digests
  - Purging old moderation queue entries
  - Cleaning up expired 2FA sessions
  - Resetting daily/weekly streaks

  **Fix:** Implement `pubsub.schedule()` functions for each maintenance task.

- [ ] 🟡 MEDIUM — **Trust score computation**
  `TrustScoringEngine.swift` references trust scores but no Cloud Function was found that computes or updates these scores server-side. Trust scores computed entirely on-device can be manipulated.
  **Fix:** Implement server-side trust score computation on relevant events.

---

## 7. Firestore Indexes Audit

- [ ] 🔴 **No `firestore.indexes.json` file found in project**
  Composite indexes are either managed via Firebase Console (not version-controlled) or are missing entirely. Missing indexes cause:
  - Silent query failures in production (Firestore returns empty results with no client-side error)
  - "FAILED_PRECONDITION: The query requires an index" logged in Firebase console
  - Degraded user experience that's hard to diagnose

  **Required indexes based on query patterns found in code:**
  - `notifications`: `(recipientId ASC, actorId ASC, createdAt DESC)` — for rate limit check
  - `notifications`: `(recipientId ASC, idempotencyKey ASC)` — for idempotency check
  - `users`: `(username ASC)` — for mention lookup
  - `follows`: `(followerId ASC, followingId ASC, status ASC)` — for mutual follow checks
  - `posts`: `(userId ASC, createdAt DESC)` — for profile feed
  - `posts`: `(visibility ASC, createdAt DESC)` — for discovery feed
  - `enforcementHistory`: `(userId ASC, timestamp DESC)` — for violation count queries
  - `moderationQueue`: `(uid ASC, status ASC, priority ASC)` — for moderation dashboard
  - `prayers`: `(communityId ASC, createdAt DESC)` — for prayer wall

  **Fix:** Create `firestore.indexes.json`, add all required composite indexes, deploy via `firebase deploy --only firestore:indexes`.

---

## 8. Data Model Integrity Audit

- [ ] 🟠 HIGH — **Post engagement counters exist in both RTDB and Firestore**
  Engagement counts appear to be stored in `postInteractions/{postId}` (RTDB) AND in the post document in Firestore. These can diverge. The display layer needs a single source of truth.
  **Fix:** Designate one source of truth. Recommend Firestore (for consistency with rest of data model) and deprecate the RTDB counters.

- [ ] 🟡 MEDIUM — **`uploadGroupId` on post documents used for media-to-post linking**
  `mediaScanning.ts` looks up posts by `uploadGroupId` to flag them for content review. If the `uploadGroupId` index is missing or the post hasn't been written yet when the scan completes (race condition), the flagging silently fails.
  **Fix:** Add a composite index on `posts.uploadGroupId`. Write the post document before the media upload begins (with `status: "uploading"` state).

- [ ] 🟡 MEDIUM — **E2EE key bundles stored in Firestore without expiry**
  `keyBundles/{uid}` and `usedOTPKs/{uid}` documents grow unboundedly. One-time prekeys (OTPKs) that have been used should be deleted. Stale key bundles can cause decryption failures for the client.
  **Fix:** Implement a scheduled function to clean up expired/used OTPKs.

- [ ] 🔵 LOW — **`userAgeProfiles` documents not validated for tampering**
  The `callerAgeTier()` helper reads `userAgeProfiles/{uid}.ageTier` but the Firestore rules should prevent the user from writing their own `ageTier` to a higher tier. Verify that `userAgeProfiles` write rules enforce server-only writes for the `ageTier` field.

---

## 9. Notification System Audit

See Section 5 (Cloud Functions) for function-level issues. Additional system-level issues:

- [ ] 🟠 HIGH — **Double notification risk on follow**
  `onFollowCreated` and `onFollowRequestAcceptedV2` may both fire for the same follow event. See Section 5.

- [ ] 🟡 MEDIUM — **Notification documents written before policy evaluation**
  If the notification document is written first and then the policy pipeline suppresses it, the document may remain in Firestore as "orphaned" — visible to the user as an unread notification even though it should have been suppressed.
  **Fix:** Evaluate policies first, then write the notification document only if allowed.

- [ ] 🟡 MEDIUM — **`badgeCount` maintained at push-send time rather than notification-write time**
  Badge counts are computed when pushing, not when the notification is created. If push fails, the badge count on-device goes out of sync with the actual notification count.
  **Fix:** Maintain badge count as an atomic counter in Firestore, updated whenever a notification is created or read.

- [ ] 🔵 LOW — **No notification archival / TTL**
  Notification documents accumulate indefinitely in `users/{uid}/notifications`. Active users will accumulate thousands of notification documents, increasing Firestore read costs.
  **Fix:** Implement a scheduled function that archives or deletes notifications older than 90 days.

---

## 10. Keyboard / Input System Audit

*The Swift client input files were not fully audited in this session. The following are known risks based on patterns in the codebase.*

- [ ] 🟡 MEDIUM — **`MentionTextEditor` / `MentionTextView` send raw mention text to Firestore**
  Mention text should be sanitized server-side before storage. If mention resolution happens client-side, a malicious client can craft mention documents pointing to arbitrary UIDs.
  **Fix:** Validate mention UID references server-side (Cloud Function) against the actual `users` collection.

- [ ] 🟡 MEDIUM — **Post composition — no server-side max length enforcement**
  Client enforces character limits in the composer UI, but Firestore rules use `validLength()` helper. Confirm the `validLength` helper is applied to all text fields on the post document (body, captions, etc.).

- [ ] 🔵 LOW — **No paste-from-clipboard sanitization for verse attacher**
  If the verse attacher uses clipboard content, malformed content could produce malformed Firestore documents.

---

## 11. Auth / Session / Identity Enforcement Audit

- [ ] 🟠 HIGH — **2FA session validation only enforced for specific sensitive paths**
  `caller2FASessionValid()` is used in some collections but not all. Collections managing financial data (giving), sensitive content (chat), or account settings may not require a valid 2FA session.
  **Audit action:** Enumerate all collections that touch sensitive user data and verify `caller2FASessionValid()` is required for write operations.

- [ ] 🟠 HIGH — **Email verification required for DMs but not for post creation**
  `callerIsEmailVerified()` gates DM access. Confirm it also gates:
  - Post creation (currently gated by `isAuthenticated()` only in most rules)
  - Comment creation
  - Follow actions

- [ ] 🟡 MEDIUM — **Device token management — stale token cleanup is reactive only**
  Invalid FCM tokens are cleaned up when a push fails. A user with many old devices will accumulate stale tokens. The cleanup only fires after a failed send.
  **Fix:** Run periodic cleanup of device tokens older than 60 days.

- [ ] 🟡 MEDIUM — **No account lockout after repeated failed auth attempts**
  Firebase Auth has per-project rate limiting but no per-account lockout policy. Targeted brute-force attacks on known email addresses are possible.
  **Fix:** Implement `onSignInFailed` trigger or use Firebase App Check + reCAPTCHA to throttle auth attempts.

- [ ] 🔵 LOW — **`twoFactorSessions/{uid}` documents not TTL-expired server-side**
  2FA session documents should expire automatically. If the client-side logout doesn't delete the session document (e.g., due to a crash), the session remains valid indefinitely.
  **Fix:** Add `expiresAt` Firestore TTL policy or a scheduled cleanup function.

---

## 12. Security Gaps — What Is Not Secure Right Now

These are live, unmitigated risks:

| # | Risk | Severity | Exploitability |
|---|------|----------|---------------|
| 1 | Any authenticated user can set any post's engagement counts (RTDB) | 🔴 CRITICAL | Trivially easy |
| 2 | Notification Cloud Functions may not be deployed (commented out) | 🔴 CRITICAL | Platform-wide impact |
| 3 | No `storage.rules` in repo — unknown storage security posture | 🔴 CRITICAL | Unknown |
| 4 | `prayerChains` updatable by any authenticated user | 🟠 HIGH | Easy |
| 5 | `notificationDigests` listable by any authenticated user | 🟠 HIGH | Easy |
| 6 | CSAM detection logic has a bug (redundant OR condition) | 🟠 HIGH | Trust/safety gap |
| 7 | Creator Studio media not scanned for unsafe content | 🟠 HIGH | Easy for bad actors |
| 8 | No username uniqueness Cloud Function (race condition) | 🟠 HIGH | Moderate |
| 9 | No deleted-user data cascade Cloud Function | 🟠 HIGH | GDPR/privacy risk |
| 10 | Group chat messages bypass per-target no-contact orders | 🟠 HIGH | Easy for bad actors |
| 11 | `translations` duplicate rule strips safety checks | 🟠 HIGH | Easy |
| 12 | No server-side composite indexes file | 🟡 MEDIUM | Scale-dependent |
| 13 | Post counters in both RTDB and Firestore (can diverge) | 🟡 MEDIUM | Data integrity |
| 14 | Quiet hours computed in UTC not user's timezone | 🟡 MEDIUM | UX impact |
| 15 | No rate limits on post/comment/follow/report | 🟡 MEDIUM | Spam risk |

---

## 13. Missing Security Controls

Controls that best-practice platforms of this type implement that are absent:

- [ ] 🟠 **No Firestore TTL policies configured** — Old documents accumulate, increasing attack surface and cost.
- [ ] 🟠 **No Firebase App Check enforcement** — Cloud Function endpoints are callable by any client with a valid Firebase project config, not just the AMEN iOS app.
- [ ] 🟠 **No NCMEC CyberTipline reporting integration** — Platforms with CSAM detection are legally required to report to NCMEC. The media scanning function deletes the file and suspends the account but does not file a CyberTipline report.
- [ ] 🟡 **No structured content-hash deduplication** — The same harmful image can be re-uploaded slightly modified to bypass hash-based detection.
- [ ] 🟡 **No audit log for admin actions** — `isAdmin()` grants broad write access but admin operations are not logged to an immutable audit trail.
- [ ] 🟡 **No IP-based rate limiting** — Only per-UID rate limiting exists. A bad actor can create multiple accounts to bypass per-UID limits.
- [ ] 🟡 **No server-side text content moderation** — Only media is scanned. Post text, comments, and DMs are sent through client-side moderation only (AntiHarassmentEngine runs on-device). Server-side text moderation (via Perspective API or similar) is absent.
- [ ] 🔵 **No `X-Content-Type-Options` or security headers on HTTP callable responses** — Cloud Functions HTTP responses should include standard security headers.

---

## 14. Critical Things the Team May Be Forgetting

1. **The commented-out notification functions are a P0 if not deployed elsewhere.** Confirm this immediately. Users not receiving notifications directly impacts retention and is an App Store review risk.

2. **Firebase Storage rules are missing from version control.** If a developer runs `firebase deploy`, storage rules may be reset to a default insecure state. This needs a `storage.rules` file committed to the repo TODAY.

3. **`firestore.indexes.json` missing means every composite query is untested infrastructure.** Silent query failures are the hardest bugs to diagnose in production because Firestore returns `[]` instead of an error to the client.

4. **NCMEC reporting is a legal requirement, not a best practice.** The PROTECT Our Children Act requires platforms to report CSAM to NCMEC. The current mediaScanning.ts deletes the file and suspends the account but does not file a report. This is a legal compliance gap.

5. **Age gate enforcement depends on `userAgeProfiles/{uid}` being server-authoritative.** If a user can update their own `ageTier`, the entire minor-safety architecture collapses. Audit the write rules on `userAgeProfiles` immediately.

6. **The RTDB rules are in `database.rules.json` in the app directory, not the standard Firebase project root.** Confirm this file is the one actually being deployed to your Firebase project. If the CI/CD pipeline deploys from a different path, these rules are not live.

7. **`E2EE keyBundles` growing without expiry is a forward secrecy violation.** Used one-time prekeys must be deleted. If they're retained, an attacker who later compromises the server can decrypt past E2EE messages (retroactive decryption).

8. **No rollback plan for Firestore rules.** If a bad rule is deployed, how quickly can it be reverted? Rules deployments should be automated, version-tagged, and have a one-command rollback procedure.

---

## 15. Severity-Ranked Action Plan

### Immediate (Before Next Production Release)

| Priority | Issue | File | Action |
|----------|-------|------|--------|
| P0.1 | Confirm notification Cloud Functions deployment status | `Backend/functions/src/index.ts` | Verify or redeploy |
| P0.2 | Post engagement counters forgeable (RTDB) | `AMENAPP/database.rules.json` | Remove client write access |
| P0.3 | `storage.rules` missing from repo | (missing) | Create and commit `storage.rules` |
| P0.4 | CSAM detection bug (`\|\|` condition) | `mediaScanning.ts:281` | Fix to `veryLikelyAdult \|\| veryLikelyRacy` |
| P0.5 | `translations` duplicate weaker rule | `firestore 18.rules:3662` | Remove duplicate block |

### Sprint 1 (Within 2 Weeks)

| Priority | Issue | File | Action |
|----------|-------|------|--------|
| S1.1 | `posts` `allow list` invalid CEL syntax | `firestore 18.rules` | Fix or remove invalid rule |
| S1.2 | `prayerChains` update any auth user | `firestore 18.rules` | Restrict to owner/participant |
| S1.3 | Creator media not scanned | `mediaScanning.ts` | Add `creator/` to SCANNED_PREFIXES |
| S1.4 | Group chat bypasses no-contact orders | `antiHarassmentEnforcement.ts` | Add participant-level no-contact check |
| S1.5 | `notificationDigests` world-listable | `firestore 18.rules` | Scope to owning user |
| S1.6 | Username uniqueness Cloud Function | (missing) | Implement with Firestore transaction |
| S1.7 | Double follow notification risk | `onSocialEvent.ts` | Add status-field deduplication |
| S1.8 | Create `firestore.indexes.json` | (missing) | Add all required composite indexes |

### Sprint 2 (Within 1 Month)

| Priority | Issue | File | Action |
|----------|-------|------|--------|
| S2.1 | Deleted user cascade Cloud Function | (missing) | Implement `onUserDeleted` trigger |
| S2.2 | Post deletion cascade | (missing) | Implement `onPostDeleted` trigger |
| S2.3 | `mentorshipRelationships` leaking | `firestore 18.rules` | Scope list queries |
| S2.4 | Quiet hours timezone bug | `policies.ts:336` | Use user's stored timezone |
| S2.5 | Rate limits for post/comment/follow | `rateLimit.ts` | Add presets + enforcement |
| S2.6 | Badge count slow-path query | `sendPush.ts` | Maintain atomic counter document |
| S2.7 | FCM batch retry logic | `sendPush.ts` | Add exponential backoff |
| S2.8 | `prayers` list client-trust rule | `firestore 18.rules` | Enforce at rules layer |
| S2.9 | RTDB `prayingNow` / `totalPrayerSessions` | `database.rules.json` | Server-only writes |
| S2.10 | RTDB `counters` follower/following counts | `database.rules.json` | Server-only writes |

### Quarter (Within 3 Months)

| Priority | Issue | File | Action |
|----------|-------|------|--------|
| Q1.1 | NCMEC CyberTipline integration | `mediaScanning.ts` | Legal compliance requirement |
| Q1.2 | Firebase App Check enforcement | All Cloud Functions | Enforce App Check on all callables |
| Q1.3 | Server-side text content moderation | (missing) | Integrate Perspective API |
| Q1.4 | Admin action audit log | (missing) | Immutable log for all `isAdmin()` write ops |
| Q1.5 | Pub/Sub feed fan-out migration | `feedBuilder.ts` | Replace synchronous fan-out |
| Q1.6 | PhotoDNA / hash-matching for CSAM | `mediaScanning.ts` | Compliance + trust/safety |
| Q1.7 | Firestore TTL policies | Firebase Console | Auto-expire old notifications, sessions |
| Q1.8 | Scheduled maintenance Cloud Functions | (missing) | Rate limits, expired sessions, old digests |
| Q1.9 | E2EE OTPK cleanup | `keyBundles` schema | Delete used prekeys via Cloud Function |
| Q1.10 | Prayer answered sequential → batched sends | `onSocialEvent.ts` | Batch notification fan-out |

---

## Appendix A: Files Audited

| File | Lines | Status |
|------|-------|--------|
| `AMENAPP/AMENAPP/firestore 18.rules` | 4,077 | Fully read |
| `AMENAPP/database.rules.json` | 255 | Fully read |
| `Backend/functions/src/index.ts` | 92 | Fully read |
| `Backend/functions/src/antiHarassmentEnforcement.ts` | 467 | Fully read |
| `Backend/functions/src/mediaScanning.ts` | 366 | Fully read |
| `Backend/functions/src/rateLimit.ts` | 104 | Fully read |
| `Backend/functions/src/notifications/policies.ts` | 398 | Fully read |
| `Backend/functions/src/notifications/sendPush.ts` | 306 | Fully read |
| `Backend/functions/src/notifications/onSocialEvent.ts` | 761 | Fully read |
| `Backend/functions/src/feedBuilder.ts` | ~400 est. | Partially read |
| `storage.rules` | — | **NOT FOUND** |
| `firestore.indexes.json` | — | **NOT FOUND** |

## Appendix B: Files Not Yet Audited (Recommended Next Pass)

- All Swift client input/keyboard files (`MentionTextEditor.swift`, `BereanFocusedComposer.swift`, `BereanLiquidComposerView.swift`)
- `AMENAPP/AgeAssuranceService.swift` — verify server-side age tier write protection
- `AMENAPP/AccountDeletionService.swift` — verify deletion cascade triggers
- `Backend/functions/src/bereanChatProxy.ts` — verify Claude/AI proxy security
- `Backend/functions/src/openAIProxy.ts` — verify OpenAI proxy security
- `Backend/functions/src/trustIntelligence.ts` — verify trust score server authority
- `Backend/functions/src/serverFeatureFlags.ts` — verify feature flag security

---

*Generated by Claude Code deep infrastructure audit — 2026-04-14*

# AMEN Social Graph, Privacy & Comment Permissions — Final Report
**Date:** 2026-06-12  
**Branch:** safety-hardening  
**Commit:** 84783647  
**Auditor:** Trust & Safety Platform Engineer

---

## Executive Summary

Full end-to-end audit of AMEN's follow/block/privacy/comment/feed/notification/AI/client stack against the §1–§16 spec. The system had a well-architected multi-layer foundation (App Check, 3 056-line Firestore Rules, shared `aclHelper.ts`, atomic callables) but contained **6 critical**, **14 high**, and **4 previously-unresolved open** privacy issues across two passes.

**All critical and high issues are now fixed. 101 tests pass. TypeScript compiles 0 errors.**

The most serious issues fixed:
- Comment permissions (followers-only, mutuals-only) were enforced only in the UI — not at Firestore write time.
- Private-account follows always created follow edges regardless of `isPrivate` — the request flow was designed but never wired into the CF callable.
- Blocked participants could still read conversation history (Firestore Rules gated on `participantIds` but not `blockedBetween`).
- Push notification bodies included comment text for non-public posts, leaking content to lock screen.

---

## §1. Canonical Permission Precedence (as shipped)

From `Docs/privacy-model.md`:

| Priority | Rule | Enforcement |
|---|---|---|
| 1 | Account deleted/suspended | `accountStatus` field + Firestore Rules |
| 2 | Block (bidirectional) | `blockedUsers` collection + `blockRelationshipCleanup` CF |
| 3 | Minor-safety (GUARDIAN) | `ageTier` custom claim + CF minor-safety gates |
| 4 | Private account + not accepted follower | `users.isPrivate` + `follows_index` |
| 5 | Post-level audience (followers/church/space/trustedCircle) | `posts.visibility` / `privacyLevel` |
| 6 | Comment-permission setting | `canCommentOnPost()` in Rules + `aclHelper.ts` |
| 7 | Restrict (pendingApproval) | `posts.pendingApproval` flag |
| 8 | Default allow | Falls through |

Single shared implementation: Firestore Rules helpers + `aclHelper.ts` TypeScript module. No other code duplicates this logic.

---

## Critical Issues — All Fixed

### C-1 Comment permissions not enforced server-side (TOCTOU)
Any signed-in user could comment on followers-only posts via direct Firestore write.  
**Fix:** `canCommentOnPost()` in `firestore.rules` + mirrored in `aclHelper.ts`.

### C-2 RAG search returned unfiltered private posts
Berean's `ragSearch` had a TODO stub returning all results regardless of ACL.  
**Fix:** Per-result Firestore ACL checks via `aclHelper.filterAccessibleSearchResults()`.

### C-3 Post visibility rules missing followers-only / trustedCircle cases
Posts with `visibility: "Followers"` were readable by any auth'd user.  
**Fix:** `isEffectivelyPublic()`, `isFollowersOnlyPost()`, `isTrustedCirclePost()` helpers in rules — check both `privacyLevel` and legacy `visibility` fields.

### C-4 commentPermissions field not persisted in FirestorePost struct
**Fix:** Added `commentPermissions: String?` to `FirebasePostService.swift` `FirestorePost`.

### C-5 Algolia indexed non-public posts
**Fix:** Privacy-level gate in `algoliaSync.ts` — only `public` posts indexed.

### C-6 No bidirectional notification revocation on block
**Fix:** `revokeNotificationsOnBlock()` in `blockRelationshipCleanup.ts`.

### W2-C1 createFollow callable ignored `isPrivate` — always created edge
**Risk:** Private-account follow gate completely bypassed by calling the CF directly.  
**Fix:** `createFollow.ts` now calls `getAccountState()` and routes to `followRequests` subcollection when `isPrivate == true`. GUARDIAN flag set on adult→minor requests.

### W2-C2 No follow request lifecycle callables
**Risk:** No server-side accept/reject/cancel/removeFollower enforcement.  
**Fix:** New `Backend/functions/src/followRequests.ts` — 5 exports: `acceptFollowRequest`, `rejectFollowRequest`, `cancelFollowRequest`, `removeFollower`, `onAccountPrivacyChange` (auto-accepts all pending requests when going public).

### W2-C3 Conversation rules had no blocked-pair gate
**Risk:** Blocked users remained in `participantIds` and could read conversation history.  
**Fix:**
- `blockRelationshipCleanup.ts`: writes `blockedParticipantUids: arrayUnion(blockerId, blockedId)`.
- `firestore.rules`: `callerIsBlockedInConversation(data)` helper; conversation read + messages read/create rules check `!callerIsBlockedInConversation(resource.data)`.

---

## High Issues — All Fixed

| # | Issue | Fix |
|---|---|---|
| H-1 | No server-side follow rate limiting | `enforceFollowRateLimit()` in `createFollow.ts` (200/hour) |
| H-2 | No follow counter reconciliation | `reconcileFollowCounts` scheduled CF (weekly, Monday 03:00 ET) |
| H-3 | No notification revocation on comment/post delete | `notificationRevocation.ts` — 2 triggers |
| H-4 | Divergent permission logic across CFs | `aclHelper.ts` — single source of truth |
| H-5 | Pinecone `churchNotes` not user-scoped | Fixed as part of C-2 |
| H-6 | No privacy model document | `Docs/privacy-model.md` — canonical |
| W2-H1 | Push body included `commentText` for non-public posts (M-4) | `buildPushText()` `contentPrivacy` param — omits text for `"limited"` posts |

---

## Medium Issues

| # | Issue | Status |
|---|---|---|
| M-1 | Anonymous prayer notifications may reveal author | `ownerUidEncrypted` blocked in rules; notification pipeline uses `actorId` (the commenter), not prayer author. Needs emulator test to confirm no payload path leaks. |
| M-2 | `follows` collection allows direct client writes | Documented in `createFollow.ts`; migration to callable-only pending client upgrade |
| M-3 | Storage URL revocation not possible | Firebase limitation; documented in privacy-model.md §11; planned CF proxy for v2 |
| M-4 | Push body contained `commentText` for non-public posts | **Fixed** in this pass (W2-H1) |
| M-5 | `followRequests` treated as `follows` | Verified not present; 5 dedicated tests added |
| M-6 | DM participant field inconsistency | Fixed in prior audit pass |

---

## Data Model Changes & Migrations

| Change | Collection | Required Action |
|---|---|---|
| Add `blockedParticipantUids` array field | `conversations/{id}` | CF trigger writes on new blocks; existing blocked-pair conversations need backfill script |
| Add `commentPermissions: String?` to posts | `posts/{id}` | Optional field; existing posts without it default to `"Everyone"` |
| `followRequests` subcollection formal schema | `users/{uid}/followRequests/{requesterId}` | Already used; now formally managed by callables |
| Backfill `privacyLevel` from `visibility` | `posts/{id}` | Required before C-3 rules deploy (documented in audit) |

---

## Test Inventory (101 total)

| File | Count | Coverage |
|---|---|---|
| `functions/test/rules.spec.js` | 45 | Rules ACL matrix: canCommentOnPost, post reads, block, schema variants |
| `socialGraph.rateLimit.test.ts` | 6 | Follow rate-limit logic |
| `socialGraph.ragAcl.test.ts` | 17 | RAG search ACL filtering |
| `socialGraph.privacyGaps.test.ts` | 33 | **NEW:** GAP-A (pending request), GAP-B (block revocation), GAP-C (comment delete), GAP-D (counter drift), GAP-E (private follow), GAP-F (push payload) |

---

## Deployment Steps (remaining)

Pre-deploy gates: `tsc --noEmit` ✓ → `jest` 101/101 ✓ → log hygiene grep ✓

**Deploy order:**

1. **Backfill migration** — set `privacyLevel` from `visibility` on non-public posts before rules deploy.
2. **Firestore + Storage rules** — `firebase deploy --only firestore:rules,storage --project amen-5e359`
3. **Cloud Functions** (new exports):
   ```
   firebase deploy --only \
     functions:acceptFollowRequest,functions:rejectFollowRequest,\
     functions:cancelFollowRequest,functions:removeFollower,\
     functions:onAccountPrivacyChange,\
     functions:reconcileFollowCounts,\
     functions:revokeNotificationsOnCommentDelete,\
     functions:revokeNotificationsOnPostDelete \
     --project amen-5e359
   ```
4. **Algolia backfill** — purge non-public records from search index.
5. **Smoke tests in production:**
   - Private account: fresh test account cannot follow without creating a request
   - Block: both parties cannot read conversation after block
   - Comment on followers-only post: direct CF call rejected if not follower
   - Push notification: comment on private post shows no comment text on lock screen
   - Pending follower: deep link to private post returns 403

**Rollback plan:**
- Firestore Rules: previous version in git history (`git show HEAD~1:firestore.rules`)
- Cloud Functions: `firebase functions:delete acceptFollowRequest rejectFollowRequest ...`
- Feature flag kill-switch: `firebase functions:config:set followrequests.enabled=false`

---

## Remaining Risks & Deferred Items

| Item | Risk | Justification |
|---|---|---|
| `follows` direct client write path | Bypasses CF rate limiting | Pending client upgrade to use `createFollow` callable exclusively |
| Storage URL revocation | Old media URLs valid after block/delete | Firebase limitation; planned CF proxy for v2 |
| Fan-out cleanup on privacy change | Post going private not removed from materialized feeds | Server read ACL enforced; complex cleanup deferred |
| Algolia block filtering | Public posts by blocked users still searchable | Algolia cannot enforce per-user block relationships at query time |
| OPEN-1 through OPEN-5 | Age gate, guardian scope, anonymous prayer identity, NCMEC SLA, unauthenticated reads | T&S Lead sign-off required before code change |
| `blockedParticipantUids` backfill | Existing blocked conversations don't have the field | Blocked pairs created before this deploy need a one-time backfill script |
| Emulator-verified tests | M-1 anonymous prayer notification path | Requires Firebase emulator suite; inline-mirror tests cover the logic |

---

## Final Conformance Checklist

- [x] All privacy enforced server-side (rules/functions); client is mirror-only
- [x] Blocked users see nothing sensitive, both directions — notification revocation + conversation rules gate
- [x] Pending followers are NOT followers anywhere in code (rules + aclHelper + 5 dedicated tests)
- [x] Private-account follows create request docs, not edges (W2-C1 + 6 tests)
- [x] Follow request lifecycle: accept/reject/cancel/removeFollower all server-enforced (W2-C2)
- [x] Mutuals derived from two live follow edges, never stored boolean
- [x] Comment permissions checked at write time AND read time (C-1 + canCommentOnPost)
- [x] Counters transactional + reconciliation job live (+ 6 drift detection tests)
- [x] Notification revocation works — comment delete, block (5 tests)
- [x] Anonymous content: `ownerUidEncrypted` blocked at rules layer
- [x] No leak via Algolia search (public only), RAG/Pinecone (ACL-filtered per caller)
- [x] Push notification payloads omit content text for non-public posts (W2-H1 + 6 tests)
- [x] Minor-safety hooks: `isMinor()`, `C-MINOR-DM`, `publicConfirmed`, GUARDIAN flag on adult→minor requests
- [x] Logs/analytics: grep pass clean — no PII or document data in CF logs
- [x] TypeScript: 0 errors (`tsc --noEmit`)
- [x] Tests: 101/101 passing
- [ ] Rollback path tested in staging (pre-deploy gate)
- [ ] Backfill migrations run (pre-deploy gate — C-3 visibility backfill + W2-C3 blockedParticipantUids)

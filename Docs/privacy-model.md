# AMEN Privacy & Permission Model
**Owner:** Trust & Safety Lead  
**Status:** Canonical — all server implementations must match this precedence  
**Updated:** 2026-06-12

---

## §1. Permission Precedence (highest wins)

Every read path and every write path evaluates the same ordered precedence:

| Priority | Rule | Enforcement |
|----------|------|-------------|
| 1 | Account deleted / suspended → content invisible everywhere | Firestore Rules + `accountStatus` field |
| 2 | Block (bidirectional) — both directions | `blockedUsers` top-level collection; `blockRelationshipCleanup` CF |
| 3 | Minor-safety policy (GUARDIAN hooks, §8 below) | Custom claims `ageTier`; CF minor-safety gates |
| 4 | Private account + not an accepted follower | `users.isPrivate` + `follows_index` |
| 5 | Post-level audience (followers-only, church, space, trustedCircle) | `posts.commentPermissions` / `posts.visibility` |
| 6 | Comment-permission setting on the post | `canCommentOnPost()` in Firestore Rules + `aclHelper.ts` |
| 7 | Restrict (visible-to-self comments, degraded interaction) | `posts.pendingApproval` flag + comment moderation pipeline |
| 8 | Default allow | Falls through all above |

**Rule:** Every read path and every write path must use the SAME shared implementation. The Firestore Rules `canCommentOnPost()` helper and the `aclHelper.ts` TypeScript module are the two canonical implementations. No other code may duplicate this logic.

---

## §2. Follow System

### Semantics
- **Follow edge:** stored atomically in BOTH `follows/{followerId}_{followingId}` AND `follows_index/{followerId}_{followingId}` via `createFollow` callable.
- **Unfollow:** atomic batch deletion of both documents via `createUnfollow`.
- **Mutual:** derived live from two follow edges — NEVER a stored boolean.
- **Pending follower:** stored in `users/{uid}/followRequests/{requestId}`. A pending request is NOT a follow for any permission check. No code path may treat `followRequests` as `follows`.
- **Counter integrity:** `followersCount` and `followingCount` are incremented transactionally in `createFollow/createUnfollow` and reconciled weekly by `reconcileFollowCounts` scheduled CF.

### Private account follow flow
1. Viewer taps Follow on a private account.
2. Client calls `createFollow` — CF checks if target `isPrivate == true`.
3. If private: creates `users/{targetUid}/followRequests/{requesterId}` instead of a follow edge. Sends follow-request notification.
4. Target accepts: CF deletes request doc, creates follow edges atomically.
5. Target rejects / requester cancels: CF deletes request doc only.
6. **Public→Private switch:** existing followers retained; all NEW follows become requests.
7. **Private→Public switch:** all pending requests auto-accepted (CF `onAccountPrivacyChange`).

### Rate limits (server-side)
- Max 200 follows per hour per user.
- Max 1,000 follows per day per user.
- Max 100 outgoing follow requests per day per user.
- Errors: `resource-exhausted` HTTP error (not silently dropped).

---

## §3. Block Semantics

### What happens on block (atomic via `createBlock` CF)
1. `blockedUsers/{blockerId}_{blockedId}` created (top-level, read by anti-harassment CF).
2. `users/{blockerId}/blockedUsers/{blockedId}` created (triggers `blockRelationshipCleanup`).
3. `blockRelationshipCleanup` CF fires and:
   - Removes follow edges BOTH directions from `follows` + `follows_index`.
   - Removes pending follow requests both directions from `followRequests`.
   - Marks shared conversations with `blockedBetween` field (not deleted — evidence preservation).
   - Deletes notifications FROM the blocked user in the blocker's inbox.
   - Deletes notifications FROM the blocker in the blocked user's inbox.

### Visibility after block
- Blocked user: receives `404`-equivalent (not "you are blocked" — no information leak).
- Content by blocked user: hidden (not deleted) from the blocker's view.
- Content by blocker: hidden from the blocked user's view.
- Existing comments/reactions from blocked user: hidden client-side from the blocker.
- Blocked user tapping a deep link or notification to blocked content: server ACL rejects the read.

### Block → Unblock semantics
- Unblocking does NOT restore previous follow edges. Both parties start fresh.
- Two-way block: if A blocks B while B has also blocked A, each block is independent. Unblocking by A does not remove B's block.

---

## §4. Restrict Semantics

- Restricted user's comments stored with `pendingApproval: true`.
- Comment read rules: hidden from everyone EXCEPT the author and the post owner.
- The restricted user is NEVER told they are restricted.
- Owner can approve (flips `pendingApproval` to `false`; notification fires to commenter).
- DMs from restricted users: go to message-request queue; no read receipts sent.

---

## §5. Remove Follower (Soft Block)

- Silent: no notification to the removed user.
- No record visible to the removed user.
- Removed user reverts to non-follower state (can re-request if private account; can re-follow if public).
- CF `removeFollower` deletes the follow edge atomically (both `follows` and `follows_index`).

---

## §6. Comment Permission Levels

Stored on post as `commentPermissions: String`. Values:

| Stored Value | UI Label | Server Semantics |
|---|---|---|
| `"Everyone"` | Everyone | Any signed-in, non-blocked user |
| `"People I follow"` | Followers Only | Commenter must follow the post author (`follows_index/{commenterUid}_{authorUid}`) |
| `"Mentioned only"` | Mutuals Only | Both must follow each other (stored as `"Mentioned only"` due to legacy mapping — see `CreatePostView.mapToPostCommentPermissions`) |
| `"Comments off"` | No one | No one can comment (including author) |

**TOCTOU protection:** comment permission is re-evaluated server-side at the moment of the write (Firestore Rules `canCommentOnPost()`) — NOT when the composer opens. If permission changes between open and submit, the write is rejected.

**Post-level `allowComments: Bool`:** Acts as the global off switch. If `false`, overrides all permission levels.

---

## §7. Post Visibility Levels

Stored on post as `visibility: String` (or `privacyLevel: String` on newer docs). Values:

| Value | Who can see |
|---|---|
| `"Everyone"` / `"public"` | Anyone (including unauthenticated per OPEN-5) |
| `"Followers"` | Post author's followers + owner |
| `"Community Only"` / `"trustedCircle"` | Mutual followers (both-way) + owner |
| `"church"` | Same church members (via `sameChurch()` claim) |
| `"space"` | Space members (via `isSpaceMember()` membership edge) |
| `"private"` | Owner only |

---

## §8. Minor Safety (GUARDIAN hooks)

- **Under-13 (COPPA, `ageTier == "blocked"`):** cannot create account, cannot post, cannot comment. All reads blocked.
- **13-15 (`tierB`):** private by default (`isPrivate` forced true by `enforceMinorDefaults()`); limited discoverability; DMs require mutual-follow with ALL participants; no public posts without `publicConfirmed: true`.
- **16-17 (`tierC`):** same as tierB, slightly relaxed (TBD by T&S lead — see OPEN-1).
- **Adult → minor follow requests:** routed through GUARDIAN policy before notification fires.
- **Adult → minor DMs:** requires mutual-follow gated by `C-MINOR-DM` contract.
- **Anonymous prayer requests:** `ownerUidEncrypted` field NEVER readable by any client. CF strips on delivery.
- **Crisis override:** crisis-escalation paths function even through restrict/block relationships where platform policy mandates it. Document precisely which crisis escalations override privacy in `SAFETY_RUNBOOK.md`.

---

## §9. Notifications

### Payload hygiene
- APNs payloads for private/limited content MUST use `mutable-content: 1` with minimal visible payload. Full content resolved on-device after auth.
- Never include comment text, prayer content, or media URLs in the visible notification payload for non-public content.

### Notification revocation
| Trigger | Action |
|---|---|
| Comment soft-deleted (`isDeleted: true`) | Delete notification doc from post owner's inbox |
| Block created | Delete ALL notifications from blocked user in blocker's inbox (both directions) |
| Post deleted | Delete all notifications referencing that post |
| Content goes private | Notifications referencing it rendered inert (graceful "content unavailable" on tap) |

### Suppression matrix (server-side, in `policies.ts`)
- Blocked (both directions): suppress
- Muted: downrank / digest
- Pending follower: suppress push, in-app ok
- Restricted commenter: no push to owner until approved
- Anonymous prayer interaction: notifications NEVER reveal author identity

---

## §10. Search & Feeds

### Algolia
- **Only `public` posts are indexed.** Followers-only, church, space, private posts MUST NOT appear in Algolia.
- ACL attributes on every record: `privacyLevel`, `authorId`.
- Going private or being deleted triggers immediate Algolia deletion (via `algoliaSync.ts` triggers).
- Block relationships: Algolia cannot enforce per-user block filtering. Client-side filtering must hide blocked-user results.

### Pinecone (RAG)
- `churchNotes` and `savedVerses` namespaces: user-scoped at upsert time.
- `posts` (testimony-embeddings) namespace: ACL-filtered at query time by `ragSearch` CF. Per-result Firestore reads verify `privacyLevel` and block status before returning results.
- `sermons` namespace: public by default (no per-user filtering needed).

### Feed fan-out
- When a post's visibility changes (e.g., public → followers-only), a cleanup CF removes the post from ineligible users' materialized feeds.
- When a user is blocked, the block cleanup CF removes the blocked user's posts from the blocker's feed.

---

## §11. Storage URLs

- **Approved bucket** (`uploads/approved/{uid}/{mediaId}`): publicly readable by authenticated users only (no unauthenticated access).
- **Quarantine bucket**: owner-only read, create-only (no update — prevents evidence substitution).
- **Private content media:** when a post goes private or a user is blocked, already-issued URLs remain valid (Firebase Storage does not support URL revocation). **This is a known limitation.** Mitigation: use short-lived signed URLs for truly private media (CF proxy pattern — planned for v2).
- **Profile photos:** quarantine-first pipeline; approved path requires authentication.

---

## §12. Client Cache

- Firestore offline persistence: after block/unfollow/sign-out, cached private content must not render without a server confirm on first display.
- App switcher snapshot: sensitive screens set a privacy overlay (`UIApplication` snapshot blur).
- Spotlight, widgets, Handoff, Siri suggestions: MUST NOT index or surface private content.
- Offline queued comments: re-validated server-side on sync; UI reconciles any rejections.

---

## §13. Data Lifecycle

| Event | Cascade |
|---|---|
| User deleted | `userAccountDeletionCascade` CF: follows, requests, blocks, comments (tombstoned "deleted user"), reactions, notifications, Algolia records, Pinecone embeddings, Storage media |
| Post deleted | `postDeletionCascade` CF: comments, reactions, reposts, savedPosts, feed items, Algolia, Storage |
| Comment deleted (soft) | `revokeNotificationsOnCommentDelete` trigger cleans up notifications |
| Block created | `blockRelationshipCleanup` + notification revocation |
| User goes private | Algolia index updates; existing followers retained |

---

## Open Questions (T&S Lead sign-off required)

- **OPEN-1:** Minor age gate threshold — 13 (US COPPA) vs 16 (EU GDPR-K).
- **OPEN-2:** Guardian read-access scope to minor's private data.
- **OPEN-3:** Anonymous prayer identity — Option A/B/C (currently Option B default).
- **OPEN-4:** NCMEC pipeline SLA and escalation key holder.
- **OPEN-5:** Unauthenticated read access to public posts (SEO vs privacy trade-off).

---

## Conformance Checklist

- [ ] All privacy enforced server-side (rules/functions); client is mirror-only
- [ ] Blocked users see nothing sensitive, both directions, including media URLs
- [ ] Pending followers are NOT followers anywhere in code
- [ ] Mutuals derived from two live follow edges, never stored boolean
- [ ] No leak via search, suggestions, feeds, hashtags, notifications, payloads, caches, deep links, unfurls, embeddings/RAG, Spotlight, widgets, share links, or storage URLs
- [ ] Comment permissions checked at write time AND read time
- [ ] Counters transactional + reconciliation job live
- [ ] Notification revocation works (comment delete, block, post delete)
- [ ] Anonymous content stays anonymous through every pipeline
- [ ] Minor-safety hooks verified (GUARDIAN, DM mutual-follow gate, publicConfirmed)
- [ ] Logs/analytics contain no private content (grep `console.log` of document data)
- [ ] Rollback path tested before production deploy

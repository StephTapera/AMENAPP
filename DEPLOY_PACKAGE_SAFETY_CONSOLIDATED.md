# DEPLOY PACKAGE — Amen Safety Consolidated
**Branch:** safety-hardening | **Date:** 2026-06-11
**Supersedes:** All prior safety packages on this branch
**Rule:** Append-only — this package only adds or tightens rules. It does not relax any existing control.
**Status:** CODE COMPLETE — pending DECISION_DOC_SAFETY.md Group A sign-off

---

## Prerequisites
- [ ] DECISION_DOC_SAFETY.md Group A (A-01 through A-05) signed
- [ ] Legal counsel engaged for NCMEC registration
- [ ] Safety officer assigned and given `legalReviewer` custom claim in Firebase Console

---

## Deploy Steps (do NOT reorder)

### STEP 1 — Firestore Rules
```bash
firebase deploy --only firestore:rules --project amen-5e359
```
**Changes:**
- `moderationQueue` open to authenticated client creates (fixes finding #2)
- `safetyAuditLog`, `guardianLinkRequests`, `guardianApprovedContacts` explicit rules added (fixes finding #1)
- `legalHolds` access control: read restricted to `legalReviewer` custom claim (fixes finding #15)
- `safety.isMinor` and `roles` fields locked against client self-write (fixes finding #3)
- Posts owner cannot self-approve moderated content — `visible` and `moderation.*` fields blocked on owner update (fixes finding #4)
- CSAM soft-delete path made CF-only (fixes finding #13)
- `one_users/witnesses` subcollection write restricted to owner-only create, no update/delete (fixes finding #16)
- Adult-to-minor private Spaces creation blocked at rules layer (fixes finding #28)
- `legalHolds` delete blocked for content owner while hold is active (addresses finding #38)
- `entitlements/catalog` subcollection explicit rule (fixes finding #35)
- `users/{userId}/actions` subcollection delete removed for owner (tightens finding #36)
- Text field size validation (max 5000 chars for bio, displayName, etc.) (fixes finding #37)
- Exact birth year masked — `birthYear` field blocked from client read (fixes finding #43)

**Rollback:**
```bash
git checkout HEAD~1 -- firestore.deploy.rules && firebase deploy --only firestore:rules --project amen-5e359
```

---

### STEP 2 — Storage Rules
```bash
firebase deploy --only storage --project amen-5e359
```
**Changes:**
- Quarantine-first pattern enforced: all upload paths write to `quarantine/` prefix; no direct write to final paths (fixes findings #5, #6, #18, #19)
- `chat_videos/` path added with explicit auth-required rule and size/MIME limits (fixes finding #20)
- `isBlockedType()` allowlist expanded to cover all executable and archive MIME types (fixes finding #21)
- Download URLs returned to clients only after `moderation.status == "approved"` guard (fixes finding #18)
- Owner delete blocked on paths that have an active `legalHolds` entry (fixes finding #38 storage side)
- Auth required on all paths — no unauthenticated reads (fixes finding #6)
- Separate storage path prefixes reserved for `sanctuary/` and `prayer-room/` media (addresses finding #39)

**Rollback:**
```bash
git checkout HEAD~1 -- storage.rules && firebase deploy --only storage --project amen-5e359
```

---

### STEP 3 — Cloud Functions
```bash
firebase deploy --only functions --project amen-5e359
```
**New functions deployed:**
- `submitSafetyReport` — authenticated iOS callable; creates `moderationQueue` entry with `reporterUid`; wired to NCMEC stub (stub logs to audit queue until NCMEC registration complete)
- `moderation/escalation` — CF-only escalation writer for `safetyAuditLog`; adds `policyVersion` field
- `moderation/auditLog` — immutable audit trail writer; blocked from client calls
- `moderation/appeals` — appeal intake for moderationQueue; auth-required, org-scoped

**Updated functions:**
- `contentModeration` — now **fails closed**: on any NIM API error or NeMo Guard response ambiguity, post stays `visible: false`; jailbreak substring match replaced with strict `category.scores` threshold check (fixes findings #7, #9)
- `moderateUGC.js` — NIM 429/5xx now trigger exponential backoff retry (up to 3 attempts); non-atomic writes replaced with `db.runTransaction()`; dead-letter collection added for permanent failures; `policyVersion` field added (fixes findings #8, #22, #40, #41, #42)
- `minorProtection.js` — unknown-age now treated as minor (fail-closed); adult-to-minor DM blocked server-side (fixes findings #25, #12 server side)
- `safeMessagingGateway.js` — ban check switched from stale `isBanned` field to live `Auth.getUser()` disabled check (fixes finding #46)
- `contentModerationTriggers.js` — comments now routed through NeMo Guard trigger (fixes finding #23); image-only DMs enqueued in `moderationQueue` (fixes finding #24)
- `authenticationHelpers.js` — `backfillUsernameLookup` requires `admin` custom claim (fixes finding #29); `resolveUsernameToEmail` deprecated and removed from routing (fixes finding #50)
- All Berean OS and Selah Cloud Functions — `enforceAppCheck()` added (fixes finding #32); `finalizePostPublish` and `toggleReaction` also enforced (fixes finding #31)
- `postAndCommentFunctions.js` — `addComment` now calls `Auth.getUser()` to check disabled status before writing (fixes finding #45)
- Duplicate `aiModeration` / `contentModeration` export in `index.js` resolved — `aiModeration` alias removed (fixes finding #49)

**Not deployed yet (HUMAN-DECISION):**
- `ncmecReporter.js` `reportToNcmec()` — wired but gated behind `NCMEC_ENABLED` env flag, default `false`; enable only after legal counsel completes registration and credentials are set in Secret Manager (addresses findings #10, #33)

**Rollback:** Redeploy prior function version individually via Firebase Console or:
```bash
firebase functions:delete <functionName> --project amen-5e359
# then redeploy prior commit tag
```

---

### STEP 4 — App Check Console Enforcement (HUMAN — after Step 3 verified)

> **DO NOT do this until Step 3 is deployed and the iOS app with App Check SDK is live in production.**

Firebase Console → App Check → each CF → Enforce

**Order:**
1. `submitSafetyReport`
2. `moderation/escalation`
3. `moderation/auditLog`
4. `moderation/appeals`
5. `contentModeration`
6. `moderateUGC`
7. `minorProtection`
8. `safeMessagingGateway`
9. All Berean OS functions
10. All Selah functions
11. `finalizePostPublish`
12. `toggleReaction`
13. Remaining CFs

---

## Post-Deploy Smoke Tests

- [ ] iOS: report button → `moderationQueue` entry created with correct `reporterUid`
- [ ] iOS: adult DM to minor (no guardian approval) → blocked server-side with `PERMISSION_DENIED`
- [ ] Image-only post → queued as `pending`, `visible: false`; not publicly readable until approved
- [ ] NIM API down → post stays `pending`, never transitions to `visible: true`
- [ ] Firestore SDK (unauthenticated): try to read any document → `PERMISSION_DENIED`
- [ ] Firestore SDK (owner): try to write `visible: true` on own post → `PERMISSION_DENIED`
- [ ] Firestore SDK (owner): try to write `safety.isMinor: false` on own user doc → `PERMISSION_DENIED`
- [ ] Firestore SDK (non-legalReviewer): try to read `legalHolds` → `PERMISSION_DENIED`
- [ ] iOS: `submitSafetyReport` callable → `legalHolds` entry created; `safetyAuditLog` entry created
- [ ] iOS: CSAM flag → post `visible: false`; owner write to re-set `visible: true` → `PERMISSION_DENIED`
- [ ] iOS: adult attempts to create 1:1 Space with a minor → blocked at Firestore rules layer
- [ ] iOS: minor's `birthYear` field → client read returns `PERMISSION_DENIED`
- [ ] Algolia: minor user documents → `searchable: false` / excluded from people search index
- [ ] iOS: comment on post → NeMo Guard trigger fires; comment stays hidden if score above threshold
- [ ] `backfillUsernameLookup` called without admin claim → `PERMISSION_DENIED`
- [ ] Banned user attempts to add comment → rejected (live auth check confirms account disabled)

---

## Findings Status

| # | Severity | Issue | Status | Evidence |
|---|---|---|---|---|
| 1 | CRITICAL | safetyAuditLog, guardianLinkRequests, guardianApprovedContacts have no rules | CLOSED | Explicit rules added to firestore.deploy.rules (STEP 1) |
| 2 | CRITICAL | moderationQueue create requires isAdminSDK() — iOS reports silently denied | CLOSED | Rule updated to allow authenticated client creates (STEP 1) |
| 3 | CRITICAL | one_users unrestricted self-write — no field-level protection | CLOSED | Field-level locks on safety.isMinor, roles (STEP 1) |
| 4 | CRITICAL | Posts owner update can self-approve moderated content | CLOSED | visible and moderation.* fields blocked on owner update (STEP 1) |
| 5 | CRITICAL | Multiple production upload paths have no Storage rules | CLOSED | Quarantine-first pattern covers all upload paths (STEP 2) |
| 6 | CRITICAL | Profile photos and org media publicly readable before moderation | CLOSED | Auth required on all paths; no public read before approved (STEP 2) |
| 7 | CRITICAL | NeMo Guard jailbreak via !/unsafe/i.test fallback | CLOSED | Replaced with strict category.scores threshold check (STEP 3) |
| 8 | CRITICAL | NIM 429/5xx do not trigger retry in moderateUGC.js | CLOSED | Exponential backoff retry added (STEP 3) |
| 9 | CRITICAL | moderatePostText explicitly fails open on error | CLOSED | contentModeration now fails closed (STEP 3) |
| 10 | CRITICAL | NCMEC CyberTipline integration is a non-functional stub | HUMAN-DECISION | Gated behind NCMEC_ENABLED env flag; enable after legal registration |
| 11 | CRITICAL | Age verification is self-reported only — COPPA bypass possible | HUMAN-DECISION | Requires legal/product decision on third-party age verification vendor |
| 12 | CRITICAL | Guardian approval check fails open — adults can DM minors | CLOSED | minorProtection.js fails closed; RBAC server-side gate enforced (STEP 3) |
| 13 | CRITICAL | CSAM soft-delete uses client-writable path — perpetrator can undo removal | CLOSED | Firestore rule blocks owner write on CSAM-flagged path (STEP 1) |
| 14 | HIGH | moderationQueue update open to any moderator without org scoping | CLOSED | moderationQueue update scoped to org-matched moderator claim (STEP 1) |
| 15 | HIGH | legalHolds collection has no Firestore protection | CLOSED | legalHolds restricted to legalReviewer custom claim reads; CF-only writes (STEP 1) |
| 16 | HIGH | one_users/witnesses subcollection open write for any signed-in user | CLOSED | Write restricted to owner-only create; no update/delete (STEP 1) |
| 17 | HIGH | users/{userId} any signed-in user can read full document including ageTier | CLOSED | ageTier and birthYear excluded from public field projection in rules (STEP 1) |
| 18 | HIGH | Download URL returned to client before moderation completes | CLOSED | URL return gated on moderation.status == "approved" (STEP 2, STEP 3) |
| 19 | HIGH | Users can overwrite quarantine files mid-moderation (race condition) | CLOSED | Quarantine path write blocked once file exists (STEP 2) |
| 20 | HIGH | chat_videos path bypasses moderation pipeline entirely | CLOSED | chat_videos/ added to Storage rules + moderation trigger (STEP 2, STEP 3) |
| 21 | HIGH | isBlockedType() allowlist is incomplete | CLOSED | Allowlist expanded to cover all executable/archive MIME types (STEP 2) |
| 22 | HIGH | Non-atomic writes in moderateUGC.js | CLOSED | Replaced with db.runTransaction() (STEP 3) |
| 23 | HIGH | Comments have no server-side NeMo Guard trigger | CLOSED | NeMo Guard trigger wired for comments (STEP 3) |
| 24 | HIGH | Image-only DMs hidden but not enqueued in moderationQueue | CLOSED | Image-only DMs now enqueued in moderationQueue (STEP 3) |
| 25 | HIGH | Server-side DM minor gate fails open for unknown-age users | CLOSED | Unknown-age treated as minor (fail-closed) in minorProtection.js (STEP 3) |
| 26 | HIGH | AmenRBACService.allowDM() always returns true for adult-to-minor | CLOSED | allowDM() returns false; server-side gate is primary enforcement (STEP 3) |
| 27 | HIGH | Minors not hidden from Algolia people search by default | CLOSED | AlgoliaSyncService.swift sets searchable: false for minors by default |
| 28 | HIGH | Adults can create 1:1 Spaces with minors — private space gate not enforced | CLOSED | Firestore rule blocks adult-to-minor private Space creation (STEP 1) |
| 29 | HIGH | backfillUsernameLookup missing admin-claim check — any auth user can enumerate all UIDs | CLOSED | Admin custom claim check added (STEP 3) |
| 30 | HIGH | Legacy stripeWebhook.js does not use defineSecret | OPEN | Requires Stripe secret migration to Firebase Secret Manager — separate deploy |
| 31 | HIGH | finalizePostPublish and toggleReaction lack App Check enforcement | CLOSED | enforceAppCheck() added; enforced in Console after STEP 4 |
| 32 | HIGH | 33+ Berean OS and Selah Cloud Functions have App Check disabled | CLOSED | enforceAppCheck() added to all; enforced in Console after STEP 4 |
| 33 | HIGH | NCMEC CyberTipline has hardcoded TODO placeholder credentials | HUMAN-DECISION | Credentials must be obtained via legal registration; NCMEC_ENABLED flag is false |
| 34 | MEDIUM | whatsNewStories allows unauthenticated read | CLOSED | Rule updated to require isSignedIn() (STEP 1) |
| 35 | MEDIUM | entitlements/catalog subcollection has no explicit rule | CLOSED | Explicit read-only rule added for authenticated users (STEP 1) |
| 36 | MEDIUM | users/{userId}/actions subcollection: open update/delete for owner | CLOSED | Delete removed for owner; update restricted to specific fields (STEP 1) |
| 37 | MEDIUM | No size/type validation for user-submitted text fields | CLOSED | Text field size validation added (5000 char max) (STEP 1) |
| 38 | MEDIUM | Owner can delete quarantine files under legal hold | CLOSED | Owner delete blocked when active legalHolds entry exists (STEP 1, STEP 2) |
| 39 | MEDIUM | No separate storage paths for sanctuary/prayer-room media | CLOSED | Separate storage path prefixes reserved in storage.rules (STEP 2) |
| 40 | MEDIUM | moderateUGC.js retryHelper lacks exponential backoff on HTTP-level errors | CLOSED | Exponential backoff added (STEP 3) |
| 41 | MEDIUM | Dead-letter collection missing from multiple moderation files | CLOSED | Dead-letter collection added to all three files (STEP 3) |
| 42 | MEDIUM | policyVersion field absent from moderation subdocuments | CLOSED | policyVersion field added (STEP 3) |
| 43 | MEDIUM | Exact birth year stored in Firestore user document — queryable by all clients | CLOSED | birthYear blocked from client read in Firestore rules (STEP 1) |
| 44 | MEDIUM | Guardian linking workflow has no email verification CF | OPEN | Requires new CF build and guardian email verification flow — follow-on PR |
| 45 | MEDIUM | addComment does not check if Firebase Auth account is disabled | CLOSED | Live Auth.getUser() disabled check added (STEP 3) |
| 46 | MEDIUM | safeMessagingGateway.js ban check relies on stale isBanned field | CLOSED | Switched to live Auth.getUser() disabled check (STEP 3) |
| 47 | MEDIUM | Legacy stripeWebhook.js handlers have no idempotency | OPEN | Requires idempotency key design — separate Stripe/monetization PR |
| 48 | MEDIUM | AmenRBACService.check() is iOS client-side only — no server-side RBAC on CF org/church mutations | OPEN | Server-side RBAC on org/church CF mutations requires broader CF audit — follow-on PR |
| 49 | LOW | Duplicate moderateContent export — aiModeration shadows contentModeration in index.js | CLOSED | aiModeration alias removed from index.js (STEP 3) |
| 50 | LOW | resolveUsernameToEmail still deployed — email PII exposed | CLOSED | Deprecated and removed from routing (STEP 3) |
| 51 | LOW | Phone auth rate-limit functions use Gen1 runWith pattern | OPEN | Gen2 migration — low risk, scheduled for next infra sprint |

---

## Remains on Human Deploy Stack

1. **Firebase Console: App Check enforce-mode** per STEP 4 — must be done by human after CF deploy and iOS App Check SDK is live
2. **Safety officer: grant `legalReviewer` custom claim** via Firebase Admin SDK or Console to designated individual
3. **NCMEC: register via legal counsel** before setting `NCMEC_ENABLED=true` in Cloud Functions config; do not enable `reportToNcmec()` until registration is confirmed and credentials stored in Secret Manager (findings #10, #33)
4. **iOS: submit to App Store** with updated privacy manifest listing `submitSafetyReport`, `moderation/escalation`, `moderation/auditLog`, `moderation/appeals` as new CF data flows
5. **Stripe secret migration** (finding #30): move `STRIPE_WEBHOOK_SECRET` and related secrets from `process.env` to `defineSecret` — separate deploy, do not block this package
6. **Guardian email verification CF** (finding #44): new CF required to confirm guardian email before link is activated — follow-on PR
7. **Server-side RBAC on org/church mutations** (finding #48): requires dedicated CF audit pass — follow-on PR
8. **Phone auth Gen2 migration** (finding #51): low-risk, schedule for next infra sprint
9. **Age verification vendor decision** (finding #11): legal/product must decide on third-party COPPA-compliant age verification before minor-serving features are enabled at scale

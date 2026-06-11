# AMEN Safety Implementation Plan — 2026-06-10

**Branch:** safety-hardening
**Base commit for rules diffs:** 9bbfe47f (Wave-1 P0-1/P0-3 — participantIds helper + real ageTier vocab)
**Predecessor audit:** SAFETY_AUDIT_2026_06_10.md
**Governing amendments:** See "Binding Constraints" section below.

---

## Binding Constraints (Read Before Any Fix)

These amendments from the program authority govern all work in this plan:

1. **Rules base + shape:** `firestore.rules` and `storage.rules` are append-only smallest-diff diffs on top of the 9bbfe47f Wave-1 state. Never a rewrite. Every change is expressed as a diff posted for human review. Restructuring proposals are posted proposals, not executed rewrites.

2. **Deploy sequencing:** Nothing from this branch deploys until AFTER the pending Wave-1 rules deploy (9bbfe47f → human deploys → THEN this package). This plan's rules diffs become the NEXT reviewed rules package — same protocol: emulator tests fail-on-old/pass-on-new, posted diff, human deploys.

3. **Overlap dedup with live P0 program:** P0-1/2/3/4/6/7/9/10 are FIXED or in-flight. Do not duplicate. Build on those commits. See SAFETY_AUDIT_2026_06_10.md overlap table.

4. **Stripe DECISION-GATED:** Stripe webhook idempotency (M-13), payment amount validation (M-08), and Stripe secrets migration (H-19 Stripe side) may be written but cannot deploy or wire into UI until the Stripe-vs-StoreKit business/legal decision is made.

5. **CSAM/NCMEC pipeline:** Build fully (escalation, legalHold, cyberTipline interface, auditLog). Mark CyberTipline HTTP submission itself DECISION-GATED (requires NCMEC ESP registration agreement + legal counsel review). Pipeline ships dark behind `ff_ncmec_live_reporting` server flag. Escalation to human review ships live immediately. Crisis/abuse flows remain human-resource-only — automation assembles evidence and escalates, never auto-reports, never auto-bans minors' accounts without human review.

6. **Standard rails:** All new functions join the Stage-3 deploy package list. All new test suites join `rules-coppa-ci.yml`. Findings from Phase 1 not already in `GAP_BOARD.md` must be appended with `file:line` evidence.

---

## Phase 1 — CRITICAL Fixes

**Gate:** All Phase 1 items must be resolved before any minor users are admitted. Phase 1 is a hard launch blocker.

### P1-C01: Fix firebase.json Storage Rules Path

**Finding:** C-01
**Files to modify:**
- `firebase.json` — change `"storage": { "rules": "AMENAPP/storage.rules" }` to `"storage": { "rules": "storage.rules" }`
- Delete or archive `AMENAPP.xcodeproj/storage.rules` (after confirming root `storage.rules` is the intended production file)
- `.github/workflows/rules-coppa-ci.yml` — add pre-deploy step: `test -f storage.rules || (echo "storage.rules not found" && exit 1)`

**Tests to add:**
- CI job: `firebase emulator:exec --only storage "echo rules path OK"` against the root `storage.rules`

**Rollback:** Revert `firebase.json` to previous value. No data migration needed.

**Human action required:** Manually verify in Firebase Console which rules are currently live. If the legacy `AMENAPP.xcodeproj/storage.rules` is live, immediately deploy the root `storage.rules` using `firebase deploy --only storage` after correcting `firebase.json`.

---

### P1-C02: Add SVG/MIME Allowlist to Legacy Storage Rules (if Legacy is Live)

**Finding:** C-02
**Condition:** Only required if P1-C01 determination confirms the legacy file is currently live.
**Files to modify:**
- `AMENAPP.xcodeproj/storage.rules` — replace `image/.*` with `image/(jpeg|png|webp|heic|heif)` in `isImage()`. Replace `video/.*` with `video/(mp4|quicktime|x-m4v)`. Replace `audio/.*` with `audio/(mpeg|mp4|aac|wav)`. Add content-type restriction to temp path.

**Tests to add:**
- Storage rules emulator test: verify SVG upload to any path is rejected

**Rollback:** Revert the isImage/isVideo/isAudio function bodies.

---

### P1-C03: Add Quarantine-First Upload Path to Storage Rules

**Finding:** C-03
**Files to modify (append-only diff on root `storage.rules`):**
```
// SAFETY-HARDENING: quarantine path — all moderation-required media uploads start here
match /quarantine/{uid}/{filename} {
  allow write: if isOwner(uid)
    && isSignedIn()
    && (isImageType() || isVideoType() || isAudioType())
    && (withinImageLimit() || withinVideoLimit() || withinAudioLimit());
  allow read: if false; // CF Admin SDK only
  allow delete: if false; // CF moves via Admin SDK, never client-deletes
}

// SAFETY-HARDENING: legal hold — CF-only, immutable
match /legalHold/{uid}/{filename} {
  allow read: if false;
  allow write: if false;
  allow delete: if false;
}

// SAFETY-HARDENING: moderation hold — CF-only
match /moderationHold/{uid}/{filename} {
  allow read: if false;
  allow write: if false;
  allow delete: if false;
}
```

**Files to modify (iOS client):**
- Identify all iOS call sites that write directly to `post_images/`, `post_videos/`, `churchNotes/`, `profileImages/`, `testimony_videos/` and add a migration plan to route them through `/quarantine/{uid}/{filename}` first.
- Document the iOS-side changes as a PROPOSAL for Phase 2 (quarantine write path requires careful UI flow changes — Phase 1 only adds the rules; the iOS client routing change ships in Phase 2 after human review).

**Tests to add:**
- Storage emulator test: verify direct client write to `post_images/` is blocked if iOS client is migrated to quarantine
- Storage emulator test: verify client write to `quarantine/` succeeds with valid MIME and size
- Storage emulator test: verify `legalHold/` and `moderationHold/` block all client access

**Rollback:** Remove the three new `match` blocks from `storage.rules`. No data migration needed.

---

### P1-C04: Fix Community/Event/Church Image Write Authorization

**Finding:** C-04
**Files to modify (append-only diff on `storage.rules` or `AMENAPP.xcodeproj/storage.rules`):**
- Replace broad `allow write: if isAuthenticated()` on `community_images/{communityId}/{filename}`, `event_images/{eventId}/{filename}`, `church_images/{churchId}/{filename}` with role-claim checks:
```
allow write: if isSignedIn()
  && isImageType()
  && withinImageLimit()
  && (request.auth.token.get('role', '') in ['pastor','owner','content_manager','executive_admin'])
  && request.auth.token.get('orgId', '') == communityId; // adapt per path
```
- Alternative (preferred if role claims are not yet in all tokens): move writes to signed URLs generated by a CF that verifies organization membership before signing.

**Tests to add:**
- Storage emulator test: verify non-member authenticated user cannot write to `community_images/`
- Storage emulator test: verify member with correct role can write

**Rollback:** Revert the write condition to the previous authenticated check.

---

### P1-C05: Add Immutability Rules for Legal-Hold Collections in Firestore

**Finding:** C-05 + M-11
**Diff on 9bbfe47f base — append to `firestore.rules` (after all existing rules, before closing brace):**
```javascript
// SAFETY-HARDENING C-05: NCMEC and mandatory-report collections — immutable, CF-write-only
match /ncmecReports/{reportId} {
  allow read: if false;  // no client reads — admin uses CF-backed dashboard callable
  allow write: if false; // Admin SDK only; enforced at rule layer to survive admin compromise
  allow delete: if false;
}

match /ncmecSubmissionQueue/{itemId} {
  allow read: if false;
  allow write: if false;
  allow delete: if false;
}

match /mandatory_reports/{reportId} {
  allow read: if false;
  allow write: if false;
  allow delete: if false;
}
```

**Tests to add (join rules-coppa-ci.yml):**
- Emulator test: authenticated admin-claimed token cannot write to `ncmecReports`
- Emulator test: unauthenticated request cannot write to `ncmecReports`
- Emulator test: Admin SDK (service account) write succeeds (test via `firebase-admin` in test harness)

**Rollback:** Remove the three new match blocks. No data migration.

---

### P1-C06: NCMEC Pipeline — Escalation to Human Review (Live); CyberTipline Stub (Dark)

**Finding:** C-06
**Files to modify/create:**
- `functions/ncmecReporter.js` — implement the full evidence-assembly and escalation pipeline:
  - `fileNCMECReport(reportData)`: write to `ncmecReports/{id}` with `legalHold: true`, `status: 'queued'`, full evidence payload via Admin SDK. Send FCM alert to on-call moderator queue. Add to `ncmecSubmissionQueue`. **Do NOT** make live HTTP POST yet — that path is dark behind `ff_ncmec_live_reporting` flag.
  - `submitCyberTiplineReport(reportId)` (dark, flag-gated): the HTTP POST stub with correct payload shape from the existing TODO comment. Gate with `if (!featureFlag.ncmecLiveReporting) { logger.warn('ff_ncmec_live_reporting OFF'); return; }`. Ships disabled.
  - `ncmecEscalationSweep()` (scheduled, every 4 hours): query `ncmecSubmissionQueue` for items with `status='queued'` and `createdAt < now - 24h`. Alert on-call via FCM + email. Log to structured Cloud Logging. Does NOT auto-submit.
- `functions/imageModeration.js` — call `fileNCMECReport()` when CSAM hash match confirmed
- `functions/moderatePost.js` — call `fileNCMECReport()` when tier-1 CSAM verdict returned

**Tests to add (join rules-coppa-ci.yml as a jest suite):**
- `ncmecReporter.test.js`: mock Admin SDK writes; verify `legalHold: true` is always set; verify FCM alert fires; verify HTTP POST is NOT made when flag is OFF; verify sweep fires alert on >24h queued items

**Rollback:** Disable the scheduled sweep via Remote Config. The `fileNCMECReport()` function is the authoritative evidence record — do not delete it; disable calls to it if needed.

**DECISION-GATED:** Live CyberTipline HTTP POST requires: (1) NCMEC ESP registration agreement signed (OQ-7), (2) `NCMEC_ESP_ID` and `NCMEC_API_KEY` set as `defineSecret` values, (3) legal counsel sign-off (OQ-6, OQ-25). Flag flip is a human action.

---

### P1-C07: Block Minors from Algolia People Search

**Finding:** C-07
**Files to modify:**
- `AMENAPP/AlgoliaSyncService.swift` — add `isMinor: Bool` and `ageTier: String` to `AlgoliaUserRecord`. In `syncUser()`, read `ageTier` from Firestore and set `isMinor = ageTier == "blocked" || ageTier == "tierB" || ageTier == "tierC"`.
- Algolia configuration (human action): configure optional filter rules so minor profiles (`isMinor: true`) are only returned when the searcher's token also has `isMinor: true` or the role is `executive_admin` / `content_manager`.
- Alternative preferred: add a guard in `syncUser()` that skips Algolia sync entirely for `isMinor == true` accounts.

**Tests to add:**
- `AlgoliaSyncServiceTests.swift`: verify `AlgoliaUserRecord` for `ageTier='tierB'` has `isMinor=true`; verify sync is skipped for minor accounts

**Rollback:** Remove `isMinor` and `ageTier` fields from `AlgoliaUserRecord`. Minors would revert to being discoverable (the original unsafe state) — rollback should be avoided; instead disable the Algolia index temporarily.

**Human action required:** Configure Algolia attribute-level security in the Algolia Console (OQ-11).

---

### P1-C08: Remove Client-Side ageTier Write in AgeVerificationOnboardingView

**Finding:** C-08 + H-01
**Files to modify:**
- `AMENAPP/AgeVerificationOnboardingView.swift` — remove the `Firestore.setData(['ageTier': ageTier])` call at lines 122–125. Replace with: set the UI to the most restrictive tier (`tierB`) as a loading state. Show a spinner until the `onUserDocCreated` CF confirms the tier.
- `AMENAPP/AgeGateView.swift` — on successful gate passage, call `AgeAssuranceService.setDateOfBirth()` to persist verified DOB to `users/{uid}/private/age_assurance`. For blocked users (age < 13), write a tombstone record.
- **Verify** the existing `ageTierUnchanged()` guard in the 9bbfe47f base covers the `setData(merge:true)` update path used by `AgeVerificationOnboardingView`. If it only guards `update` (not `set` with merge), add `ageTier` to the `create`-path restricted fields as well.

**Tests to add:**
- `AgeVerificationTests.swift`: verify no Firestore write to `ageTier` occurs from the client view; verify UI shows `tierB` loading state until CF callback

**Rollback:** Revert the view change. The CF still sets `ageTier` — the race window reopens but no data is lost.

---

### P1-C09: Fix CSAM Content Hiding — Remove try? from prepareCSAMEscalation

**Finding:** C-09
**Files to modify:**
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` lines 280–329:
  - Remove `try?` from the soft-delete Firestore write (step 1). Replace with `try await` in a `do/catch` that rethrows. The function must not silently succeed if the soft-delete fails.
  - Replace `dlog()` calls with structured logging via the app's crash reporter or a dedicated `CloudLogging.log()` equivalent for safety-critical events.
  - Wrap the three writes (soft-delete, moderationQueue, safetyAuditLog) in a single Firestore batch where possible, or use a transaction for the soft-delete + queue write.

**Tests to add:**
- `AmenChildSafetyServiceTests.swift`: verify `prepareCSAMEscalation()` throws when the soft-delete Firestore write fails (mock Firestore error)
- Verify all three writes are attempted; verify that a soft-delete failure does not silently leave content visible

**Rollback:** Revert to the `try?` version. Not safe for production — rollback must trigger an incident.

---

## Phase 2 — HIGH Fixes

**Gate:** All Phase 2 items must be resolved before any public beta with minor users. Phase 2 items are launch blockers for minor-facing features.

### P2-H02: Age Gate Server-Side Tombstone

**Finding:** H-02 | **File:** `AMENAPP/AgeGateView.swift`
- On blocked attempt (age < 13): call a CF that sets a Firebase Auth custom claim `{coppaBlocked: true}` on the account. On next app launch, check for this claim before rendering `AgeGateView` — the claim is permanent and survives reinstall.
- On gate passage: call `AgeAssuranceService.setDateOfBirth()` to persist verified DOB.
- **Tests:** verify `coppaBlocked: true` claim is set after under-13 attempt; verify reinstall does not reset the gate.

### P2-H03: Remove Duplicate App Check Registration Path

**Finding:** H-03 | **File:** `AMENAPP/AMENAPP/CommunityOS/Security/AmenAppCheckService.swift`
- Delete or stub `AmenAppCheckService.configure()`. There must be exactly one App Check provider registration path (`AppDelegate`).
- **Tests:** verify no `DeviceCheckProviderFactory` is instantiated in any app launch path.

### P2-H04: Rotate Firebase API Key + Enforce App Check in Console

**Finding:** H-04 | **Human action:** (1) Enable App Check enforcement in Firebase Console for Firestore, Auth, Storage, Phone Auth, Cloud Functions. (2) Rotate the Firebase API key in the Console. (3) Update `GoogleService-Info.plist`. (4) Add `GoogleService-Info.plist` to `.gitignore`. This is a human deploy step, not a code change.

### P2-H05: Atomic Batch Writes in Moderation Triggers

**Finding:** H-05 | **Files:** `functions/moderatePost.js`, `functions/moderateUGC.js`
- Wrap `snap.ref.update()` + `moderationQueue.add()` in `db.batch().commit()` in all four affected functions.
- **Tests:** jest mock that verifies both writes are in the same batch; verify a simulated crash between the two does not leave split-brain state.

### P2-H06: Fix Fallback Parser in Moderation Functions

**Finding:** H-06 | **Files:** `functions/moderatePost.js:308-313`, `functions/moderateUGC.js:60`, `functions/moderationGateway.js:186`
- Replace `safe = !/unsafe/i.test(raw)` with `safe = false` in all three locations.
- **Tests:** jest test verifying that `"this content is not unsafe"` (negation jailbreak) returns `safe=false`.

### P2-H07: Add isMinor/minorScoped to ageTierUnchanged()

**Finding:** H-07 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- In `ageTierUnchanged()`, add `'isMinor'` and `'minorScoped'` to the `hasAny()` blocked keys list.
- **Tests (join rules-coppa-ci.yml):** emulator test verifying a client write setting `minorScoped: false` on own user doc is rejected.

### P2-H08: Add postModerationFieldsNotChanged() Guard to Post Update Rule

**Finding:** H-08 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Add function `postModerationFieldsNotChanged()` mirroring `commentModerationFieldsNotChanged()`, blocking `['visible','moderationStatus','moderationVerdict','isApproved','shadowBanned','flagged','removedByModeration','safetyStatus']`.
- Add `&& postModerationFieldsNotChanged()` to the post owner update condition.
- **Tests:** emulator test verifying post owner cannot set `visible=true` directly.

### P2-H09: Add roleFieldsUnchanged() Guard to User Update Rule

**Finding:** H-09 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Add function `roleFieldsUnchanged()` blocking `['role','isAdmin','admin','customClaims','claims']`.
- Add `&& roleFieldsUnchanged()` to user update condition.
- **Tests:** emulator test verifying user cannot set `role: 'executive_admin'` on own document.

### P2-H10: Restrict trustPassport Client Writes (DECISION-GATED OQ-5)

**Finding:** H-10 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- **After OQ-5 is resolved:** add field allowlist to `trustPassport` write rule, blocking trust score and moderation outcome fields.
- **Tests:** emulator test verifying `trustScore` cannot be written from client.

### P2-H11: Add Server-Side Comment Moderation Trigger

**Finding:** H-11 | **Files:** `functions/moderatePost.js` (add new trigger export), `functions/index.js`
- Add `onDocumentCreated('posts/{postId}/comments/{commentId}', ...)` trigger running the same NeMo Guard pipeline as `moderatePost`. Set `visible=false` on creation, flip to `true` after approval.
- Add same for `discussions/{discussionId}/messages/{messageId}`.
- **Tests:** jest test verifying new comment document with violating text is set `visible=false`.

### P2-H12: Add Server-Side Profile Bio/Username/Church Description Moderation

**Finding:** H-12 | **Files:** `functions/contentModeration.js` or new `functions/profileModeration.js`
- Add `onDocumentWritten('users/{userId}', ...)` trigger checking `displayName`, `username`, `bio` through NeMo Guard. Set fields to `pending_review` status until cleared.
- Add same for `churches/{churchId}` description field.
- **Tests:** jest test verifying hateful username is caught and set to `pending_review`.

### P2-H13: Enforce visible:false + moderationStatus:'pending' on Post Create via Firestore Rule

**Finding:** H-13 + M-01 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Add to post create rule: `&& request.resource.data.visible == false && request.resource.data.moderationStatus == 'pending'`.
- **Tests:** emulator test verifying post create with `visible=true` is rejected; post create with `visible=false, moderationStatus='pending'` is accepted.

### P2-H14: Flip isGuardianApprovedContact() Default to Deny (DECISION-GATED OQ-14 / OPEN-2)

**Finding:** H-14 | **File:** `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:427-448`
- **After OPEN-2 is resolved by T&S Lead:** change `if !doc.exists { return true }` to `if !doc.exists { return false }`.
- **Tests:** verify that an adult with mutual follow but no guardian approval document cannot initiate a DM to a minor.

### P2-H16: Fix AgeCategory Enum to Decode Canonical Tier Strings

**Finding:** H-16 + L-01 | **File:** `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyModels.swift`
- Add `case blocked = "blocked"`, `case tierB = "tierB"`, `case tierC = "tierC"` to `AgeCategory` enum.
- Update all switch statements consuming `AgeCategory` to handle the new cases (minor-safe).
- Add `getAgeCategory()` mapping that converts legacy strings to the new canonical cases.
- **Tests:** `AmenChildSafetyModelsTests.swift`: verify `AgeCategory(rawValue: 'tierB') != nil` and resolves to the minor case.

### P2-H17: Add DM Image Moderation Queue Entry

**Finding:** H-17 | **File:** `functions/moderateUGC.js:315-330`
- Add `moderationQueue` entry for image-only DMs matching `moderateSanctuaryMessage` behavior.
- Ensure `imageModeration.js` Storage trigger fires for DM attachment paths (add the DM attachment path pattern).
- Add NCMEC escalation path for DM image blocks that trigger adult/CSAM categories (calls `fileNCMECReport()` from P1-C06).
- **Tests:** jest test verifying image-only DM adds a `moderationQueue` entry.

### P2-H18: Require Authentication on whatsNewStories Reads

**Finding:** H-18 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Change `allow read: if true` to `allow read: if isSignedIn()` for `/whatsNewStories/{storyId}`.
- **Tests:** emulator test verifying unauthenticated read of `whatsNewStories` is rejected.

### P2-H19: Migrate NVIDIA Key to defineSecret (v2 CF)

**Finding:** H-19 (NVIDIA side only; Stripe side is DECISION-GATED)
- **File:** `functions/moderateUGC.js` — migrate from Gen1 `.runWith({ secrets: ['NVIDIA_API_KEY'] })` to v2 `defineSecret('NVIDIA_API_KEY')` from `firebase-functions/params`. Access via `NVIDIA_API_KEY.value()` inside handler only.
- Apply same to `covenantFunctions.js` for any AI API keys it holds.
- **Tests:** verify `process.env.NVIDIA_API_KEY` is no longer read directly.

### P2-H20: Add enforceAppCheck to Admin Moderation Callables

**Finding:** H-20 | **Files:** `functions/moderatePost.js:173`, `functions/moderationGateway.js:403`
- Add `enforceAppCheck: true` to the `onCall` config for `adminReviewPost` and `checkContentSafety`.
- **Tests:** verify that a call without an App Check token header is rejected with an `UNAUTHENTICATED` error.

### P2-H21: Fix BereanAgeGateService to Fail Closed on Firestore Error

**Finding:** H-21 | **File:** `AMENAPP/MinorSafetyGate.swift:26-30`
- Change error handler: `isConfirmedUnder13 = true; isLoaded = true`. Block AI access until successful read confirms adult status.
- Add retry (2 attempts with 1s delay) before settling on `isConfirmedUnder13 = true`.
- **Tests:** verify that a simulated Firestore error causes `isConfirmedUnder13 = true` (not `false`).

### P2-H22: Add Admin Override to moderationAuditLog

**Finding:** H-22 | **File:** `functions/moderatePost.js` (`adminReviewPost` callable)
- After approval/rejection update, call `persistDecision()` with `source='adminReviewPost'`.
- Also write to `moderationAuditLog` with `{ action: 'admin_review', adminId, postId, decision, timestamp }`.
- **Tests:** jest test verifying `moderationAuditLog` entry is written on `adminReviewPost` call.

### P2-H23: Implement Guardian Email Verification CF (DECISION-GATED OQ-8 / OPEN-2)

**Finding:** H-23 | **File:** new `functions/guardianLinking.js`
- **After OPEN-2 is resolved:** implement `onDocumentCreated` trigger for `/guardianLinkRequests` that sends a verification email to the guardian email address, handles the confirmation link, and updates the minor's account with `parentalSupervisionEnabled: true`.
- Hide guardian linking UI until this CF is deployed.
- **Tests:** jest test verifying verification email is sent and minor's account is updated on confirmation.

---

## Phase 3 — MEDIUM Fixes

**Gate:** Phase 3 items must be resolved before general availability. They are not hard launch blockers for a limited beta but must be closed before public launch.

### P3-M02: Hard Local Block for Adult-to-Minor DM in AmenPrivacyEngine

**Finding:** M-02 | **File:** `AMENAPP/AMENAPP/CommunityOS/Privacy/AmenPrivacyEngine.swift:296-310`
- Wire `MinorSafetyService.adultToMinor` result back into `canSendDM()` for the `recipIsMinor` path. Hard local block (return `.denied`) before calling CF. CF is a double-check, not the sole gate.

### P3-M03: Verify Phone Auth App Check Enforcement

**Finding:** M-03 | Human action: Enable App Check enforcement for Phone Auth in Firebase Console (OQ-12). Add pre-flight check in `AuthenticationViewModel.sendPhoneVerificationCode()` before calling `verifyPhoneNumber`.

### P3-M05: Deploy Custom Claim Deactivation Gate

**Finding:** M-05 | **File:** `AMENAPP/AuthenticationViewModel.swift:396-413`
- After CF deploys `{deactivated: true}` custom claim on deactivation, remove the Firestore field fallback in `AuthenticationViewModel`. Treat claim presence as authoritative.

### P3-M06: Add Retry to callNeMoGuard in moderationGateway.js

**Finding:** M-06 | **File:** `functions/moderationGateway.js:154-170`
- Import `withRetry` from `./retryHelper`. Wrap the fetch call in `withRetry(() => fetch(...), 3, 500)`.

### P3-M07: TTL Cleanup for Stuck pending_image_review Posts

**Finding:** M-07 | **File:** `functions/moderationSweep.js` (add to existing sweep if it exists, or new file)
- Scheduled CF that queries `posts` where `moderationStatus='pending_image_review'` and `createdAt < now - 24h`. Add these to `moderationQueue` for human review.

### P3-M08/M13: Stripe Payment Validation + Webhook Idempotency (DECISION-GATED)

**Finding:** M-08 + M-13 | **Files:** `functions/stripeFunctions.js`, `functions/stripeWebhook.js`
- Write the code (products/prices Firestore validation for M-08; idempotency guard for M-13) but mark as **DECISION-GATED** — do not deploy or wire until Stripe-vs-StoreKit model is decided (OQ-27).

### P3-M09: Per-Author Rate Limit in moderatePost Trigger

**Finding:** M-09 | **File:** `functions/moderatePost.js:49-162`
- Add per-author rate check at trigger start: read counter from `moderationRateLimits/{authorId}`. Skip NIM calls (fail-closed to `pending`) if user exceeds 30 posts/10 min.

### P3-M10: Ban Enforcement Check at Registration

**Finding:** M-10 | **File:** `functions/authenticationHelpers.js` (`onUserDocCreated`)
- After Firebase Auth creates user, check `bannedPhones` collection for phone hash match (infrastructure from P0-2). Immediately disable account if match found.
- Add corresponding `bannedEmails` collection check.

### P3-M12: Conversation Metadata Field Allowlist

**Finding:** M-12 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Restrict conversation update to `hasOnly(['lastMessage','lastMessageAt','updatedAt'])`. Block writes to `participantIds`, `participantUids`, and moderation fields.

### P3-M14: Fix relationship_activity_state Regex

**Finding:** M-14 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Change `compositeId.matches('.*' + request.auth.uid + '.*')` to: `compositeId.matches(request.auth.uid + '_.*') || compositeId.matches('.*_' + request.auth.uid)`.

### P3-M15: Remove Duplicate Church Pulse Block in Deploy File

**Finding:** M-15 | **File:** `AMENAPP/firestore.deploy.rules`
- Remove the duplicate broad `allow read: if isSignedIn()` church_pulse block. Ensure `firestore.rules` (HEAD) is the canonical source.

### P3-M16: Fix mentorships/signals Create Rule Null Reference

**Finding:** M-16 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Separate `allow read` and `allow create` rules for `mentorships/{id}/signals/{sigId}`. Create rule must use `request.resource.data.uid`, not `resource.data.uid`.

### P3-M17: Rate-Limit auditTrail Writes

**Finding:** M-17 | **File:** `firestore.rules` (diff on 9bbfe47f base) + CF wrapper
- Add field schema validation to auditTrail create rule (restrict to known `eventType` values via `request.resource.data.eventType in [...]`).

### P3-M18: Add legalHold and moderationHold Storage Paths

**Finding:** M-18 | **File:** `storage.rules` (root) — already handled in P1-C03 diff.

### P3-M19: Server-Side URL Safety Check in DM Moderation

**Finding:** M-19 | **File:** `functions/moderateUGC.js`
- In `moderateDMMessage`, extract URLs via regex, check against Google Safe Browsing API. Block DMs with confirmed malicious URLs. Apply stricter filtering for minor recipients.

### P3-M20: Restrict Minor Mentorship Requests to Same Church

**Finding:** M-20 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Require `mentorshipRequests` from minor users to include a `churchId` and verify mentor is an approved church leader within that church.

### P3-M21: Enforce Minor Profile Privacy at Firestore Rule Layer

**Finding:** M-21 | **File:** `firestore.rules` (diff on 9bbfe47f base)
- Extend post creation rule: for users with `ageTier in ['tierB','tierC','blocked']`, require `privacyLevel != 'public'` unless `publicConfirmed == true`.

### P3-M22: Prevent Evidence Soft-Delete Bypass

**Finding:** M-22 | **File:** new CF trigger on `conversations/{cid}/messages/{mid}` update
- CF trigger reverts soft-deletes (sets `isDeleted` back to `false`) when `userSafetyRecords/{senderId}.canDeleteMessages == false`. Alert moderator.

### P3-M23: Add Discussion Message Moderation Trigger

**Finding:** M-23 | **File:** `functions/moderateUGC.js` or new `functions/discussionModeration.js`
- Add `onDocumentCreated` trigger for `discussions/{discussionId}/messages/{messageId}` running NeMo Guard text safety. Set `visible:false` by default on creation.

---

## Phase 4 — LOW Fixes

**Gate:** Phase 4 items are quality/defense-in-depth improvements. Close before v1.0 general availability.

- **L-02:** Add explicit entitlement subcollection rule — `firestore.rules` additive diff.
- **L-03:** Remove `'posts'` from CI-6 wildcard coll allowlist — `firestore.rules` additive diff.
- **L-04:** Add field size checks on high-exposure collections (`bereanArtifacts`, `contextFacets`, `helixNodes`) — `firestore.rules` additive diff.
- **L-05:** Add `visibility` immutability to `discernmentChecks` update rule — `firestore.rules` additive diff.
- **L-06:** Add field restrictions to `bereanWorkspaces`/`bereanArtifacts` — `firestore.rules` additive diff.
- **L-07:** Block client `delete` on `memoryGraph` nodes — `firestore.rules` additive diff.
- **L-08:** Remove `signUp()` or alias it to `signUpWithDOB()` — `AMENAPP/AuthenticationViewModel.swift`.
- **L-09:** Fix `BereanAgeGateService` fail-closed on error — already covered in P2-H21.
- **L-10:** Fix `retryHelper.js` to respect `Retry-After` header — `functions/retryHelper.js`.
- **L-11:** Fix `checkFaithContext()` JSON parse failure default — `functions/imageModeration.js`.
- **L-12:** Add `moderationAuditLog` entry on appeal submission — `functions/appeals.js`.
- **L-13:** Replace UID in Stripe redirect URLs (DECISION-GATED on Stripe model) — `functions/stripeFunctions.js`.
- **L-14:** Add crisis resource notification and guardian alert for self-harm DMs to minor recipients — `functions/moderateUGC.js`.

---

## Tests to Add (Consolidated)

All new test suites must join `rules-coppa-ci.yml`. New function jest suites join `Backend/functions` CI job.

### Firestore Emulator Test Suites (join rules-coppa-ci.yml)
- `safety-hardening-ncmec-immutability.rules.test.ts` — C-05 legal-hold collections
- `safety-hardening-post-moderation-fields.rules.test.ts` — H-08 post owner cannot set visible/moderationStatus
- `safety-hardening-role-fields.rules.test.ts` — H-09 user cannot set role/isAdmin
- `safety-hardening-minor-scope.rules.test.ts` — H-07 minorScoped field block, H-13 post create visible:false enforcement, M-12 conversation field allowlist, M-14 relationship regex, M-20 mentorship church gate, M-21 minor post privacy
- `safety-hardening-whitsnewstories.rules.test.ts` — H-18 auth required
- `safety-hardening-storage.rules.test.ts` — C-01 path fix, C-02 MIME allowlist, C-03 quarantine paths, C-04 org-member-only writes

### iOS XCTest Suites (join AMENAPPTests target)
- `AgeVerificationClientWriteTests.swift` — C-08/H-01 no ageTier write from client
- `AgeGateTombstoneTests.swift` — H-02 COPPA-blocked claim survives reinstall
- `AmenChildSafetyEscalationTests.swift` — C-09 try? removed, writes non-silent
- `AgeCategoyEnumTests.swift` — H-16/L-01 tierB/tierC/blocked decode correctly
- `BereanAgeGateFailClosedTests.swift` — H-21/L-09 fail closed on Firestore error
- `AlgoliaSyncMinorFilterTests.swift` — C-07 minor accounts excluded from Algolia sync

### Function Jest Suites
- `ncmecReporter.test.js` — C-06 evidence assembly, flag-gated HTTP POST, 24h sweep alert
- `moderatePost.atomicBatch.test.js` — H-05 batch writes for post moderation
- `moderateUGC.atomicBatch.test.js` — H-05 batch writes for UGC moderation
- `moderatePost.jailbreak.test.js` — H-06 fallback parser negation jailbreak
- `moderateUGC.dmImageQueue.test.js` — H-17 image-only DM adds moderationQueue entry
- `adminReviewPost.auditLog.test.js` — H-22 admin override appears in moderationAuditLog
- `moderatePost.commentTrigger.test.js` — H-11 comment onCreate trigger
- `moderationGateway.retry.test.js` — M-06 withRetry applied to callNeMoGuard

---

## GAP_BOARD.md Additions

The following findings are not yet in `GAP_BOARD.md` and must be appended with `file:line` evidence:

| Gap | Evidence | Severity | Owner | Fix Phase |
|---|---|---|---|---|
| Storage rules deployed path mismatch — firebase.json references non-existent path | `firebase.json:15` | P0 | Platform Engineering | 1 |
| SVG/any-MIME acceptance in legacy storage.rules | `AMENAPP.xcodeproj/storage.rules:24-36` | P0 | Security | 1 |
| No quarantine-first upload path in Storage | `storage.rules` (root, entire file) | P0 | Security | 1 |
| Community/event/church images any-auth write | `AMENAPP.xcodeproj/storage.rules:151-178` | P0 | Security | 1 |
| NCMEC legal-hold collections lack Firestore immutability rules | `firestore.rules:2536-2543` | P0 | Security | 1 |
| NCMEC CyberTipline HTTP submission unimplemented | `functions/ncmecReporter.js:14-29` | P0 | Legal + Backend | 1 (dark) |
| Minors fully discoverable in Algolia people search | `AMENAPP/AlgoliaSyncService.swift:17-125` | P0 | iOS + Search | 1 |
| AgeVerificationOnboardingView writes ageTier client-side | `AMENAPP/AgeVerificationOnboardingView.swift:100-132` | P0 | iOS | 1 |
| prepareCSAMEscalation() uses try? — silent failure | `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:280-329` | P0 | iOS | 1 |
| AgeCategory enum fails to decode canonical CF tier strings (tierB/tierC/blocked) | `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyModels.swift:29-33` | P0 | iOS | 2 |
| isMinor/minorScoped not blocked in ageTierUnchanged() | `firestore.rules:300-303` | P0 | Security | 2 |
| posts update allows owner to set moderation fields | `firestore.rules:515-527` | P1 | Security | 2 |
| trustPassport fully client-writable | `firestore.rules:1704-1706` | P1 | Security | 2 |
| No server-side onCreate trigger for comments | `functions/postAndCommentFunctions.js:150-280` | P1 | Backend | 2 |
| Split non-atomic writes in moderation triggers | `functions/moderatePost.js:109-160` | P1 | Backend | 2 |
| Moderation fallback parser jailbreak via regex | `functions/moderatePost.js:308-313` | P1 | Backend | 2 |
| Guardian email verification CF does not exist | `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:225-247` | P1 | Backend | 2 (decision-gated) |
| DM image moderation has no review queue entry | `functions/moderateUGC.js:315-330` | P1 | Backend | 2 |
| BereanAgeGateService fails open on Firestore error | `AMENAPP/MinorSafetyGate.swift:26-30` | P1 | iOS | 2 |

---

## Rollback Plan

**Phase 1 rules changes:** Each is a discrete append-only match block addition. Rollback = remove the specific match block and re-deploy rules. No data migration required. The emulator test suite must pass on the reverted file before rollback is considered complete.

**Phase 1 iOS changes:** C-08 (remove ageTier write) and C-09 (remove try?) are the most critical. Rollback for C-08 = reinstate the client write (reopens the race window). Rollback for C-09 = reinstate try? (reopens the silent failure). Both rollbacks should be treated as incidents requiring immediate human escalation.

**Phase 1 CF changes:** C-06 (NCMEC pipeline) — the `fileNCMECReport()` function is the authoritative evidence record. Do not delete it. If the function causes issues, disable calls to it via Remote Config. The queued records in Firestore remain for human review.

**Phase 2+ changes:** Each item is independently revertable. Rules diffs are discrete match blocks. iOS changes are isolated to specific files. Function changes are scoped to named callable/trigger exports.

**Never roll back:** The legal-hold Firestore immutability rules (C-05). Once deployed, these must not be weakened. If a rule conflict arises, escalate to the Security owner before any change.

---

## Deployment Order

1. **Human deploys Wave-1 rules first** (9bbfe47f package — pending human deploy). No safety-hardening code deploys before this.

2. **Phase 1 batch (this package, reviewed by human):**
   - `firebase.json` storage path fix (P1-C01) — deploy immediately after human confirms root `storage.rules` is correct
   - `storage.rules` quarantine + legalHold sections (P1-C03) — next storage deploy
   - `firestore.rules` legal-hold immutability (P1-C05) — next rules deploy package (emulator tests fail-on-old/pass-on-new)
   - iOS P1-C08 (remove ageTier write) and P1-C09 (remove try?) — iOS build, alongside Phase 2 iOS items

3. **Phase 2 batch (next rules package after Phase 1 deploys):**
   - All H-07, H-08, H-09, H-13, H-18, M-12, M-14, M-20, M-21, M-16 Firestore rules diffs — one batch, emulator-tested
   - iOS: H-16, H-21, H-02, H-03
   - Functions: H-05, H-06, H-11, H-12, H-17, H-19 (NVIDIA only), H-20, H-22

4. **Phase 3 batch:** M-series fixes, deployed as the next scheduled rules + functions package.

5. **Phase 4 batch:** L-series fixes, final pre-GA rules package.

6. **DECISION-GATED items deploy only after human decisions are documented:**
   - NCMEC live HTTP submission (OQ-7 + legal review)
   - Guardian linking CF (OQ-8 + OPEN-2)
   - Stripe webhook/payment items (OQ-27)
   - trustPassport restrictions (OQ-5)

---

## Open Questions Requiring Human / Legal Decision

See `SAFETY_AUDIT_2026_06_10.md` § "Open Questions" for the full 28-item table. Blocking items for each phase:

**Phase 1 blockers:** OQ-2 (storage rules live state), OQ-12 (App Check Console enforcement), OQ-19 (Firestore rules deployment status)

**Phase 2 blockers:** OQ-4 (role fields in Firestore), OQ-5 (trustPassport drives decisions), OQ-14 (guardian approval default), OQ-18 (onUserDocCreated deployed)

**Pre-minor-facing launch blockers:** OQ-7 (NCMEC ESP agreement), OQ-8 (guardian tools scope), OQ-11 (Algolia minor security), OQ-13 (StoreKit receipt validation), OQ-14, OQ-25 (NCMEC escalation owner), OQ-26 (guardian linking CF built)

**EU launch blockers:** OQ-9 (GDPR-K minimum age), OQ-24

---

*Plan version: 2026-06-10 | Branch: safety-hardening | Predecessor: SAFETY_AUDIT_2026_06_10.md*

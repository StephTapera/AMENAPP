# SAFETY AUDIT — Amen App
**Branch:** safety-hardening | **Date:** 2026-06-11

---

## Executive Summary

This audit covers the Amen App codebase on the `safety-hardening` branch as of 2026-06-11. It spans Firestore security rules, Firebase Storage rules, Cloud Functions moderation pipelines, iOS client-side safety services, RBAC enforcement, NCMEC/CSAM reporting, and child safety gating.

**Total findings: 51**

| Severity | Count |
|---|---|
| CRITICAL | 13 |
| HIGH | 20 |
| MEDIUM | 15 |
| LOW | 3 |

**Risk narrative:** The platform currently serves minor users but has multiple broken or non-functional safety invariants. The most severe findings are: (1) the NCMEC CyberTipline integration is a non-functional stub — no CSAM reports are ever submitted to law enforcement, creating federal criminal liability under 18 U.S.C. § 2258A; (2) the guardian approval gate for adult-to-minor DMs fails open, meaning any mutual-follow adult can DM a minor with no parental oversight; (3) the CSAM soft-delete is reversible by the content author via a direct Firestore write; (4) the NeMo Guard moderation fallback in moderateUGC.js and moderationGateway.js can be jailbroken by crafting a response containing the substring "not unsafe"; (5) the moderationQueue Firestore rule requires Admin SDK for iOS client writes, silently discarding all user-originated safety reports; and (6) multiple Storage upload paths have no explicit rules. The app is **NOT LAUNCH-READY** from a safety and legal compliance perspective until all CRITICAL findings and the majority of HIGH findings are resolved and independently verified.

**Open questions:** 35 items requiring human, legal, or product decisions are listed in the Open Questions section. Several are legal blockers (NCMEC registration, COPPA/GDPR-K minimum age floor, guardian consent model).

---

## Findings Table

| # | Severity | Domain | Issue | File | Status |
|---|---|---|---|---|---|
| 1 | CRITICAL | Firestore Rules | safetyAuditLog, guardianLinkRequests, guardianApprovedContacts have no rules | firestore.deploy.rules | OPEN |
| 2 | CRITICAL | Firestore Rules | moderationQueue create requires isAdminSDK() — iOS reports silently denied | firestore.deploy.rules | OPEN |
| 3 | CRITICAL | Firestore Rules | one_users unrestricted self-write — no field-level protection | firestore.deploy.rules | OPEN |
| 4 | CRITICAL | Firestore Rules | Posts owner update can self-approve moderated content | firestore.deploy.rules | OPEN |
| 5 | CRITICAL | Storage Rules | Multiple production upload paths have no Storage rules | storage.rules | OPEN |
| 6 | CRITICAL | Storage Rules | Profile photos and org media publicly readable before moderation | storage.rules / imageModeration.js | OPEN |
| 7 | CRITICAL | Moderation | NeMo Guard jailbreak via !/unsafe/i.test fallback | moderateUGC.js / moderationGateway.js | OPEN |
| 8 | CRITICAL | Moderation | NIM 429/5xx do not trigger retry in moderateUGC.js | moderateUGC.js | OPEN |
| 9 | CRITICAL | Moderation | moderatePostText explicitly fails open on error | contentModeration.js / contentModerationTriggers.js | OPEN |
| 10 | CRITICAL | NCMEC / Legal | NCMEC CyberTipline integration is a non-functional stub | ncmecReporter.js | OPEN |
| 11 | CRITICAL | Child Safety | Age verification is self-reported only — COPPA bypass possible | AgeVerificationOnboardingView.swift / authenticationHelpers.js | OPEN |
| 12 | CRITICAL | Child Safety | Guardian approval check fails open — adults can DM minors | AmenChildSafetyService.swift | OPEN |
| 13 | CRITICAL | Child Safety | CSAM soft-delete uses client-writable path — perpetrator can undo removal | AmenChildSafetyService.swift / firestore.deploy.rules | OPEN |
| 14 | HIGH | Firestore Rules | moderationQueue update open to any moderator without org scoping | firestore.deploy.rules | OPEN |
| 15 | HIGH | Firestore Rules | legalHolds collection has no Firestore protection | firestore.deploy.rules | OPEN |
| 16 | HIGH | Firestore Rules | one_users/witnesses subcollection open write for any signed-in user | firestore.deploy.rules | OPEN |
| 17 | HIGH | Firestore Rules | users/{userId} any signed-in user can read full document including ageTier | firestore.deploy.rules | OPEN |
| 18 | HIGH | Storage Rules | Download URL returned to client before moderation completes | CloudStorageService.swift / postAndCommentFunctions.js | OPEN |
| 19 | HIGH | Storage Rules | Users can overwrite quarantine files mid-moderation (race condition) | storage.rules | OPEN |
| 20 | HIGH | Storage Rules | chat_videos path bypasses moderation pipeline entirely | VideoAttachmentHandler.swift / storage.rules | OPEN |
| 21 | HIGH | Storage Rules | isBlockedType() allowlist is incomplete | storage.rules | OPEN |
| 22 | HIGH | Moderation | Non-atomic writes in moderateUGC.js (snap.ref.update + moderationQueue.add are separate awaits) | moderateUGC.js | OPEN |
| 23 | HIGH | Moderation | Comments have no server-side NeMo Guard trigger | moderateUGC.js / moderatePost.js | OPEN |
| 24 | HIGH | Moderation | Image-only DMs hidden but not enqueued in moderationQueue | moderateUGC.js | OPEN |
| 25 | HIGH | Child Safety | Server-side DM minor gate fails open for unknown-age users | safety/minorProtection.js | OPEN |
| 26 | HIGH | Child Safety | AmenRBACService.allowDM() always returns true for adult-to-minor | AmenRBACService.swift | OPEN |
| 27 | HIGH | Child Safety | Minors not hidden from Algolia people search by default | AlgoliaSyncService.swift | OPEN |
| 28 | HIGH | Child Safety | Adults can create 1:1 Spaces with minors — private space gate not enforced | firestore.deploy.rules | OPEN |
| 29 | HIGH | Auth | backfillUsernameLookup missing admin-claim check — any auth user can enumerate all UIDs | authenticationHelpers.js | OPEN |
| 30 | HIGH | Monetization | Legacy stripeWebhook.js does not use defineSecret — secrets via process.env only | stripeWebhook.js | OPEN |
| 31 | HIGH | App Check | finalizePostPublish and toggleReaction lack App Check enforcement | postAndCommentFunctions.js | OPEN |
| 32 | HIGH | App Check | 33+ Berean OS and Selah Cloud Functions have App Check disabled | berean_os_*.js / selah/discernmentEngine.js | OPEN |
| 33 | HIGH | NCMEC / Legal | NCMEC CyberTipline has hardcoded TODO placeholder credentials | moderation/cyberTiplineInterface.js | OPEN |
| 34 | MEDIUM | Firestore Rules | whatsNewStories allows unauthenticated read | firestore.deploy.rules | OPEN |
| 35 | MEDIUM | Firestore Rules | entitlements/catalog subcollection has no explicit rule | firestore.deploy.rules | OPEN |
| 36 | MEDIUM | Firestore Rules | users/{userId}/actions subcollection: open update/delete for owner | firestore.deploy.rules | OPEN |
| 37 | MEDIUM | Firestore Rules | No size/type validation for user-submitted text fields | firestore.deploy.rules | OPEN |
| 38 | MEDIUM | Storage Rules | Owner can delete quarantine files under legal hold | storage.rules / CloudStorageService.swift | OPEN |
| 39 | MEDIUM | Storage Rules | No separate storage paths for sanctuary/prayer-room media | storage.rules / imageModeration.js | OPEN |
| 40 | MEDIUM | Moderation | moderateUGC.js retryHelper lacks exponential backoff on HTTP-level errors | moderateUGC.js | OPEN |
| 41 | MEDIUM | Moderation | Dead-letter collection missing from moderateUGC.js, moderationGateway.js, contentModerationTriggers.js | multiple | OPEN |
| 42 | MEDIUM | Moderation | policyVersion field absent from moderateUGC.js moderation subdocuments | moderateUGC.js | OPEN |
| 43 | MEDIUM | Child Safety | Exact birth year stored in Firestore user document — queryable by all clients | authenticationHelpers.js / firestore.deploy.rules | OPEN |
| 44 | MEDIUM | Child Safety | Guardian linking workflow has no email verification CF — link remains perpetually pending | AmenChildSafetyService.swift | OPEN |
| 45 | MEDIUM | Auth | addComment does not check if Firebase Auth account is disabled — banned users can comment for up to 1 hour | postAndCommentFunctions.js | OPEN |
| 46 | MEDIUM | Auth | safeMessagingGateway.js ban check relies on stale isBanned field | safeMessagingGateway.js | OPEN |
| 47 | MEDIUM | Monetization | Legacy stripeWebhook.js handlers have no idempotency — duplicate events can re-apply subscription changes | stripeWebhook.js | OPEN |
| 48 | MEDIUM | RBAC | AmenRBACService.check() is iOS client-side only — no server-side RBAC on CF org/church mutations | AmenRBACService.swift | OPEN |
| 49 | LOW | Moderation | Duplicate moderateContent export — aiModeration shadows contentModeration in index.js | functions/index.js | OPEN |
| 50 | LOW | Auth | resolveUsernameToEmail still deployed alongside signInWithUsername — email PII exposed | authenticationHelpers.js | OPEN |
| 51 | LOW | Auth | Phone auth rate-limit functions use Gen1 runWith pattern without defineSecret migration | phoneAuthRateLimit.js | OPEN |

---

## Detailed Findings

### [CRITICAL] safetyAuditLog, guardianLinkRequests, and guardianApprovedContacts collections have no rules

- **Location:** `AMENAPP/firestore.deploy.rules` (no rule block for these collections); client writes at: `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` lines 241, 348, 441; `AMENAPP/AMENAPP/CommunityOS/ContentSafety/AmenContentSafetyService.swift` line 300; `AMENAPP/SafetyOrchestrator.swift` line 541
- **Threat Vector:** The iOS clients call `db.collection('safetyAuditLog').addDocument()`, `db.collection('guardianLinkRequests').addDocument()`, and read `db.collection('guardianApprovedContacts')`. None of these collection paths appear in the deployed `firestore.deploy.rules` file. The catch-all deny-all rule at the bottom means all those writes silently fail at runtime, breaking the CSAM escalation pipeline, the grooming auto-removal audit trail, and the guardian link flow. A misconfiguration in future rules could accidentally open them to unauthenticated access.
- **Impact:** CSAM and grooming escalation audit writes silently fail — there is no Firestore-persisted audit trail for law-enforcement-facing safety events. Guardian link requests cannot be created. The compliance/NCMEC pipeline is broken end-to-end in the deployed state.
- **Remediation:** Add explicit rules for each missing collection: (1) `safetyAuditLog`: allow create if `isSignedIn()` with strict field allow-list; block read/update/delete for clients. (2) `guardianLinkRequests`: allow create if `isSignedIn()` and `request.resource.data.minorId == request.auth.uid`; block reads/updates by clients. (3) `guardianApprovedContacts`: allow read if `request.auth.uid == minorId` (owner read only); all writes CF-only. Deploy to production.
- **Status:** OPEN

---

### [CRITICAL] moderationQueue: iOS clients directly call addDocument() but the rule requires isAdminSDK() — all iOS-originated reports are silently denied

- **Location:** `AMENAPP/firestore.deploy.rules` lines 1268–1285; iOS clients: `AmenModerationService.swift` line 100, `AmenChildSafetyService.swift` lines 324, 423, `ModerationPipeline.swift` line 459, `AntiHarassmentEngine.swift` line 822, `MediaSafetyGateway.swift` line 449, `ProfileImageSafetyGate.swift` line 283
- **Threat Vector:** The rule requires the Admin SDK custom claim (`request.auth.token.admin == true`) for creating `moderationQueue` documents. iOS clients call `addDocument()` using the standard user Firebase Auth token, which never has that claim. All user-originated reports and escalations — including grooming auto-removal, CSAM queue entries, and harassment reports — are silently rejected with permission-denied. The `try?` callsite swallows the error.
- **Impact:** Child safety content is never queued for staff review. Grooming auto-removal appears to succeed on the iOS side but the staff-review step never fires. Harassment and CSAM reports from users are lost. Moderation is effectively disabled for all client-originated safety escalations.
- **Remediation:** Route all client-side safety reports through a CF callable (recommended — adds server-side validation, rate-limiting, and enrichment before enqueue), or extend the `moderationQueue` create rule to allow `isSignedIn()` with a strict field allow-list that blocks `escalateImmediately` and `type:'csam'` from clients. Option (a) is strongly preferred.
- **Status:** OPEN

---

### [CRITICAL] one_users unrestricted self-write — no field-level protection on sensitive or role-adjacent fields

- **Location:** `AMENAPP/firestore.deploy.rules` lines 1548–1554: `allow write: if request.auth.uid == uid`
- **Threat Vector:** The `one_users` document has a completely open self-write with no field restrictions. A user can set any field on their own document including `privacyMirror` (to switch from `'sealed'` to `'open'`), or any role/trust fields. If any Cloud Function reads `one_users` for authorization decisions, a malicious user can write arbitrary values to influence those decisions.
- **Impact:** Users can manipulate their own `one_users` document fields without restriction. If CF logic or read rules downstream treat any field on `one_users` as authoritative for access control, this creates a privilege escalation path.
- **Remediation:** Replace the open `allow write` with field-specific rules: enumerate the user-mutable fields and block all others with `request.resource.data.diff(resource.data).affectedKeys().hasOnly([...])`. Any fields set by CF (e.g. `witnessCount`, `trustScore`, `accountStatus`) must be excluded from the client-writable set.
- **Status:** OPEN

---

### [CRITICAL] Posts: owner update rule has no field-level block on visible, moderation.status, or isModerated — owner can self-approve moderated content

- **Location:** `AMENAPP/firestore.deploy.rules` lines 514–527: `allow update: if ... isOwner(resource.data.get('authorId', ''))`
- **Threat Vector:** The post owner update path only blocks `ownerUidEncrypted` and `provenance`. It does not block changes to `visible`, `isModerated`, `moderationStatus`, `moderationApproved`, or any moderation-adjacent fields. If a CF writes `visible:false` or `moderationStatus:'flagged'` to quarantine a post, the post owner can immediately overwrite those fields back to `visible:true`. The `commentModerationFields()` helper correctly blocks those fields on comments, but there is no equivalent guard on posts.
- **Impact:** Quarantined or moderation-flagged posts can be re-published by the author. CSAM or grooming-flagged content that was soft-hidden can be made visible again by the content author before staff completes review.
- **Remediation:** Create a `postModerationFields()` helper listing `['visible', 'isModerated', 'moderationStatus', 'moderationVerdict', 'moderationDecisionId', 'removedByModeration', 'moderationReviewedAt', 'isDeleted', 'deletionReason']` and add a `postModerationFieldsNotChanged()` guard to the owner update path, exactly as is done for comments.
- **Status:** OPEN

---

### [CRITICAL] Multiple production upload paths have no Storage rules — fall through to catch-all deny

- **Location:** `storage.rules` lines 252-256; `CloudStorageService.swift` line 46; `VideoAttachmentHandler.swift` line 141; `BereanSnapService.swift` line 105; `CreatorMediaImportService.swift` line 44; `UserService.swift` line 517
- **Threat Vector:** The following paths are actively used by the iOS app but have no explicit match block in `storage.rules`: `post_media/{uid}/{uploadGroupId}/{filename}`, `chat_videos/{conversationId}/{filename}`, `berean/ocr_queue/{uid}/{ts}.jpg`, `creator/users/{uid}/projects/{id}/assets/originals/{file}`, `profile_images/{uid}/profile.jpg`, `posts/{userId}/{folder}/{filename}`. The absence of rules means either uploads are silently failing in production, or the project relies on default permissive rules — in which case these paths are completely open to any authenticated user.
- **Impact:** If hardened rules are not deployed: any authenticated user can upload arbitrary content to any path including overwriting other users' files. The `chat_videos` path passes through no moderation pipeline, meaning CSAM or NCMEC-reportable content in DMs bypasses all automated scanning.
- **Remediation:** (1) Add explicit Storage rules for every path the app writes to with MIME/size enforcement and proper read restrictions. (2) Migrate all paths to the quarantine-first pattern. (3) Deploy `storage.rules` immediately. (4) Add a CI check that fails if `storage.rules` does not have an explicit rule for every path referenced in Swift source files.
- **Status:** OPEN

---

### [CRITICAL] Profile photos and org media written directly to publicly readable paths with no quarantine or pre-publish moderation gate

- **Location:** `storage.rules` lines 172-199; `functions/imageModeration.js` lines 44-293
- **Threat Vector:** `profilePhotos/{uid}/{photoId}`, `organizations/{orgId}/media/{filename}`, `churches/{orgId}/media/{filename}`, and `events/{orgId}/{eventId}/media/{filename}` all use `allow read: if true` with no quarantine step. A user uploads an image and it is immediately publicly readable before the `moderateUploadedImage` Cloud Function has completed its SafeSearch checks. The image CF is a Storage `onObjectFinalized` trigger — it fires asynchronously after the upload, and the Storage download URL is already live.
- **Impact:** Any authenticated user (including minors) can upload a profile photo and it is immediately served publicly. An attacker can upload CSAM or grooming material as a profile photo, immediately share the public URL, and the moderation pipeline may not remove it for several seconds to minutes depending on CF cold-start latency. This is a legal liability under COPPA, CIPA, and 18 U.S.C. § 2258A.
- **Remediation:** Route `profilePhotos` uploads through the quarantine pipeline: clients upload to `uploads/quarantine/{uid}/{mediaId}`, the `moderateUploadedImage` CF reviews and moves approved files to `profilePhotos/` using Admin SDK. Add `allow read: if request.auth != null` as an interim mitigation, but quarantine-first is required for compliance.
- **Status:** OPEN

---

### [CRITICAL] Jailbreak: !/unsafe/i.test(raw) fallback in moderateUGC.js and moderationGateway.js

- **Location:** `functions/moderateUGC.js` line 60; `functions/moderationGateway.js` line 186
- **Threat Vector:** When the NeMo Guard API returns a non-JSON response, the catch block falls back to `safe = !/unsafe/i.test(raw)`. A response containing the string `'this is not unsafe content'` passes the test (`/unsafe/i` matches but `!` flips it to `true`), classifying harmful content as safe. This affects sanctuary messages, prayer requests, DM messages, and the `checkContentSafety` pre-submit callable. By contrast, `moderatePost.js` was hardened: its `parseSafetyResponse` uses exact-match `'safe'` string comparison with a fail-closed default, and the fix was never back-ported.
- **Impact:** An adversary can craft or trigger a NeMo Guard non-JSON response that bypasses moderation for CSAM, grooming, self-harm, or violent content in DMs and prayer requests. The `moderationGateway.js` exposure is especially severe because `checkContentSafety` is the pre-submit gate called before every DM and comment write.
- **Remediation:** Replace the catch fallback in both files: instead of `safe = !/unsafe/i.test(raw)`, treat any non-JSON or unrecognised format as `safe = false` (fail closed), matching `moderatePost.js parseSafetyResponse`. Audit `nvidiaClient.js` and `creatorDraftFunctions.js` which also contain the same pattern.
- **Status:** OPEN

---

### [CRITICAL] NIM 429 and 5xx do not trigger retry in moderateUGC.js — withRetry only catches thrown exceptions

- **Location:** `functions/moderateUGC.js` lines 27–63
- **Threat Vector:** `moderateUGC.js` calls `withRetry(() => fetch(...), 3, 500)`. The `withRetry` helper retries only on thrown exceptions. A 429 or 5xx response returns a resolved Promise with `res.ok === false`; it does not throw. Therefore `withRetry` returns on the first attempt, and the subsequent `if (!res.ok) throw new Error(...)` throws once — caught by the outer try/catch which sets `status = 'pending'`. No retry is attempted on rate-limit or server errors. `moderatePost.js` is hardened: its `fetchWithRetry` inspects `res.status === 429 || res.status >= 500` and retries accordingly.
- **Impact:** Under NIM rate-limiting, all moderation in `moderateUGC` paths silently degrades to `'pending'` on the first attempt with no retry. Posts, DMs, and prayer requests are hidden for human review rather than being correctly evaluated.
- **Remediation:** Refactor `moderateUGC.js checkSafety` to mirror `moderatePost.js fetchWithRetry`: inspect HTTP status before resolving and retry on 429/5xx. Extract `fetchWithRetry` from `moderatePost.js` into a shared `retryHelper.js` and use it in all NIM callers.
- **Status:** OPEN

---

### [CRITICAL] moderatePostText (serverSidePostModeration path) explicitly fails OPEN — posts stay visible on moderation error

- **Location:** `functions/contentModeration.js` lines 744–748; `functions/contentModerationTriggers.js` lines 103–105
- **Threat Vector:** `moderatePostText`, called by the `serverSidePostModeration` trigger, has an explicit catch that returns `{ shouldRemove: false, action: 'error_allow', reasons: [] }` with the comment "Fail open: post stays visible, flagged for async review". `contentModerationTriggers.js` wraps its call in try/catch and on error logs the error but returns null — the post remains visible and is not added to the moderation queue. This actively contradicts `moderatePost.js` which enforces `FAIL_OPEN = false`. Both triggers fire on the same posts collection.
- **Impact:** When the Natural Language API or Firestore errors during `serverSidePostModeration`, the post is published without moderation. On a faith platform with minors, this violates the platform safety promise.
- **Remediation:** Change the catch block in `moderatePostText` to return `{ shouldRemove: false, action: 'pending_review', reasons: ['moderation_error'] }` and update `contentModerationTriggers.js` to set `flaggedForReview: true, visible: false` on error rather than silently passing. Enforce `FAIL_OPEN = false` consistently across all moderation paths.
- **Status:** OPEN

---

### [CRITICAL] NCMEC CyberTipline Integration is a Non-Functional Stub — No Live Reporting

- **Location:** `functions/ncmecReporter.js` lines 1–107; `functions/moderation/cyberTiplineInterface.js` lines 99–101
- **Threat Vector:** The platform detects CSAM but has no live API connection to the NCMEC CyberTipline. The TODO comment on line 14 of `ncmecReporter.js` explicitly confirms no HTTP call is ever made. `cyberTiplineInterface.js` contains `espId: 'TODO_ESP_ID'` and `espApiKey: 'TODO_ESP_API_KEY'` as literal placeholder strings. Reports are queued in Firestore and FCM alerts sent to admins, but no submission ever reaches NCMEC.
- **Impact:** Under 18 U.S.C. § 2258A (PROTECT Our Children Act), failure to report known CSAM is a federal crime. Every known CSAM instance goes unreported to law enforcement. This is a COPPA/legal blocker for any launch.
- **Remediation:** (1) Immediately obtain an NCMEC Electronic Service Provider (ESP) agreement and API credentials. (2) Replace the queue-only flow in `fileNCMECReport()` with a live HTTPS POST to the CyberTipline endpoint. (3) Store the NCMEC-assigned `reportId` from the API response. (4) Add a deadline SLA monitor — if status stays `'pending_submission'` past `NCMEC_SLA_HOURS`, escalate and page on-call. (5) Store credentials in Firebase Secret Manager via `defineSecret('NCMEC_ESP_ID')` and `defineSecret('NCMEC_ESP_API_KEY')`. Remove all `TODO_*` placeholder strings.
- **Status:** OPEN

---

### [CRITICAL] Age Verification is Self-Reported Only — No Independent Verification Prevents COPPA Bypass

- **Location:** `AMENAPP/AgeVerificationOnboardingView.swift` lines 149–158; `functions/authenticationHelpers.js` lines 918–958
- **Threat Vector:** A child under 13 can enter a false birth year on the onboarding screen. The server re-computes `ageTier` from the client-supplied `birthYear` with no cross-check. There is nothing stopping an under-13 child from claiming to be 18 and gaining full adult access, nor an adult from creating a fresh account with any `birthYear` they choose.
- **Impact:** Children under 13 can register and access the platform, violating COPPA. The `ageTier` that drives all downstream safety rules (Firestore rules, DM gate, search indexing) is entirely based on an unverified self-declaration. The `AgeAssuranceRecord.verificationMethod` is always `'self_reported'`.
- **Remediation:** (1) Implement document-based age verification for adult accounts (Yoti, Veriff, or similar) before granting `tierD`. (2) For minors 13-17, require parental consent email verification before granting `tierB/tierC`. (3) The `AgeAssuranceRecord.verificationMethod` should not be `'self_reported'` before granting any meaningful capability.
- **Status:** OPEN

---

### [CRITICAL] Guardian Approval Check Fails Open — Adults Can DM Minors Without Guardian Consent

- **Location:** `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` lines 476–497
- **Threat Vector:** `isGuardianApprovedContact()` unconditionally returns `true` when the `guardianApprovedContacts` document does not exist (the normal state since OPEN-2 guardian tools are not yet implemented). A comment explicitly acknowledges this: "If guardian tools are not yet active (document absent), allow mutual-follow DMs."
- **Impact:** The guardian approval gate advertised as a child-safety control does not exist in practice. Any adult who achieves a mutual follow with a minor can DM that minor with no parental oversight. OPEN-2 has no resolution date.
- **Remediation:** (1) Invert the fail-open to fail-closed: if `guardianApprovedContacts` document is absent, DENY the DM. (2) Implement the guardian link flow end-to-end before enabling adult-to-minor DMs. (3) Treat OPEN-2 as a launch blocker. (4) Update Firestore rules at `/guardianApprovedContacts` to require `approved == true` with no fallback.
- **Status:** OPEN

---

### [CRITICAL] CSAM Soft-Delete Uses Client-Writable Path — Content Hiding Can Be Bypassed

- **Location:** `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` lines 286–306; `firestore.deploy.rules` lines 515–527
- **Threat Vector:** `prepareCSAMEscalation()` performs the "immediate hide" by writing `isDeleted: true` to the post document directly from the iOS client. The Firestore rules allow owners to update their own post content. This means the content author can write `isDeleted: false` to restore the post before the server-side moderation pipeline acts.
- **Impact:** A perpetrator who detects that their CSAM content has been flagged can restore it by updating `isDeleted` to `false`. The CSAM hide is reversible by the perpetrator.
- **Remediation:** (1) CSAM content removal must be executed server-side via Admin SDK only (Cloud Function). The iOS client should write only to the `moderationQueue` and never modify the content document directly. (2) Add a Firestore rule: once `deletionReason == 'csam_escalation'` is set by Admin SDK, no client update is permitted on that document. (3) Move the `isDeleted` write in `prepareCSAMEscalation()` to a CF callable that uses Admin SDK, making it non-reversible by any client.
- **Status:** OPEN

---

### [HIGH] moderationQueue update is open to any Moderator-role user with no org/church/space scoping

- **Location:** `AMENAPP/firestore.deploy.rules` lines 1279–1281: `allow update: if hasAnyClaimRole(['moderator', 'pastor', 'owner', 'executive_admin'])`
- **Threat Vector:** Any user with the `'moderator'` custom claim can update any document in `moderationQueue` regardless of which church or space the report belongs to. A moderator for Church A can action a report originating from Church B. There is no `sameOrg/sameChurch` guard on the update path.
- **Impact:** Cross-church moderators can dismiss or escalate reports for communities they have no authority over. A compromised moderator account can interfere with pending safety escalations (including CSAM-tier items) across the entire platform.
- **Remediation:** Add context scoping to the `moderationQueue` update rule: `allow update: if hasAnyClaimRole([...]) && (isAdminSDK() || sameOrg(resource.data.get('orgId','')) || sameChurch(resource.data.get('churchId','')))`. `executive_admin` can retain cross-context access.
- **Status:** OPEN

---

### [HIGH] legalHolds collection does not exist in the rules — no Firestore protection for legal hold objects

- **Location:** `AMENAPP/firestore.deploy.rules` — no `match /legalHolds/` block exists
- **Threat Vector:** There is no `legalHolds` collection rule anywhere in the deployed rules file. If the collection were ever accidentally created with wrong default rules during a refactor, data in it would be exposed.
- **Impact:** No enforceable `legalReviewer`-claim gate protecting legal hold documents. Legal hold content could be exposed to normal moderators or deleted without restriction.
- **Remediation:** Add a `legalHolds` collection rule: `allow read: if hasClaimRole('legalReviewer') || hasClaimRole('executive_admin'); allow create, update, delete: if false; // CF Admin SDK only`. Define and mint the `legalReviewer` custom claim in the CF auth layer.
- **Status:** OPEN

---

### [HIGH] one_users/witnesses subcollection: allow write: if isSignedIn() — any authenticated user can write a witness document under any UID

- **Location:** `AMENAPP/firestore.deploy.rules` lines 1556–1562: `allow write: if isSignedIn()`
- **Threat Vector:** Any signed-in user can create, update, or delete a witness document under any other user's UID path. The comment says "CF validates both-party acceptance" but the rule allows the write before the CF runs. An attacker can fabricate or delete witness relationships for any user.
- **Impact:** Witness relationships can be created or destroyed by any signed-in user. An attacker could silently insert themselves as a witness for a minor user, or delete protective witness relationships.
- **Remediation:** Restrict client witness writes to: `allow create: if request.auth.uid == uid && request.resource.data.witnessUID == request.auth.uid`. All cross-party acceptance must remain CF-only. `allow update, delete: if false; // CF only`.
- **Status:** OPEN

---

### [HIGH] users/{userId}: any signed-in user can read the full user document — no field-level privacy for sensitive profile fields

- **Location:** `AMENAPP/firestore.deploy.rules` lines 313–314: `allow read: if isSignedIn()`
- **Threat Vector:** Any authenticated user can `getDocument()` on any other user's `/users/{userId}` document. If the user document contains sensitive fields (phone number, birthYear, ageTier, churchId), those fields are readable by all authenticated users. An attacker can enumerate minors by querying `ageTier` in `['blocked','tierB','tierC']` against the users collection.
- **Impact:** Leaks `ageTier` (revealing minor status) and any other sensitive field stored on the users document to all authenticated users.
- **Remediation:** Separate public profile fields from private fields: create a `/users/{userId}/private/profile` subcollection for sensitive data. The `ageTier` field used by `isMinorAccount()` should be read from the private subcollection rather than the top-level document.
- **Status:** OPEN

---

### [HIGH] Download URL returned to client before moderation for post_media and profilePhotos

- **Location:** `AMENAPP/CloudStorageService.swift` lines 69–85; `AMENAPP/BereanSnapService.swift` lines 113–124; `functions/postAndCommentFunctions.js` lines 477–481
- **Threat Vector:** `CloudStorageService.uploadMedia()` calls `storageRef.downloadURL()` immediately on upload success and stores the result in the Firestore post document before the `moderateUploadedImage` CF has completed its checks. On a platform serving minors, any inappropriate media uploaded is accessible to followers during the moderation latency window.
- **Impact:** If the image CF is experiencing cold-start delays, the window can be minutes. The NCMEC mandatory reporting requirement is also implicated: the URL is already distributed before it can be withheld.
- **Remediation:** Do not write the public download URL to Firestore until the moderation CF has approved the file. Pattern: (1) client uploads to quarantine path; (2) post draft written with `mediaProcessingStatus: 'pending'` and no public URL; (3) moderation CF moves approved file and writes URL back; (4) post becomes visible only after the CF write.
- **Status:** OPEN

---

### [HIGH] Users can overwrite quarantine files mid-moderation (race condition — moderation evasion)

- **Location:** `storage.rules` lines 123–135
- **Threat Vector:** A user could upload a file with a `mediaId` that collides with a file currently in review, overwriting evidence before the CF has moved it to `approved/` or `blocked/`. This allows a user to evade moderation by substituting a benign file after initial upload triggers the CF, then re-uploading the offending content.
- **Impact:** Real race condition on a platform subject to NCMEC reporting. The window is narrow but exploitable.
- **Remediation:** Generate `mediaId` server-side or use a CF-issued upload token. Alternatively, prohibit update on quarantine paths (`allow create` only, no `update`). Add a Firestore companion document written by the CF when scanning begins, and check its existence before allowing an overwrite.
- **Status:** OPEN

---

### [HIGH] chat_videos path bypasses moderation pipeline entirely — no MIME type or size enforcement

- **Location:** `AMENAPP/VideoAttachmentHandler.swift` lines 141–153; `storage.rules` lines 252–256
- **Threat Vector:** `VideoAttachmentHandler.swift` uploads DM videos directly to `chat_videos/{conversationId}/{filename}` with only client-side metadata. There is no Storage rule for this path, no size limit, no MIME validation at the Storage rules layer, and no moderation CF configured to scan this path. Since minor users can participate in DMs, this is a direct child safety risk.
- **Impact:** Any authenticated user can upload arbitrarily large files or malicious content to DM paths readable by all conversation participants. CSAM or NCMEC-reportable content in DMs bypasses all automated scanning.
- **Remediation:** Add an explicit Storage rule for `chat_videos/{conversationId}/{filename}` that: (1) verifies the uploader is a conversation participant via Firestore lookup; (2) enforces `video/mp4` or `video/quicktime` MIME type; (3) enforces a 100 MB size cap; (4) restricts reads to conversation participants. Extend or add a video scanning CF to cover this path.
- **Status:** OPEN

---

### [HIGH] isBlockedType() allowlist is incomplete — many dangerous MIME types not blocked

- **Location:** `storage.rules` lines 44–48
- **Threat Vector:** `isBlockedType()` only explicitly blocks `application/x-executable`, `text/html`, and `application/javascript`. It does not block `.sh`, `.py`, `.zip`, `.apk`, `.exe`, `.dll`, `application/octet-stream`, and many others. The legacy `isImageType()`/`isVideoType()` helpers use `.matches()` regex which could be bypassed by crafted content-type headers.
- **Impact:** If `isBlockedType()` is ever used standalone on a new path, the incomplete allowlist would allow dangerous file types through. Legacy helper function regex can be bypassed on `churchNotes` paths.
- **Remediation:** Replace all uses of legacy `isImageType()`/`isVideoType()`/`isAudioType()` with explicit allowlist variants. Remove `isBlockedType()` entirely — rely only on explicit allowlists, as denylists are inherently incomplete.
- **Status:** OPEN

---

### [HIGH] Non-atomic writes in moderateUGC.js — snap.ref.update() and moderationQueue.add() are separate awaits

- **Location:** `functions/moderateUGC.js` lines 183–217, 270–307, 350–385 (all three UGC trigger functions)
- **Threat Vector:** In all three UGC triggers, the content visibility update and `moderationQueue.add()` are separate awaited operations. If the CF crashes or times out between the two writes, the content document is updated (hidden) but no queue entry is created. An admin has no record to act on and the user's content is invisibly stuck hidden with no appeal path. `moderatePost.js` uses `db.batch()` combining both writes atomically.
- **Impact:** Content can be permanently hidden with no corresponding `moderationQueue` entry, causing silent content loss with no admin visibility and no user appeal path. For minor users, self-harm prayer requests could be hidden but not escalated.
- **Remediation:** Refactor all three trigger functions in `moderateUGC.js` to use `db.batch()` combining `snap.ref.update` and `moderationQueue.add`, matching the pattern in `moderatePost.js` lines 360–390.
- **Status:** OPEN

---

### [HIGH] Comments (posts/{postId}/comments/{commentId}) have no server-side NeMo Guard trigger

- **Location:** `functions/moderateUGC.js`; `functions/moderatePost.js` (absence of any `onCreate` trigger matching `posts/{postId}/comments/{commentId}`)
- **Threat Vector:** `moderatePost.js` only triggers on `posts/{postId}` onCreate. `moderateUGC.js` covers sanctuaries, prayers, and DMs — but not comments. The `checkCommentQuality` callable in `commentGateway.js` is a client-side opt-in. A user who writes directly to Firestore (bypassing the iOS app) can post comments without any NLP safety check.
- **Impact:** Comments on posts are not server-side moderated. Direct Firestore writes containing CSAM text, grooming language, or violent content publish immediately and remain visible until a human reports them.
- **Remediation:** Add a `moderateComment` Firestore `onCreate` trigger listening on `posts/{postId}/comments/{commentId}` with the same NeMo Guard pipeline as `moderatePost.js`, including fail-closed behaviour and self-harm escalation.
- **Status:** OPEN

---

### [HIGH] Image-only DMs are hidden but not enqueued — moderateDMMessage skips moderationQueue for no-text messages

- **Location:** `functions/moderateUGC.js` lines 322–331
- **Threat Vector:** When a DM message has no text, `moderateDMMessage` sets `visible: false` and returns immediately without adding a `moderationQueue` entry. The code comment explicitly states "NOT enqueued separately". An admin reviewing the moderation queue has no record of the image-only DM and cannot approve or reject it. The DM stays hidden indefinitely.
- **Impact:** Image-only DMs sent to minors are invisible to the moderation team. There is no escalation path, no TTL, and no dead-letter record. This is particularly dangerous for grooming scenarios.
- **Remediation:** Add a `moderationQueue` entry in the `!text` branch of `moderateDMMessage` with `imageReviewRequired: true` and a link to the Storage path so `imageModeration` results can be correlated.
- **Status:** OPEN

---

### [HIGH] Server-Side DM Minor Gate Has Age-Unknown Fail-Open — Unknown-Age Users Can DM Minors

- **Location:** `functions/safety/minorProtection.js` lines 155–175
- **Threat Vector:** `checkAdultMinorInteraction()` explicitly allows the interaction when either party's age is unknown (`senderIsMinor === null` or `recipientIsMinor === null`), with only a `requiresReview` flag set. Since `ageTier` may not yet be set at account creation time (the `onUserDocCreated` trigger is asynchronous), there is a race window where a freshly created account can DM a minor.
- **Impact:** During the race window between account creation and `ageTier` computation, a new account has null age status and can DM minors with no block. The `requiresReview` flag goes to `moderationQueue` but the message is already delivered.
- **Remediation:** (1) Change fail-open to fail-closed for unknown age: if either party's age cannot be confirmed as adult, treat as minor for DM gating. (2) Set `ageTier` to `'blocked'` synchronously at account creation so there is no null window. (3) Ensure the client-written document defaults `ageTier` to `'blocked'` before the CF overwrites.
- **Status:** OPEN

---

### [HIGH] AmenRBACService.allowDM() Always Returns True for Adults Contacting Minors — No Enforcement

- **Location:** `AMENAPP/AMENAPP/CommunityOS/Identity/AmenRBACService.swift` lines 290–302
- **Threat Vector:** The `allowDM()` method contains the comment "Non-minor cannot DM a minor unless they are a church leader with verified parental consent" but returns `true` unconditionally for all non-visitor roles. If the CF callable is not called before a conversation document is created via a direct Firestore write, no check fires.
- **Impact:** The iOS-side DM guard is a no-op for adult-to-minor interactions. All protection relies solely on Firestore rules and the `minorProtection.js` CF — neither of which are called for all write paths.
- **Remediation:** (1) Implement the adult-to-minor check in `allowDM()` by actually querying `isMinorAccount()` before returning `true`. (2) Verify all conversation creation paths go through a CF callable that calls `checkAdultMinorInteraction()`. (3) Add an integration test verifying an adult cannot create a conversation with a minor directly via Firestore write.
- **Status:** OPEN

---

### [HIGH] Minors Not Hidden From Algolia People Search by Default — Discovery Gap

- **Location:** `AMENAPP/AlgoliaSyncService.swift` lines 224–295, 351–356
- **Threat Vector:** `shouldExcludeFromPeopleIndex()` correctly excludes known minors from bulk Algolia sync but is a batch-sync gate only. If the incremental sync path does not call the same gate, newly registered minors appear in Algolia search until the next bulk sync.
- **Impact:** Minor profiles that bypass the exclusion gate appear in public Algolia people search, allowing strangers to discover and contact minors.
- **Remediation:** (1) Audit every Algolia sync path to confirm `shouldExcludeFromPeopleIndex()` is called. (2) Add a Firestore `onDocumentWritten` trigger that removes a user from the Algolia index when `ageTier` is set to a minor tier. (3) Add a facet filter for `isMinor == false` on all public people-search queries as defense-in-depth.
- **Status:** OPEN

---

### [HIGH] Adults Can Create 1:1 Spaces With Minors — Private Space Gate Not Enforced

- **Location:** `AMENAPP/firestore.deploy.rules` lines 878–924
- **Threat Vector:** There is no rule blocking an adult from creating a private space and inviting a specific minor as a member. An adult with leader/pastor/owner role can create a private space, add a minor as a member via the admin-role path, and then use space messages to communicate outside the DM mutual-follow gate.
- **Impact:** Private spaces become a vector to bypass the DM minor-safety gate. Space messages have no minor-safety mutual-follow check in the rules.
- **Remediation:** (1) Add a Firestore rule: when adding a member where `isMinor(memberUid)` is true, require `churchVerified == true` for the space. (2) Apply the `minorSafeDM` mutual-follow check to space messages when a minor is a member. (3) Add CF validation: if `minorCount > 0` in a space with < 3 members, require church verification and guardian consent. (4) Alert when any adult creates a private space with only themselves and one minor.
- **Status:** OPEN

---

### [HIGH] backfillUsernameLookup missing admin-claim check — any authenticated user can enumerate all UIDs

- **Location:** `functions/authenticationHelpers.js` lines 428–465 (line 435–437)
- **Threat Vector:** Authenticated (non-admin) callers can invoke `backfillUsernameLookup`. The function checks only `request.auth?.uid` (must be non-null) but performs no admin-claim validation. It then reads every document in the `users` collection and bulk-writes to `usernameLookup`, leaking all UIDs.
- **Impact:** Any signed-in user can trigger a full user-collection scan, exposing all UIDs and their usernames. This constitutes a user-enumeration attack surface.
- **Remediation:** Add the same admin-claim guard used by `setAdminClaim` and `banUserPhone`: `if (!request.auth || request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Admin only.');`
- **Status:** OPEN

---

### [HIGH] Legacy stripeWebhook.js does not use defineSecret — secrets referenced via process.env only

- **Location:** `functions/stripeWebhook.js` lines 1, 26–27, 100–112
- **Threat Vector:** The root-level `stripeWebhook.js` reads `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` via raw `process.env` using the Gen1 `runWith({ secrets: [...] })` pattern. The canonical hardened version in `functions/stripe/stripeWebhook.js` correctly uses `defineSecret()`, but the legacy file remains deployed alongside it. Legacy handlers also lack idempotency guards.
- **Impact:** Gen1 `runWith` secrets have weaker isolation than Gen2 `defineSecret`. Duplicate Stripe deliveries can re-apply subscription changes, potentially toggling a user's tier.
- **Remediation:** Remove the legacy `stripeWebhook.js` and route all Stripe webhook traffic through `functions/stripe/stripeWebhook.js`. Remove the duplicate export in `stripeFunctions.js`.
- **Status:** OPEN

---

### [HIGH] finalizePostPublish and toggleReaction lack App Check enforcement

- **Location:** `functions/postAndCommentFunctions.js` lines 76, 311
- **Threat Vector:** `finalizePostPublish` and `toggleReaction` are declared as `onCall({ region: REGION })` with no `enforceAppCheck: true`. Any script that obtains a valid Firebase ID token can call these endpoints directly, bypassing App Check attestation that guards adjacent functions.
- **Impact:** Automated scripts can post unlimited content or flood reaction counts without a real iOS client, undermining feed integrity and rate-limit controls.
- **Remediation:** Add `enforceAppCheck: true` to both function declarations to match the security posture of `addComment`.
- **Status:** OPEN

---

### [HIGH] Large cluster of Berean OS and Selah Cloud Functions have App Check disabled

- **Location:** `functions/berean_os_*.js`, `functions/selah/discernmentEngine.js`, `functions/creatorDraftFunctions.js`
- **Threat Vector:** 33+ callable Cloud Functions across `berean_os_sources.js`, `berean_os_graph.js`, `berean_os_projects.js`, `berean_os_documents.js`, `berean_os_advisory.js`, `berean_os_research.js`, `berean_os_wisdom.js`, `berean_os_memory.js`, `berean_os_mentor.js`, `berean_os_debate.js`, `selah/discernmentEngine.js`, and `creatorDraftFunctions.js` all declare `enforceAppCheck: false`.
- **Impact:** These functions call expensive AI models (Anthropic, NVIDIA, OpenAI). Without App Check, any automated client can hammer them freely — incurring large AI cost bills, bypassing entitlement gates, and potentially extracting AI system-prompt context.
- **Remediation:** Enable `enforceAppCheck: true` in all production deployments. Use the Firebase Emulator exemption pattern (`process.env.FUNCTIONS_EMULATOR`) for local development rather than setting globally to false.
- **Status:** OPEN

---

### [HIGH] NCMEC CyberTipline integration has hardcoded TODO placeholder credentials

- **Location:** `functions/moderation/cyberTiplineInterface.js` lines 99–101
- **Threat Vector:** The CSAM mandatory reporting module contains `espId: 'TODO_ESP_ID'` and `espApiKey: 'TODO_ESP_API_KEY'` as literal placeholder strings. No HTTP call is made to the NCMEC CyberTipline API. This duplicates and deepens the non-functional stub finding in `ncmecReporter.js`.
- **Impact:** 18 U.S.C. § 2258A requires ESP platforms to submit CyberTip reports within 60 days of detection. Placeholder credential strings in source code confirm no live NCMEC integration exists.
- **Remediation:** Complete NCMEC ESP registration, store credentials in Firebase Secret Manager via `defineSecret('NCMEC_ESP_ID')` and `defineSecret('NCMEC_ESP_API_KEY')`, and implement the live HTTPS POST. Remove all `TODO_*` placeholder strings.
- **Status:** OPEN

---

### [MEDIUM] whatsNewStories has allow read: if true — unauthenticated read for all story content

- **Location:** `AMENAPP/firestore.deploy.rules` line 2226
- **Threat Vector:** `/whatsNewStories/{storyId}` allows unauthenticated read. Any person can read all `whatsNewStories` documents without signing in. If any story document contains user data, UIDs, or feature flag state, that information is publicly disclosed.
- **Impact:** Potential data leakage from story documents to unauthenticated crawlers and OSINT tooling.
- **Remediation:** Change to `allow read: if isSignedIn()`. If SEO-indexed public content is intentional, ensure story documents contain only sanitized marketing copy with no user references.
- **Status:** OPEN

---

### [MEDIUM] entitlements/catalog subcollection has no explicit rule — write protection relies solely on catch-all

- **Location:** `AMENAPP/firestore.deploy.rules` lines 1818–1822
- **Threat Vector:** The `hasPaidAccess()` function reads `/users/{request.auth.uid}/entitlements/catalog` but there is no explicit rule for the `entitlements` subcollection. If the catch-all is ever modified or a permissive rule added higher in the tree, entitlement documents could become client-writable, allowing users to self-grant paid plan access.
- **Impact:** Currently safe (falls to catch-all deny). Future rule refactors could inadvertently expose the entitlement write path.
- **Remediation:** Add an explicit entitlements subcollection rule: `allow read: if isOwner(userId); allow create, update, delete: if false; // CF StoreKit validation only`. This codifies the server-only write invariant in the contract.
- **Status:** OPEN

---

### [MEDIUM] users/{userId}/actions subcollection: open update/delete for owner — no field-validation or soft-delete enforcement

- **Location:** `AMENAPP/firestore.deploy.rules` lines 467–474
- **Threat Vector:** The create path enforces a type allowlist, but the update path has no field restrictions — an owner can update any field after creation, including `type`. The delete path allows hard deletes, inconsistent with the I-1 soft-delete invariant stated in the rules.
- **Impact:** Users can hard-delete their own action/reminder objects and change action type to any value after creation.
- **Remediation:** Add field protection to the update path restricting to editable fields only (e.g. `title`, `notes`, `scheduledAt`, `completedAt`) and blocking `type` and `provenance`. Change `allow delete` to `if false` and implement soft-delete via a `deletedAt` field update.
- **Status:** OPEN

---

### [MEDIUM] Size and type validation missing for user-submitted text fields across posts, comments, and discussions

- **Location:** `AMENAPP/firestore.deploy.rules` — match `/posts/{postId}` create/update, `/discussions/{discussionId}/messages/{messageId}` create, `/posts/{postId}/comments/{commentId}` create
- **Threat Vector:** Create and update rules for posts, comments, and discussion messages do not enforce maximum string length or require specific field types. A user can submit an arbitrarily large document (Firestore's 1 MB document limit is the only brake), causing disproportionate storage costs, search index bloat, and potential DoS against CF triggers.
- **Impact:** Storage abuse, CF trigger DoS, and downstream processing errors when non-string fields are passed to text moderation pipelines.
- **Remediation:** Add size guards: `request.resource.data.get('body','') is string && request.resource.data.get('body','').size() <= 5000`. Enforce required fields via `request.resource.data.keys().hasAll([...])`. Apply to comments and discussion messages.
- **Status:** OPEN

---

### [MEDIUM] Owner can delete quarantine files under legal hold with no server-side check

- **Location:** `storage.rules` line 134; `AMENAPP/CloudStorageService.swift` lines 128–135
- **Threat Vector:** The Storage rule `allow delete: if isOwner(uid)` on quarantine paths does not consult Firestore to check whether a legal hold flag exists. An offending user could delete a quarantine file during the moderation window before the CF has moved it to `legalHold/`, destroying evidence.
- **Impact:** A user flagged for CSAM or grooming content could delete their quarantine upload before the moderation CF processes it, destroying evidence and breaking the NCMEC mandatory reporting pipeline. This is a legal compliance risk under 18 U.S.C. § 2258A.
- **Remediation:** Add a Firestore lookup in the Storage delete rule for quarantine paths: check that no document in `ncmecReports` or `moderationQueue` with `legalHold: true` references this `mediaId`. Alternatively, have the moderation CF immediately move files that trigger a CSAM hit to `uploads/legalHold/` (where `delete: if false`) before any client-side delete can execute.
- **Status:** OPEN

---

### [MEDIUM] No separate storage paths or rules for sanctuary/prayer-room media

- **Location:** `storage.rules`; `functions/imageModeration.js` lines 65–70
- **Threat Vector:** The app has a sanctuary/prayer-room feature with distinct trust requirements, but all user-generated media flows through generic `post_media` or `chat_videos` paths. Prayer room audio/video would only be scanned if it matches `image/*` content type; video and audio in prayer rooms receive no automated scanning.
- **Impact:** A malicious user could upload inappropriate video or audio to a prayer room and it would not be scanned. Minor users in prayer rooms are exposed to unscanned audio/video content.
- **Remediation:** Define separate storage paths for sanctuary media (e.g. `sanctuary/{sanctuaryId}/media/{filename}`) with explicit rules, tighter MIME allowlists, and participant-only reads. Extend the moderation pipeline to cover audio and video files.
- **Status:** OPEN

---

### [MEDIUM] moderateUGC.js retryHelper withRetry is not the same implementation as moderatePost.js fetchWithRetry — no exponential backoff on HTTP-level errors

- **Location:** `functions/moderateUGC.js` lines 27–39
- **Threat Vector:** The `retryHelper.withRetry` used by `moderateUGC.js` retries only on thrown exceptions with a fixed 500ms base delay. `moderatePost.js fetchWithRetry` uses exponential backoff and explicitly checks for HTTP 429/5xx before retrying. Under NIM load, `moderateUGC` triggers exhaust faster and produce more false-pending outcomes.
- **Impact:** Higher rate of unnecessary pending queue items during NIM congestion. Increased admin review burden and longer content hide windows.
- **Remediation:** Extract `fetchWithRetry` from `moderatePost.js` into a shared `retryHelper.js` export, replacing `withRetry` for all NIM callers. Add status-code-aware retry logic with exponential backoff.
- **Status:** OPEN

---

### [MEDIUM] Dead-letter collection missing from moderateUGC.js, moderationGateway.js, and contentModerationTriggers.js

- **Location:** `functions/moderateUGC.js`; `functions/moderationGateway.js`; `functions/contentModerationTriggers.js`
- **Threat Vector:** `moderatePost.js` writes to `moderationDeadLetter` when retries are exhausted. None of the other moderation triggers or the `checkContentSafety` callable do the same. Permanently failed moderation attempts disappear into Cloud Function logs with no Firestore record.
- **Impact:** Operations team cannot distinguish between `'pending because of admin review'` and `'pending because NIM permanently failed'`. Content may be stuck hidden with no recovery mechanism.
- **Remediation:** After retry exhaustion in `moderateUGC.js` and `contentModerationTriggers.js`, write to `moderationDeadLetter`. Add a periodic sweep of this collection to the existing `moderationSweep` Cloud Function.
- **Status:** OPEN

---

### [MEDIUM] policyVersion field is absent from moderateUGC.js moderation subdocuments and moderationQueue entries

- **Location:** `functions/moderateUGC.js` lines 183–217, 270–307, 350–385
- **Threat Vector:** `moderatePost.js` stamps `policyVersion: POLICY_VERSION ('amen-safety-v1')` on every moderation subdocument and audit log entry. `moderateUGC.js` does not write `policyVersion` to either the content document's moderation subdocument or the `moderationQueue` entries.
- **Impact:** Inability to scope a retroactive policy re-review to a specific content type or time window. Compliance and COPPA audit obligations are harder to demonstrate.
- **Remediation:** Define `POLICY_VERSION` in `moderateUGC.js` (or import from a shared constants module) and include it in all moderation subdocument writes and `moderationQueue` entries.
- **Status:** OPEN

---

### [MEDIUM] Exact birth year stored in Firestore user document — queryable by any client

- **Location:** `functions/authenticationHelpers.js` lines 1152–1159; `AMENAPP/firestore.deploy.rules` lines 311–329
- **Threat Vector:** The `updateBirthYear` CF writes `birthYear` (an exact year) back to the public `/users/{uid}` document. Any authenticated user can read any user's `birthYear` field. Predators can enumerate minors by querying `birthYear`.
- **Impact:** Any authenticated user can enumerate `birthYear` for any other user. For minor users, this confirms approximate age to potential predators.
- **Remediation:** (1) Move `birthYear` to the `/users/{uid}/private/age_assurance` subcollection (owner-read-only). (2) Store only the computed `ageTier` in the top-level user document, not the raw `birthYear`. (3) Consider masking `ageTier` from non-owner reads, exposing only a boolean `isMinor` flag with restricted access.
- **Status:** OPEN

---

### [MEDIUM] Guardian linking workflow has no email verification CF — link remains perpetually pending

- **Location:** `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` lines 210–243; `AmenChildSafetyModels.swift` lines 109–132
- **Threat Vector:** `requestGuardianLink()` writes a pending guardian link request and notes "A Cloud Function (onDocumentCreated on /guardianLinkRequests) handles sending the verification email." No CF implementing this trigger was found. The link never completes; `guardianLinked` stays `false`; the safety pipeline treats all minors as having no guardian oversight.
- **Impact:** The guardian oversight system is non-functional. No guardian ever receives a verification email. The `_hasApprovedRelationship()` check in `minorProtection.js` will always return `false` for all users.
- **Remediation:** (1) Implement the `onDocumentCreated` Cloud Function for `/guardianLinkRequests` that sends a verification email. (2) Implement the email verification landing page/deep link that calls Admin SDK to complete the link. (3) Until the CF exists, do not allow any DMs involving minors at all.
- **Status:** OPEN

---

### [MEDIUM] addComment does not check Firebase Auth disabled flag — banned users can comment for up to 1 hour

- **Location:** `functions/postAndCommentFunctions.js` lines 150–280
- **Threat Vector:** When a user is banned, `banUserPhone` calls `admin.auth().updateUser(userId, {disabled: true})` and `revokeRefreshTokens(uid)`. However, an existing Firebase ID token remains valid for up to 1 hour. `addComment` only checks `request.auth` (token present), not whether the underlying account is disabled or `accountStatus` is `banned`.
- **Impact:** A banned user holding a valid ID token can continue commenting for up to 60 minutes after the ban is applied.
- **Remediation:** In `addComment` (and `finalizePostPublish`), add a server-side check: read `user_trust/{uid}` and throw `permission-denied` if `accountStatus` is `banned` or `suspended`. Alternatively, verify `admin.auth().getUser(uid).disabled` before proceeding.
- **Status:** OPEN

---

### [MEDIUM] safeMessagingGateway.js ban check relies on stale isBanned field

- **Location:** `functions/safeMessagingGateway.js` line 585
- **Threat Vector:** `safeMessagingGateway.js` checks `senderData.isBanned` on the Firestore user document. This field can be stale (written by an async ban flow) and is inconsistent with the canonical ban authority (`admin.auth().disabled` and `user_trust/{uid}.accountStatus`).
- **Impact:** A banned user whose Firestore `isBanned` field has not yet propagated can send direct messages during the propagation window.
- **Remediation:** Use `admin.auth().getUser(uid)` to check `disabled: true` as the authoritative ban signal, supplemented by a Firestore `user_trust/{uid}` read. Remove reliance on the potentially-stale `isBanned` field.
- **Status:** OPEN

---

### [MEDIUM] Legacy stripeWebhook.js handlers have no idempotency — duplicate Stripe events can re-apply subscription changes

- **Location:** `functions/stripeWebhook.js` lines 100–143
- **Threat Vector:** `handleSubscriptionUpdated` and `handleSubscriptionDeleted` in the legacy `stripeWebhook.js` accept `_eventId` but never store it in `processedStripeEvents` or any idempotency collection. Stripe may re-deliver webhooks, causing the subscription update to run again. The canonical `stripe/stripeWebhook.js` has this fixed via `isAlreadyProcessed`/`markProcessed`.
- **Impact:** Duplicate delivery of a `customer.subscription.deleted` event can erroneously cancel an active subscription.
- **Remediation:** Remove the legacy `stripeWebhook.js` and route all traffic to `stripe/stripeWebhook.js`, or add `processedStripeEvents` idempotency guard to the legacy file while migration is in progress.
- **Status:** OPEN

---

### [MEDIUM] AmenRBACService.check() is iOS client-side only — no server-side RBAC enforcement on CF mutations

- **Location:** `AMENAPP/AMENAPP/CommunityOS/Identity/AmenRBACService.swift` lines 176–244 (lines 186–244)
- **Threat Vector:** The `AmenRBACService` C5 matrix is a client-side Swift class. A malicious user can bypass it entirely by calling Cloud Functions directly with a valid Firebase ID token. Unless Cloud Functions re-check the caller's role from Firestore before executing, the RBAC is purely advisory.
- **Impact:** Organization/church resource mutations may be executable by callers with insufficient roles if the backing Cloud Functions do not independently verify the caller's role.
- **Remediation:** Audit every Cloud Function that mutates org/church/space resources to ensure it reads the caller's role from `roles/{contextType}/{contextId}/members/{uid}` and enforces the C5 matrix server-side. Client-side RBAC should be treated as a UX convenience, not a security control.
- **Status:** OPEN

---

### [LOW] Duplicate moderateContent export — aiModeration.moderateContent shadows contentModeration.moderateContent in index.js

- **Location:** `functions/index.js` lines 167 and 300
- **Threat Vector:** `index.js` exports `moderateContent` twice: first from `./contentModeration` (line 167) and then from `./aiModeration` (line 300). The second assignment silently overwrites the first. If `aiModeration.js` uses a different failure mode or toxicity threshold, the deployed behaviour is not what this audit reviewed.
- **Impact:** Potential silent substitution of the moderation callable with an unreviewed implementation.
- **Remediation:** Remove the duplicate export. Decide which module owns the `moderateContent` callable and export only that one. If both are needed, rename one (e.g., `moderateContentLegacy` vs `moderateContentAI`).
- **Status:** OPEN

---

### [LOW] resolveUsernameToEmail remains deployed alongside signInWithUsername — email PII exposed to the client

- **Location:** `functions/authenticationHelpers.js` lines 240, 318
- **Threat Vector:** `resolveUsernameToEmail` returns `{ email: userRecord.email }` to any caller who knows a valid username, allowing systematic email harvesting. `signInWithUsername` was built to replace it but the old function is still exported and callable.
- **Impact:** Attackers can enumerate usernames and harvest email addresses, enabling phishing campaigns targeting Amen users.
- **Remediation:** Migrate all iOS client call sites from `resolveUsernameToEmail` to `signInWithUsername`, then remove or revoke the `resolveUsernameToEmail` export.
- **Status:** OPEN

---

### [LOW] Phone auth rate-limit functions use Gen1 runWith pattern without defineSecret migration

- **Location:** `functions/phoneAuthRateLimit.js` (file-level)
- **Threat Vector:** Phone auth rate-limit functions still use Gen1 `runWith` per the `// TODO: MIGRATE_TO_V2` comment pattern. Gen1 functions do not benefit from the stronger process isolation of Gen2 Cloud Run containers.
- **Impact:** Lower isolation for functions handling phone number hashes.
- **Remediation:** Migrate to Firebase Functions v2 (`onCall` from `firebase-functions/v2/https`) with `defineSecret` for any secrets used.
- **Status:** OPEN

---

## Open Questions

These items require decisions by engineering, legal, product, or trust-and-safety leadership before the audit can be closed.

1. Which file is actually deployed to production — `firestore.deploy.rules` (in `AMENAPP/`) or `firestore.rules` (at root)? The `firebase.json` comment says to change the `'firestore.rules'` field before deploying. The `safety-hardening` branch has both files modified, but they have diverged — the `safetyAuditLog`/`guardianLinkRequests` gap exists in `firestore.deploy.rules` but NOT `firestore.rules`.

2. Has the `moderationQueue 'allow create: if isAdminSDK()'` restriction been tested end-to-end with actual iOS clients? The silently-failing `try?` calls in `AmenChildSafetyService`, `AmenModerationService`, and `AntiHarassmentEngine` mean no runtime error surfaces — this failure mode may have gone undetected.

3. Is the `'legalReviewer'` custom claim defined anywhere in the Cloud Functions auth layer? The `legalHolds` collection gap requires both a Firestore rule and a custom claim definition in the CF token-minting flow.

4. Does any Cloud Function read fields from `/users/{userId}` (e.g. `ageTier`, `churchId`, `isMinor`) to make trust or authorization decisions? If so, the unrestricted any-signed-in-user read on that collection means those decision inputs are also readable by other users — an adversary can read another user's `ageTier` to learn their minor status.

5. The `one_users/witnesses` subcollection comment says "CF validates both-party acceptance" but no CF callable is named. Which CF is expected to run, and does it actually enforce the constraint before the Firestore write or only after?

6. The OPEN-5 flag (unauthenticated read of public posts) is acknowledged in the rules header but left as default-open. Has a product decision been made about whether SEO-driven unauthenticated reads are intentional? This affects both privacy posture and COPPA risk (minors' public posts are readable without account).

7. Are there any collections written by the `MusicContentLayer` (`RightsMonetizationService`, `FaithMusicGraphService`, `AmenPulseDigestService`) that are not yet covered by Firestore rules? The git status shows those files modified on the `safety-hardening` branch and they likely write to music-specific collections.

8. Is `storage.rules` actually deployed to production, or is the project still running on default permissive rules? Running `firebase deploy --only storage --dry-run` would confirm. Several iOS upload paths (`post_media`, `chat_videos`, `profile_images`) are absent from `storage.rules` and would be silently denied if the hardened rules are live — implying either these features are broken in production or the rules have not been deployed.

9. What is the latency between a file being uploaded to `profilePhotos/` and the `moderateUploadedImage` CF completing its SafeSearch check? If this window exceeds 5 seconds under normal load, a CDN may cache the public URL before removal, making deletion insufficient.

10. The NCMEC submission pipeline is gated on `NCMEC_SUBMISSION_ENABLED === 'true'` (`ncmecReporter.js` line 39). Is this environment variable set to `'true'` in production? If not, the app is collecting `ncmecReports` but never submitting to NCMEC, which may violate 18 U.S.C. § 2258A once the platform reaches the threshold of "a provider of electronic communication service to the public."

11. The `isGuardianApprovedContact()` function returns `true` (allow) when the guardian approval document does not exist, and OPEN-2 remains unresolved. Has a T&S Lead decision been made on guardian approval scope? Without this, the guardian approval check is a no-op for all minor DMs.

12. The `chat_videos` path is used for DM video uploads but has no Storage rule. Who has write access to `chat_videos/{conversationId}/`? If any authenticated user can write to any `conversationId`, non-participants can inject media into other users' conversations.

13. The legacy `users/{uid}/profileImages/{filename}` path uses `allow read: if isSignedIn()` while the newer `profilePhotos/{uid}/{photoId}` path uses `allow read: if true` (unauthenticated). Is the legacy path still actively used? If so, the two paths have inconsistent access models for profile images.

14. Does `withRetry` in `retryHelper.js` inspect HTTP status codes (429/5xx) or only caught exceptions? If only exceptions, the retry gap between `moderatePost.js` and `moderateUGC.js` is confirmed as a separate defect in `retryHelper.js`.

15. What does `aiModeration.moderateContent` (which overwrites the `contentModeration` export at `index.js` line 300) actually do? Does it also use the `!/unsafe/i.test` fallback pattern?

16. Is there any server-side moderation trigger on `posts/{postId}/comments/{commentId}` in a file not reviewed here (e.g. `Backend/functions/src/index.ts` or `v2functions.js`)? The audit found none in the `functions/` directory.

17. The `moderateDMMessage` trigger is Gen-1 (`firebase-functions/v1`). Is the Cloud Run quota exhaustion that forced other functions to v1 (e.g. `updateBirthYear`, `banUserPhone`) also affecting `moderateDMMessage` reliability?

18. Are Firestore security rules preventing direct client writes to `posts/{postId}/comments/{commentId}` without going through the `addComment` callable? If not, the comment moderation gap can be exploited without any server-side enforcement.

19. The NCMEC CyberTipline integration in `ncmecReporter.js` is invoked from `imageModeration.js` but the `moderatePost.js` child-safety escalation path sets `externalReport.submitted: false` with a `TODO` placeholder for `NCMEC_CYBERTIPLINE_TODO`. Has a real NCMEC API key been configured and tested end-to-end for text-detected CSAM?

20. Is there a Firestore TTL policy actually enabled on `moderationQueue.expireAt` and `moderationDeadLetter` in the Firebase Console? The code comments say "TTL policy should be enabled" but this requires a manual Firebase Console step that may not have been completed.

21. **OPEN-4 (unresolved):** Who is the designated SLA key holder for NCMEC submissions? What is the maximum acceptable time between CSAM detection and NCMEC filing? This must be defined and contractually enforced before any launch.

22. **OPEN-2 (unresolved):** Guardian tools scope — until this is defined and implemented, the guardian-approval DM gate is non-functional. What is the intended guardian permission model: read-only oversight, active approve/deny, or emergency-only access?

23. **OPEN-1 (unresolved):** Is the minimum age floor 13 (US COPPA) or 16 (GDPR-K for certain EU jurisdictions)? If the app will be available in the EU, GDPR-K compliance requires explicit parental consent for under-16 in some member states.

24. Is the `onDocumentCreated` Cloud Function for `/guardianLinkRequests` implemented anywhere not covered by this audit? If not, the entire guardian system is inert.

25. Does every incremental Algolia user-sync path (e.g. real-time profile updates) call `shouldExcludeFromPeopleIndex()`? Only the bulk sync path was confirmed to do so.

26. Is the CSAM detection pipeline (hash-matching or ML scan) actually deployed and producing `detectionSource` values of `'ios_hash_match'` or `'cf_vision_scan'`? The `prepareCSAMEscalation()` method exists but its callers were not found in this audit.

27. Is there a report/flag button present on every surface where minors can see content or be contacted? `SafetyReportingService.swift` exists but the audit did not confirm the button appears in all minor-visible surfaces (DMs, space messages, comments on public posts).

28. The `ageTier` field is written to the public `/users/{uid}` document by the CF. Is there a mechanism to prevent an admin with Firestore console access from manually setting `ageTier` to `'tierD'` for a minor, bypassing the I-8 invariant? The `allow update: if false` rule applies only to clients, not to the Firebase console or Admin SDK.

29. Is the legacy `stripeWebhook.js` (root-level) actually exported and deployed to production, or has it been superseded by `stripe/stripeWebhook.js`? The `stripeFunctions.js` import chain needs to be traced to confirm which file is live.

30. Have the 33+ Berean OS Cloud Functions with `enforceAppCheck: false` ever been deployed to production? The audit note says "App Check migration tracked separately per Trust OS audit" — what is the current status of that migration ticket?

31. Which Cloud Functions that mutate org/church/space resources (e.g. in `covenantFunctions.js`, `spacesLivekitFunctions.js`) perform a server-side RBAC role read before executing? This requires a function-by-function audit beyond the scope of this scan.

32. Has the NCMEC CyberTipline ESP agreement been initiated? The `TODO_ESP_ID` and `TODO_ESP_API_KEY` placeholders suggest registration has not been completed. What is the legal team's timeline?

33. Is `safeMessagingGateway.js` the sole DM-writing path, or can messages be written directly to Firestore by the client? If Firestore security rules do not block client writes to the messages collection, the `isBanned` check in the gateway is bypassable.

34. The `AmenRBACService.resolveRole` Firestore path (`roles/{contextType}/{contextId}/members/{uid}/membership`) uses a deep nested subcollection — is this the canonical path that Cloud Functions also read, or do CFs use a different schema?

35. Are Firebase App Check attestation tokens enforced in the Firebase project console (not just at the function level)? App Check can be bypassed if the project-level enforcement toggle is off even when individual functions declare `enforceAppCheck: true`.

---

## Action Checklist

### CRITICAL — Fix Immediately (Legal / Child Safety Blockers)

- [ ] **C-01:** Add Firestore rules for `safetyAuditLog`, `guardianLinkRequests`, and `guardianApprovedContacts` collections and deploy
- [ ] **C-02:** Route all iOS-originated `moderationQueue` creates through a CF callable (or extend the Firestore rule); verify end-to-end with a real iOS client
- [ ] **C-03:** Add field-level restrictions to `one_users` self-write rule; enumerate mutable fields and block all others
- [ ] **C-04:** Add `postModerationFieldsNotChanged()` guard to the posts owner update path in `firestore.deploy.rules`
- [ ] **C-05:** Add explicit Storage rules for all missing upload paths (`post_media`, `chat_videos`, `berean/ocr_queue`, `creator/users`, `profile_images`); deploy `storage.rules`
- [ ] **C-06:** Route `profilePhotos` uploads through the quarantine pipeline; change public read to authenticated-only until quarantine-first is live
- [ ] **C-07:** Fix NeMo Guard jailbreak in `moderateUGC.js` and `moderationGateway.js` — replace `!/unsafe/i.test(raw)` fallback with fail-closed exact-match logic
- [ ] **C-08:** Fix NIM 429/5xx retry gap in `moderateUGC.js` — inspect HTTP status codes before resolving; share `fetchWithRetry` from `moderatePost.js`
- [ ] **C-09:** Change `moderatePostText` catch block in `contentModeration.js` and `contentModerationTriggers.js` to fail closed (`visible: false`, `flaggedForReview: true`)
- [ ] **C-10:** Initiate NCMEC ESP registration; implement live HTTPS POST in `ncmecReporter.js` and `cyberTiplineInterface.js`; store credentials in Secret Manager; remove `TODO_*` placeholders
- [ ] **C-11:** Implement document-based or parental-consent age verification before granting adult or minor account capabilities; block self-reported-only registrations
- [ ] **C-12:** Invert `isGuardianApprovedContact()` to fail-closed; implement guardian link CF and treat OPEN-2 as a launch blocker
- [ ] **C-13:** Move CSAM content removal to a CF callable using Admin SDK; add Firestore rule to lock documents with `deletionReason == 'csam_escalation'` from client writes

### HIGH — Fix Before Beta Launch

- [ ] **H-01:** Add org/church context scoping to `moderationQueue` update rule; restrict `executive_admin` to platform-level items only
- [ ] **H-02:** Add `legalHolds` Firestore rule with `legalReviewer` claim gate; define and mint the claim in the CF auth layer
- [ ] **H-03:** Restrict `one_users/witnesses` client write to `allow create: if request.auth.uid == uid`; set `update`/`delete` to CF-only
- [ ] **H-04:** Move `birthYear`/`ageTier` to `/users/{uid}/private/` subcollection; update `isMinorAccount()` helper
- [ ] **H-05:** Implement pre-moderation URL gate for `post_media` and `profilePhotos` — do not return public download URL until CF approves
- [ ] **H-06:** Prohibit `update` on quarantine Storage paths; require server-side `mediaId` generation or CF-issued upload token
- [ ] **H-07:** Add explicit `chat_videos` Storage rule with participant check, MIME enforcement, size cap, and participant-only read
- [ ] **H-08:** Replace `isBlockedType()` denylist with explicit allowlist pattern on all `churchNotes` paths; deprecate legacy `isImageType()`/`isVideoType()` helpers
- [ ] **H-09:** Refactor all three `moderateUGC.js` trigger functions to use `db.batch()` for atomic content update + queue enqueue
- [ ] **H-10:** Add `moderateComment` Firestore `onCreate` trigger for `posts/{postId}/comments/{commentId}` with NeMo Guard pipeline and fail-closed behaviour
- [ ] **H-11:** Add `moderationQueue` entry in `moderateDMMessage`'s `!text` branch with `imageReviewRequired: true`
- [ ] **H-12:** Change `checkAdultMinorInteraction()` unknown-age handling to fail-closed; set `ageTier: 'blocked'` synchronously at account creation
- [ ] **H-13:** Implement adult-to-minor check in `AmenRBACService.allowDM()` by querying `isMinorAccount()` before returning `true`
- [ ] **H-14:** Audit all Algolia sync paths for `shouldExcludeFromPeopleIndex()` coverage; add Firestore trigger to remove minor users from Algolia on `ageTier` write
- [ ] **H-15:** Add Firestore rule requiring `churchVerified == true` for spaces containing minor members; apply `minorSafeDM` check to space messages
- [ ] **H-16:** Add admin-claim guard to `backfillUsernameLookup` callable
- [ ] **H-17:** Remove legacy `stripeWebhook.js` and route all Stripe webhook traffic to `stripe/stripeWebhook.js`
- [ ] **H-18:** Add `enforceAppCheck: true` to `finalizePostPublish` and `toggleReaction`
- [ ] **H-19:** Enable `enforceAppCheck: true` on all 33+ Berean OS and Selah Cloud Functions; use `FUNCTIONS_EMULATOR` guard for local dev
- [ ] **H-20:** Complete NCMEC ESP registration and remove `TODO_ESP_ID`/`TODO_ESP_API_KEY` from `cyberTiplineInterface.js`

### MEDIUM — Fix Before App Store Submission

- [ ] **M-01:** Change `whatsNewStories` rule from `allow read: if true` to `allow read: if isSignedIn()`
- [ ] **M-02:** Add explicit `entitlements` subcollection rule with owner-read-only and CF-write-only constraints
- [ ] **M-03:** Add field restrictions to `users/{userId}/actions` update path; change delete to soft-delete pattern
- [ ] **M-04:** Add string length and required-field validation to post/comment/discussion-message create rules
- [ ] **M-05:** Add Firestore legal hold check to Storage quarantine delete rule; move CSAM-flagged files to `legalHold/` path immediately
- [ ] **M-06:** Define separate `sanctuary/{sanctuaryId}/media/` Storage path with explicit rules and extend moderation pipeline to audio/video
- [ ] **M-07:** Extract `fetchWithRetry` (with exponential backoff and HTTP status inspection) from `moderatePost.js` into shared `retryHelper.js`; replace `withRetry` in `moderateUGC.js`
- [ ] **M-08:** Add `writeDeadLetter` calls after retry exhaustion in `moderateUGC.js` and `contentModerationTriggers.js`; add sweep in `moderationSweep`
- [ ] **M-09:** Add `POLICY_VERSION` constant to `moderateUGC.js` and stamp it on all moderation subdocuments and queue entries
- [ ] **M-10:** Move `birthYear` from public `/users/{uid}` to private subcollection; remove `ageTier` from public reads
- [ ] **M-11:** Implement guardian link verification CF for `/guardianLinkRequests`; implement email verification deep link
- [ ] **M-12:** Add `admin.auth().getUser(uid).disabled` or `user_trust/{uid}` check in `addComment` and `finalizePostPublish`
- [ ] **M-13:** Replace `senderData.isBanned` check in `safeMessagingGateway.js` with `admin.auth().getUser(uid)` disabled check
- [ ] **M-14:** Remove legacy `stripeWebhook.js` (resolves idempotency gap as well)
- [ ] **M-15:** Audit all Cloud Functions that mutate org/church/space resources and add server-side RBAC role reads

### LOW — Fix Before v1.0

- [ ] **L-01:** Remove duplicate `moderateContent` export from `index.js`; decide canonical module and rename if needed
- [ ] **L-02:** Remove `resolveUsernameToEmail` export after migrating all iOS callers to `signInWithUsername`
- [ ] **L-03:** Migrate `phoneAuthRateLimit.js` functions to Firebase Functions v2 with `defineSecret`

### Open Questions — Require Human Decision

- [ ] Confirm which rules file (`firestore.deploy.rules` vs `firestore.rules`) is deployed to production and reconcile the divergence (Q-1)
- [ ] Test `moderationQueue` creation end-to-end from an iOS client to confirm the silent-failure hypothesis (Q-2)
- [ ] Define and mint the `legalReviewer` custom claim (Q-3)
- [ ] Audit all CFs reading `/users/{userId}` fields for authorization decisions (Q-4)
- [ ] Identify and document the CF that enforces `one_users/witnesses` both-party acceptance (Q-5)
- [ ] Make a product decision on OPEN-5: intentional unauthenticated post reads vs. privacy-first gating (Q-6)
- [ ] Audit `MusicContentLayer` CF writes for missing Firestore rules coverage (Q-7)
- [ ] Run `firebase deploy --only storage --dry-run` to confirm `storage.rules` deployment status (Q-8)
- [ ] Measure `moderateUploadedImage` CF latency under load; assess CDN caching risk (Q-9)
- [ ] Confirm `NCMEC_SUBMISSION_ENABLED` environment variable value in production (Q-10)
- [ ] T&S Lead decision on OPEN-2: guardian approval scope and permission model (Q-11, Q-22)
- [ ] Confirm who has write access to `chat_videos/{conversationId}/` (Q-12)
- [ ] Audit legacy `users/{uid}/profileImages/` vs `profilePhotos/` path consistency (Q-13)
- [ ] Confirm whether `retryHelper.js withRetry` inspects HTTP status codes (Q-14)
- [ ] Audit `aiModeration.moderateContent` for fail-closed posture (Q-15)
- [ ] Confirm no hidden comment moderation trigger exists in `Backend/functions/src/index.ts` (Q-16)
- [ ] Assess Gen-1 quota impact on `moderateDMMessage` reliability (Q-17)
- [ ] Confirm Firestore rules block direct client writes to `posts/{postId}/comments/{commentId}` (Q-18)
- [ ] Confirm NCMEC API key integration for text-detected CSAM in `moderatePost.js` (Q-19)
- [ ] Enable Firestore TTL policy on `moderationQueue.expireAt` and `moderationDeadLetter` in Firebase Console (Q-20)
- [ ] Legal: Define and contractually enforce NCMEC SLA key holder and submission deadline — OPEN-4 (Q-21)
- [ ] Legal: Confirm minimum age floor — 13 (COPPA) or 16 (GDPR-K) — OPEN-1 (Q-23)
- [ ] Confirm or implement `onDocumentCreated` CF for `/guardianLinkRequests` (Q-24)
- [ ] Audit incremental Algolia sync paths for `shouldExcludeFromPeopleIndex()` coverage (Q-25)
- [ ] Confirm CSAM detection pipeline deployment and end-to-end `prepareCSAMEscalation()` callers (Q-26)
- [ ] Confirm report/flag button exists on all minor-visible surfaces (Q-27)
- [ ] Define admin/console `ageTier` protection policy for minor accounts (Q-28)
- [ ] Trace `stripeFunctions.js` import chain to confirm which `stripeWebhook.js` is deployed (Q-29)
- [ ] Confirm App Check migration ticket status for 33+ Berean OS functions (Q-30)
- [ ] Audit `covenantFunctions.js` and `spacesLivekitFunctions.js` for server-side RBAC checks (Q-31)
- [ ] Legal: Initiate NCMEC ESP registration; confirm timeline for `TODO_ESP_ID` replacement (Q-32)
- [ ] Confirm whether Firestore rules block direct client writes to DM messages collection (Q-33)
- [ ] Confirm canonical RBAC Firestore path used by Cloud Functions vs iOS `AmenRBACService` (Q-34)
- [ ] Confirm Firebase project-level App Check enforcement toggle is enabled in console (Q-35)

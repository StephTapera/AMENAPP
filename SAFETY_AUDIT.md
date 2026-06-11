# Amen Safety Audit — 2026-06-11

## Executive Summary

This audit covers the full Amen app safety pipeline: Cloud Functions moderation stack, Firestore and Storage security rules, iOS client safety integrations, Stripe/StoreKit entitlement flows, and minor-protection systems. The audit was conducted by a senior AppSec engineer using deep reads of all production rule files, moderation modules, and iOS client code.

**Overall posture: Conditionally acceptable for closed beta; NOT acceptable for public launch without resolving all Critical and High findings.**

The core moderation pipeline (moderatePost.js, imageModeration.js, textModeration.js, providerRouter.js) is well-hardened with fail-closed invariants, atomic batch writes, and explicit T&S-lead sign-off on the most sensitive constants. Firestore and Storage rules are comprehensive with explicit deny-by-default catch-alls. No hardcoded secrets were found.

However, four Critical gaps exist that represent real-time exploitation vectors: a broken import that crashes every user-filed CSAM report, a missing escalation path for image-only CSAM, a duplicate Cloud Function export that silently replaces the primary moderation callable, and an unverified App Store transaction that allows any paid tier to be spoofed by any authenticated user. These must be resolved before any public traffic is served.

**Summary counts:**
- Critical: 4
- High: 8
- Medium: 10
- Low: 10
- Open Questions: 10

---

## What Is Already Working Well

The following controls were confirmed working and require no remediation.

**Moderation pipeline invariants:**
- `moderatePost.js` fail-closed invariant is explicit (hard-coded `false` at line 330, mandatory T&S-Lead sign-off comment) — will never silently approve on error
- `parseSafetyResponse` jailbreak hardening: exact string match for "safe", negation rejection, three-attempt fallback to fail-closed
- `moderatePost.js` batches all Firestore writes atomically (post update + moderationQueue insert in one `db.batch()` call)
- `moderatePost.js` CSAM escalation for text posts: legalHolds + childSafetyEscalations + hide-all in one atomic batch commit when NeMo Guard returns `child_safety` or `csam_suspected`
- `moderatePost.js` retry with exponential backoff (500ms / 1000ms / 2000ms, 3 retries) and dead-letter on exhaustion
- `moderatePost.js` self-harm fast-path routes to crisis review queue, not silent block

**Image and text moderation:**
- `imageModeration.js` `FAIL_CLOSED_RESULT` is `Object.freeze()`'d and returned on all error branches
- `imageModeration.js` SSRF protection: only Firebase Storage URLs (`gs://` or `firebasestorage.googleapis.com`) accepted
- `imageModeration.js` 10 MB routing: oversized images go to human review, not auto-approved
- `textModeration.js` fail-closed catch returns `safe:false` with synthetic `unknown_model_error` category
- `textModeration.js` negation bypass protection: "safe" must appear AND "unsafe" must NOT appear

**Block/mute/report:**
- Bidirectional idempotent block, unidirectional mute, immutable report records
- Report rate limit (10/day) checked before write, incremented only after success
- Reporter identity never exposed to the reported user

**Rate limiting:**
- `rateLimits.js` `incrementCounter` uses Firestore transaction for atomic increment
- `rateLimits.js` TTL `expiresAt` field set on all counter documents

**Escalation and legal hold:**
- NCMEC stub properly gated — throws with explicit `TODO(gate: DECISION)`, cannot auto-submit
- `escalation.js` `createLegalHold` immediately hides content (`visible:false`) before any other operation
- `legalHold.js` `snapshotHash` written for tamper detection on every hold record
- `legalHold.js` `isUnderLegalHold` fails safe (returns `true`) on Firestore read error

**Firestore and Storage rules:**
- Explicit catch-all deny at line 2873 (`allow read, write: if false`)
- No `allow write: if true` anywhere in the file
- Client writes to moderation fields on posts and comments fully blocked via `postModerationFields()` / `commentModerationFields()`
- `legalHolds` collection is `allow create, update, delete: if false` — Admin SDK bypass only
- `moderationAuditLog` is `allow read, write: if false` — fully server-side
- Minor DM mutual-follow gate implemented in rules
- `whatsNewStories` public read is explicitly documented as intentional (P-3 invariant)
- Quarantine-first upload pipeline: client uploads land in `uploads/quarantine/` (create-only, owner-only, MIME allowlist)
- `uploads/blocked/` and `uploads/legalHold/` are fully denied to all clients
- Explicit MIME allowlist covering jpeg/png/webp/heic/mp4/quicktime/mpeg/aac/pdf
- `isBlockedType()` blocks executable/html/js content types
- Explicit catch-all deny at Storage line 733

**Appeals and admin:**
- `appeals.js` App Check enforced on both `submitAppeal` and `decideAppeal`
- `appeals.js` ownership verification before appeal creation
- `appeals.js` status idempotency — second decision on same appeal throws `failed-precondition`
- `adminModerationFunctions.js` requires fresh Auth record via `admin.auth().getUser()` (not stale JWT claim)
- `adminModerationFunctions.js` whitelists resolution strings against `VALID_RESOLUTIONS`

**App Check and secrets:**
- `AppDelegate` uses `AmenAppCheckProviderFactory` with App Attest (iOS 14+) / DeviceCheck fallback
- `providerRouter.js` `NVIDIA_API_KEY` declared via `defineSecret` — never hardcoded
- `providerRouter.js` 10-second `AbortSignal` timeout on all API calls
- `providerRouter.js` logs only metadata (no user content in any log line)
- No hardcoded secrets found in `index.js`

**Minor protection and DM moderation:**
- `moderateDMMessage` Firestore `onCreate` trigger wired
- `moderateSanctuaryMessage` callable wired
- `moderatePrayerRequest` callable wired
- `minorProtection.js` `validateMinorDiscovery` hides under-13 profiles from non-guardians
- `AuthenticationViewModel.swift` custom claim `isDeactivated` check force-refreshes ID token and takes precedence over Firestore field

---

## Findings

---

### [CRITICAL] C1 — Broken escalateChildSafety import crashes every user-filed CSAM report

- **Location:** `functions/safety/blockMuteReport.js` lines 31, 215
- **Threat Vector:** A user files a report with category `child_safety`, `csam_suspected`, `child_grooming`, or related CHILD_SAFETY_CATEGORIES values. The report hits the child-safety fast-path at line 204, calls `escalateChildSafety()` at line 215. That symbol is imported from `../moderation/escalation` (line 31) but `escalation.js` only exports `createLegalHold` and `reportToNcmec` — `escalateChildSafety` is not exported. The import resolves to `undefined`. A `TypeError: escalateChildSafety is not a function` is thrown. The catch block (lines 235–239) logs the error but does not re-throw and does not create any escalation record.
- **Impact:** Every user-filed CSAM / child-safety report silently fails. No `legalHolds` document is created. No `childSafetyEscalations` record is written. The reported content lands in the normal moderation review queue indistinguishable from a spam report. Mandatory child-protection reporting obligations cannot be met via this vector. This is a complete bypass of the CSAM escalation pipeline for user reports.
- **Remediation:** Move `escalateChildSafety` from `moderatePost.js` into `functions/moderation/escalation.js` and export it alongside `createLegalHold`. Update the import in `blockMuteReport.js` accordingly. Additionally, change the catch block to re-throw (or write a fallback `moderationQueue` entry tagged `escalation_failed`) so failures are never silently swallowed. Add a unit test that asserts a child-safety report writes a `legalHolds` document.
- **Status:** Open

---

### [CRITICAL] C2 — Image-only CSAM has no legalHold or NCMEC escalation

- **Location:** `functions/moderation/imageModeration.js` lines 224–235; `functions/moderatePost.js` lines 268–309, 338–341
- **Threat Vector:** A user uploads an image post containing CSAM material. The vision model returns `cs_csam_suspected` or `cs_child_exploitation` in its categories. `imageModeration.js` correctly returns `status='blocked'` but performs no Firestore write itself. The caller `moderatePost.js` routes image-only posts to `pending_image_review` (lines 272–309) and returns. The `escalateChildSafety` call at line 339 fires only when NeMo Guard text categories trigger it — image-only CSAM content never triggers the escalation path regardless of what the vision model found.
- **Impact:** An image-only CSAM post creates a `moderationQueue` entry for human review but no `legalHolds` record, no `childSafetyEscalations` document, and no NCMEC pipeline entry. The evidence is not preserved in tamper-evident form at the time of detection. A human reviewer working off the queue entry may act on the content before escalation infrastructure was triggered. Mandatory child-protection reporting obligations may be violated.
- **Remediation:** In `adminReviewPost` (or a dedicated image review callable), after `imageModeration.js` returns `status='blocked'` with `cs_csam_suspected` or `cs_child_exploitation` categories, call the canonical `escalateChildSafety` (after fixing C1) before making any other moderation decision. Wire `imageModeration.js` into the DM and comment image paths to ensure CSAM images in those surfaces also reach the escalation pipeline.
- **Status:** Open

---

### [CRITICAL] C3 — index.js exports moderateContent twice — second export silently shadows the first

- **Location:** `functions/index.js` lines 167, 300
- **Threat Vector:** Line 167 exports `moderateContent` from `contentModeration.js` (a callable function). Line 300 overwrites `exports.moderateContent` with `aiModeration.moderateContent` (a Firestore `onDocumentCreated` trigger on `moderationRequests`, not a callable). Any iOS client or Cloud Function invoking the `moderateContent` callable receives the `aiModeration` version, which has a different function type, different safety model, and different CHILD_SAFETY_CATEGORIES handling.
- **Impact:** `contentModeration.moderateContent` is effectively dead code — it is never deployed as its own callable. Any caller invoking `moderateContent` gets the `aiModeration` version. If the two implementations diverge in safety posture (e.g., different fail-closed behavior, different category handling), the deployed behavior silently diverges from the audited code. Additionally, exporting a Firestore trigger under a callable-named export creates a function type mismatch in the Cloud Functions runtime.
- **Remediation:** Rename the `aiModeration` export at line 300 to `exports.moderateContentAI` and update all callers. Add a CI lint rule (e.g., ESLint `no-duplicate-keys` or a custom script) asserting no duplicate export names in `index.js`. Verify `contentModeration.moderateContent` is still the intended primary callable before the rename.
- **Status:** Open

---

### [CRITICAL] C4 — App Store subscription tier trusts unverified client-supplied transactionId — premium tiers can be spoofed

- **Location:** `functions/accountSubscriptionFunctions.js` lines 114–175
- **Threat Vector:** `processAccountSubscription` is a callable that accepts `{transactionId, tier, uid, productId}` from the iOS client and writes the subscription tier to Firestore without any Apple App Store Server API verification. The TODO at line 150 explicitly documents this as unimplemented. Any authenticated user can call this function with `tier: 'creator_pro'` (or any other paid tier) and a fabricated or replayed `transactionId` to permanently grant themselves premium access.
- **Impact:** Revenue fraud: any authenticated user can self-promote to any paid tier at zero cost. This undermines paywalls on Creator OS, live streaming, Spaces monetization, and any other tier-gated feature. The Firestore rules block direct client writes to subscription tier fields, but `processAccountSubscription` runs as a Cloud Function and writes server-side, bypassing those rules entirely.
- **Remediation:** Before writing any entitlement: (1) build an ES256 JWT using the App Store Connect private key stored in Secret Manager; (2) call App Store Server API production endpoint `GET /inApps/v1/transactions/{transactionId}`; (3) verify the response transaction matches the claimed `tier` and `productId`; (4) only then write the entitlement. Gate the deploy on `APPLE_ASC_PRIVATE_KEY` being set in Secret Manager. This must be resolved before any paid tier is activated for any user.
- **Status:** Open

---

### [HIGH] H1 — Berean AI callables do not enforce App Check

- **Location:** `functions/v2functions.js` lines 479–484, 551–557, 607–612 (`bereanChat`, `bereanMemory`, `bereanCrisisDetect`)
- **Threat Vector:** The `onCall` options objects for these three AI endpoints omit `enforceAppCheck: true`. Any authenticated user with a valid Firebase ID token — including a compromised account, an automated script, or a simulator — can call these endpoints without App Check attestation.
- **Impact:** Quota exhaustion attacks against NVIDIA/Anthropic API keys. `bereanCrisisDetect` handles crisis language detection for minors; unatteested calls could flood the crisis queue or probe model responses for jailbreak manipulation. Rate limits exist but operate on UID only — a single compromised account can burn its rate limit and keep calling.
- **Remediation:** Add `enforceAppCheck: true` to each callable's options object: `onCallV2({ region: 'us-central1', enforceAppCheck: true, timeoutSeconds: 60, secrets: [...] }, ...)`. Also confirm in the Firebase Console that App Check enforcement is toggled ON for the production project — without that toggle, `enforceAppCheck: true` in code is a no-op.
- **Status:** Open

---

### [HIGH] H2 — Universal age gate (ff_onboarding_v2) is default OFF — social sign-ins skip COPPA/KOSA age collection

- **Location:** `AMENAPP/AMENFeatureFlags.swift` lines 218, 1032; `AMENAPP/AuthenticationViewModel.swift` lines 293–294
- **Threat Vector:** `evaluateAgeGateIfNeeded()` returns immediately if `onboardingV2Enabled` is `false`. Users who sign in via Apple or Google never enter a date of birth and receive no age profile. `isMinorAccount()` in Firestore rules reads `ageTier` from the user document — a user with no age profile has no `ageTier` and `isMinorAccount()` returns `false`, treating minors without a profile as adults for DM safety gating.
- **Impact:** Under-13 users who sign in via social auth have no COPPA gate. Teenagers who sign in via social auth can DM any adult without the minor-safety block triggering. This is a COPPA/KOSA violation risk at the time of any public launch.
- **Remediation:** Set the Remote Config default for `ff_onboarding_v2` to `true` immediately. This flag is safety infrastructure, not an experimental feature. Additionally, add a server-side check: any profile-creation Cloud Function should verify an age profile exists and create a gated-pending-verification default if absent, independent of the iOS flag state.
- **Status:** Open

---

### [HIGH] H3 — publishQuotePost() writes directly to Firestore from iOS client, bypassing the moderation pipeline

- **Location:** `AMENAPP/PostsManager.swift` lines 1568–1592
- **Threat Vector:** `publishQuotePost()` calls `ref.setData(data)` directly from the iOS client. The `moderatePost` Cloud Function is an `onCreate` trigger and will fire, but the post's `visible` field is absent from the client data dict — the post may be readable to followers before moderation completes (typically 500ms–2s). The quoted content fields (`quotedContent`, `quotedAuthorName`) are fully client-controlled and can be spoofed.
- **Impact:** A user can publish a quote post with harmful content that is immediately readable to followers for the duration of moderation trigger latency. There is no pre-publish `checkCommentQuality`-style gate on quote posts. Quote attribution fields can be forged to impersonate other users' words.
- **Remediation:** Refactor `publishQuotePost` to call a Cloud Function callable (e.g., `publishPost`) that sets `visible:false` on write, then lets the `moderatePost` trigger re-enable visibility after a safe verdict. At minimum, add a Firestore rule that forces `visible:false` on post create if the client does not set it (using `request.resource.data.get('visible', false) == false` in the create condition).
- **Status:** Open

---

### [HIGH] H4 — Two parallel legalHolds schema implementations will corrupt the legal hold audit trail

- **Location:** `functions/moderation/legalHold.js` lines 40–80; `functions/moderatePost.js` lines 197–250; `functions/moderation/escalation.js` lines 60–100
- **Threat Vector:** Three code paths write to the `legalHolds` collection with incompatible schemas: `legalHold.js` uses `holdId=caseId` with a full `contentSnapshot` and `snapshotHash`; `moderatePost.js` `escalateChildSafety` uses `holdId=crypto.randomUUID()` with an `evidenceRefs` array; `escalation.js` `createLegalHold` uses yet another `holdId` format. `cyberTiplineInterface.js` likely reads only one schema.
- **Impact:** Downstream NCMEC reporting and legal review tools encounter documents with incompatible schemas, causing parse failures or missing fields. In a legal proceeding, inconsistent hold records undermine the integrity of the evidence chain. SHA-256 hashes computed from different snapshots cannot be cross-referenced. The NCMEC stub's `TODO(gate: DECISION)` cannot safely be unblocked until the schema is canonical.
- **Remediation:** Define a single canonical `legalHolds` schema in a shared module (e.g., `moderation/legalHoldSchema.js`). Route all three code paths through `legalHold.js` `createLegalHold` as the sole writer. Migrate any existing documents to the canonical schema before enabling the NCMEC submission stub.
- **Status:** Open

---

### [HIGH] H5 — one_users witnesses subcollection allows write by any authenticated user

- **Location:** `firestore.rules` line 1684
- **Threat Vector:** `allow write: if isSignedIn()` places no ownership or field restriction on witness documents. Any authenticated AMEN user can write to any `one_users/{uid}/witnesses/{witnessId}` document for any other user's UID.
- **Impact:** A malicious user could forge their own acceptance into another user's witness list, gaining false accountability access. They could overwrite and destroy legitimate witness records for a targeted user, silently severing their accountability network. The ONE private social OS witness accountability model's integrity relies entirely on these records being tamper-evident.
- **Remediation:** Replace `allow write: if isSignedIn()` with ownership and field-level checks: `allow create: if isSignedIn() && request.resource.data.witnessUID == request.auth.uid; allow update: if isSignedIn() && (request.auth.uid == uid || request.auth.uid == resource.data.witnessUID) && request.resource.data.keys().hasOnly(['status', 'acceptedAt', 'updatedAt']); allow delete: if false`. The Cloud Function that creates the initial witness invitation should own the create path via Admin SDK.
- **Status:** Open

---

### [HIGH] H6 — Duplicate Stripe webhook file with no idempotency, wrong secret method, and missing event types

- **Location:** `functions/stripeWebhook 2.js` lines 3–44
- **Threat Vector:** A legacy duplicate webhook handler uses `process.env.STRIPE_SECRET_KEY` (Gen1 env pattern) instead of `defineSecret`. It lacks the idempotency guard present in the canonical handler. It handles only `customer.subscription.updated/deleted` and `account.updated` — missing `customer.subscription.created` and invoice events.
- **Impact:** If deployed (even accidentally), duplicate subscription events will double-write entitlements. Missing `subscription.created` handling means new subscribers may not be provisioned. The Gen1 secret pattern may expose `STRIPE_SECRET_KEY` in function environment variables visible to all functions in the same deployment.
- **Remediation:** Delete `functions/stripeWebhook 2.js` immediately. Add a CI check asserting no file with a trailing space or number in name exists in the `functions/` directory. Verify only `stripe/stripeWebhook.js` (the canonical Gen2 handler) is exported in `index.js`.
- **Status:** Open

---

### [HIGH] H7 — detectGroomingRisk is exported but never called — grooming pattern detection is dead code

- **Location:** `functions/safety/minorProtection.js` lines 464, 561
- **Threat Vector:** `detectGroomingRisk` implements five weighted heuristic patterns (photo requests, location probing, off-platform solicitation, secrecy, unanswered pursuit) and is exported at line 561 but is never imported or called by any other module in the functions directory.
- **Impact:** Adult-to-minor message streams are never analyzed for grooming patterns. Grooming signals in DMs between adults and minors produce no `safetyAlert` and no `moderationQueue` entry. Any compliance documentation claiming grooming detection is active is incorrect.
- **Remediation:** Wire `detectGroomingRisk` into the `onMessageSent` trigger in `v2functions.js` or the `moderateDMMessage` handler in `moderateUGC.js`. Fetch the prior N messages for the conversation, pass to `detectGroomingRisk`, and write a `safetyAlert` if risk >= `'elevated'`. Add a time-window filter (e.g., last 30 days) to the prior-reply query to prevent stale message counts from inflating the risk score.
- **Status:** Open

---

### [HIGH] H8 — User profile bios, display names, and testimonies have no automated moderation trigger

- **Location:** `functions/profilePropagation.js` lines 37–69; `functions/testimonyFeatures.js` lines 38–86
- **Threat Vector:** `onUserProfileUpdated` in `profilePropagation.js` propagates `displayName` and `username` changes to denormalized copies with no safety check. `testimonyFeatures.js` writes testimony documents with no NeMo Guard trigger. A user can set an offensive or CSAM-referencing display name or testimony with no automated review.
- **Impact:** Offensive display names propagate to all denormalized copies (posts, comments, etc.) before any review. Testimony text receives no NeMo Guard screening. Both surfaces are high-visibility UGC vectors that bypass the entire moderation pipeline.
- **Remediation:** Add a `moderateText()` call inside `onUserProfileUpdated` for `displayName` and `bio` fields — if unsafe, revert to the prior value and create a `moderationQueue` entry. Add an `onDocumentCreated` / `onDocumentWritten` trigger on the `testimonies` collection that calls `moderateText()` on the testimony body field.
- **Status:** Open

---

### [MEDIUM] M1 — Rate limit check-then-increment is non-atomic — concurrent requests can burst above limit

- **Location:** `functions/safety/rateLimits.js`
- **Threat Vector:** `checkRateLimit` (read-only) and `incrementCounter` (transactional) are separate calls. Two concurrent requests for the same user can both pass `checkRateLimit` before either calls `incrementCounter`, allowing a small burst above the configured limit.
- **Impact:** Users can briefly exceed per-action rate limits under concurrent load. This is most impactful for the report (10/day) and DM (100/day) limits where a small burst could be exploited to flood queues.
- **Remediation:** Merge check and increment into a single Firestore transaction: read the counter, throw `RateLimitError` if `count >= limit`, otherwise increment and return. Remove the separate `checkRateLimit` function or demote it to a read-only diagnostic tool only.
- **Status:** Open

---

### [MEDIUM] M2 — iOS moderationAuditLogs collection silently denied — client audit writes always fail

- **Location:** `AMENAPP/ModerationAuditLog.swift`; `firestore.rules`
- **Threat Vector:** `ModerationAuditLog.swift` writes to `moderationAuditLogs` (plural) using the client Firestore SDK. The Firestore rules define `moderationAuditLog` (singular) as Admin SDK only (`allow read, write: if false`). The plural collection has no rule and falls through to the catch-all deny at line 2874. All iOS client audit writes are silently rejected.
- **Impact:** The iOS-side audit trail is entirely non-functional. Cross-surface audit trail is fragmented — server-side events appear in `moderationAuditLog` while iOS events are silently dropped.
- **Remediation:** Replace `ModerationAuditLog.swift`'s direct Firestore writes with a CF callable that accepts structured audit events and writes to the canonical `moderationAuditLog` collection via Admin SDK. This is safer and consistent with the server-side audit architecture.
- **Status:** Open

---

### [MEDIUM] M3 — TrueSource audit contract is entirely unimplemented — all log methods are empty stubs

- **Location:** `AMENAPP/ModerationAuditLog.swift` lines 242–254
- **Threat Vector:** `logPostCreated`, `logMediaUploaded`, `logAIGenerated`, `logAIAssisted`, `logSafetyScanned`, `logSourceChecked`, `logRankingScored`, `logLabelApplied`, `logReachReduced`, `logHumanReviewRequested`, `logContentRemoved`, `logAppealSubmitted`, `logAppealResolved` are all empty method bodies. `TrueSourceEventEntry` is defined but never written anywhere.
- **Impact:** The TrueSource audit contract — the iOS client's commitment to the Trust & Safety platform — is entirely non-functional. Any audit, compliance review, or DSA/KOSA reporting that relies on this data will find an empty collection.
- **Remediation:** Implement the TrueSource log methods using the CF callable approach described in M2. Each method should construct a `TrueSourceEventEntry` and send it to the backend audit callable. Prioritize `logContentRemoved`, `logAIGenerated`, and `logSafetyScanned` as the highest-value entries for compliance.
- **Status:** Open

---

### [MEDIUM] M4 — Appeal submission has no rate limit — users can flood the appeals queue

- **Location:** `functions/moderation/appeals.js` line 33
- **Threat Vector:** `submitAppeal` has no call to `rateLimits.checkRateLimit`. A user whose content is removed can submit an unbounded number of appeal documents. The `evidence` field (2000 chars per submission) provides a potential storage exfiltration vector.
- **Impact:** The human reviewer appeals queue can be overwhelmed, delaying legitimate appeals. The appeals collection could be used as a write amplification vector.
- **Remediation:** Add `rateLimits.checkRateLimit(db, uid, 'appeal', currentWindowBucket)` at the start of `submitAppeal`. A reasonable limit is 5 appeals per day per user. Increment the counter after the appeal document is written.
- **Status:** Open

---

### [MEDIUM] M5 — decideAppeal uses stale JWT claim for moderator check instead of re-fetching Auth record

- **Location:** `functions/moderation/appeals.js` (decideAppeal handler)
- **Threat Vector:** `decideAppeal` reads `request.auth.token.moderator` from the JWT, which can be up to 1 hour stale. A moderator whose role was revoked can continue deciding appeals until their token expires.
- **Impact:** Revoked moderators retain decision-making authority for up to one hour after revocation. Appeals decided by a revoked moderator may need to be retroactively invalidated.
- **Remediation:** Replace the JWT claim check in `decideAppeal` with the same `requireModerator()` helper pattern used in `adminModerationFunctions.js`: call `admin.auth().getUser(uid)` to fetch current custom claims at call time.
- **Status:** Open

---

### [MEDIUM] M6 — No circuit breaker on NVIDIA NIM provider — outage burns full 40s timeout per moderation call

- **Location:** `functions/moderation/providerRouter.js`
- **Threat Vector:** When NVIDIA NIM is degraded, every moderation call burns `MAX_ATTEMPTS` (4) at 10s each (40s total) before failing. Under concurrent post creation this serializes the Cloud Function cold path and can cascade into function timeout exhaustion, pushing all posts to dead-letter.
- **Impact:** A sustained NVIDIA NIM outage causes all new posts to land in dead-letter or pending-human-review simultaneously, creating a moderation backlog that may take hours to drain. Cloud Function costs spike due to extended invocation times.
- **Remediation:** Implement a simple in-memory circuit breaker (open after N consecutive failures within a window, half-open after a reset timeout). Use Firestore or a shared cache for cross-instance circuit state. Alternatively, reduce `MAX_ATTEMPTS` to 2 during detected outage and rely on the dead-letter queue for retry.
- **Status:** Open

---

### [MEDIUM] M7 — Comment edits have no moderation trigger — post-approval edits can introduce harmful content

- **Location:** `functions/` (no `onDocumentUpdated` trigger for comments exists)
- **Threat Vector:** `commentGateway.js` gates new comment creation via `checkCommentQuality`. No `onDocumentUpdated` or `onDocumentWritten` trigger exists on the comments collection path. A user can publish an approved comment and then edit it to contain harmful content.
- **Impact:** Any approved comment can be retroactively mutated to contain harmful, CSAM-adjacent, or crisis content with no automated detection.
- **Remediation:** Add an `onDocumentUpdated` trigger on `comments/{commentId}` that calls `textModeration.moderateText()` on any change to the `body`/`content` field. If unsafe, revert to the previous value and write a `moderationQueue` entry.
- **Status:** Open

---

### [MEDIUM] M8 — Password reset rate limiting is client-side only and resets on every app restart

- **Location:** `AMENAPP/AuthenticationViewModel.swift` lines 56–58, 993–1028
- **Threat Vector:** `passwordResetAttempts`, `passwordResetWindowStart`, and `passwordResetLastSent` are in-memory properties. The 3-per-15-minute limit resets on every app restart. An attacker targeting an account can force-quit and relaunch the app to reset the counter and send unlimited password reset emails to a target.
- **Impact:** Unlimited password reset emails can be sent to any account email address, constituting an email harassment vector and potentially triggering email provider abuse flags on the app's sending domain.
- **Remediation:** Move rate limiting server-side: add a `sendPasswordReset` action to `rateLimits.js` with a 3/15-minute limit keyed on the target email address (not caller UID). Wrap Firebase's password reset email send in a CF callable that enforces this server-side counter before invoking `admin.auth().generatePasswordResetLink()`.
- **Status:** Open

---

### [MEDIUM] M9 — resolveAlert audit entry writes to adminClaimLog instead of unified moderationAuditLog

- **Location:** `functions/adminModerationFunctions.js`
- **Threat Vector:** `resolveAlert` writes its audit record to the `adminClaimLog` collection using `collection.add()` rather than calling `logModerationAction()` in `auditLog.js`. Crisis alert resolutions do not appear in `moderationAuditLog` queries.
- **Impact:** The audit trail is fragmented: crisis alert resolutions are invisible to any tool or report that queries `moderationAuditLog`. Compliance reports that depend on unified audit trail completeness will miss this event class.
- **Remediation:** Replace the direct `adminClaimLog.add()` call with `logModerationAction({ actionType: 'alert_resolved', actorUid: uid, ... })` to route the entry through the unified audit log. Add `'alert_resolved'` to `VALID_ACTION_TYPES` in `auditLog.js`.
- **Status:** Open

---

### [MEDIUM] M10 — isMinorAccount() in Firestore rules reads Firestore (not auth token claim) — stale and expensive

- **Location:** `firestore.rules` lines 205–207
- **Threat Vector:** `isMinorAccount(uid)` performs a `get()` against `users/{uid}` on every DM creation check. The `ageTier` field in the document can be stale if a background Cloud Function that updates the auth token claim has not yet propagated the change back to the user document.
- **Impact:** Every DM creation incurs an additional billable Firestore read. Age tier changes (e.g., a user turns 13) may not take effect immediately, keeping the minor-safety block active or inactive longer than intended.
- **Remediation:** Set `ageTier` as a Firebase Auth custom claim when age is verified. Replace the `get()` in `isMinorAccount()` with `request.auth.token.get('ageTier', '') in ['blocked', 'teen', ...]` to use the token claim directly. This eliminates the extra read and uses the same authoritative source as the token.
- **Status:** Open

---

### [LOW] L1 — providerRouter.js always labels images as JPEG in the data-URI prefix

- **Location:** `functions/moderation/providerRouter.js`
- **Impact:** PNG, WebP, or HEIC uploads are mislabeled `data:image/jpeg;base64,` to the vision model, potentially degrading moderation accuracy on format-sensitive content.
- **Remediation:** Accept an optional `mimeType` parameter in `callVisionModel` and construct the data-URI prefix from the actual MIME type. Fall back to `image/jpeg` only when `mimeType` is unknown. Update all callers to pass the MIME type from Storage metadata.
- **Status:** Open

---

### [LOW] L2 — snapshotHash in legalHold.js uses JSON.stringify (non-deterministic key order)

- **Location:** `functions/moderation/legalHold.js` line 53
- **Impact:** SHA-256 hash computed from `JSON.stringify(contentSnapshot)` may not be reproducible across JS runtimes or V8 versions, undermining independent verification of the hash in legal proceedings.
- **Remediation:** Use a deterministic JSON serializer (e.g., `json-stable-stringify`) instead of `JSON.stringify`. Ensures the SHA-256 hash can be independently verified across environments and runtime versions.
- **Status:** Open

---

### [LOW] L3 — getLegalHoldEvidence has no role enforcement inside the function body

- **Location:** `functions/moderation/legalHold.js`
- **Impact:** A miscoded caller can retrieve CSAM evidence snapshots without a role check. The doc comment says callers must verify roles, but there is no assertion or guard inside the function.
- **Remediation:** Add an explicit role assertion inside `getLegalHoldEvidence`: verify the caller's UID has the `trust_safety_admin` or `legal_admin` custom claim via `admin.auth().getUser()` before returning any evidence snapshot.
- **Status:** Open

---

### [LOW] L4 — minorProtection unknown-age path for non-DM content types does not write a safetyAlert

- **Location:** `functions/safety/minorProtection.js`
- **Impact:** When `validateMinorInteraction` returns `{ allowed: true, requiresReview: true }` for `sanctuary_invite` or `reply` content types with an unknown-age participant, no `safetyAlert` record is written. The review requirement is silently lost if the caller ignores `requiresReview`.
- **Remediation:** When `requiresReview: true` is returned for non-DM paths, write a `safetyAlert` record (or at minimum a `moderationQueue` entry) before returning, so the review requirement is persisted server-side regardless of caller behavior.
- **Status:** Open

---

### [LOW] L5 — AmenAppCheckService.configure() uses DeviceCheckProviderFactory inconsistently with AppDelegate

- **Location:** `AMENAPP/AMENAPP/CommunityOS/Security/AmenAppCheckService.swift` lines 74–79
- **Impact:** Two separate App Check configuration methods exist with different provider choices. `AppDelegate` correctly uses `AmenAppCheckProviderFactory` (App Attest + DeviceCheck fallback). `AmenAppCheckService.configure()` uses only `DeviceCheckProviderFactory`. If `configure()` is called anywhere, it replaces the stronger provider with a weaker one.
- **Remediation:** Either update `AmenAppCheckService.configure()` to use `AmenAppCheckProviderFactory`, or add a clear doc comment and a runtime assertion that this method is not the active configuration path. Consider deleting the method if it is never called.
- **Status:** Open

---

### [LOW] L6 — textModeration.js rawResponse truncated to 500 chars — safety categories may be cut off in audit log

- **Location:** `functions/moderation/textModeration.js`
- **Impact:** If the model returns a long explanation, the truncation may hide the actual safety categories in the audit log record, hampering forensic review of moderation decisions.
- **Remediation:** Store the full `categories` array separately from the raw response text. The `categories` field is already extracted — write it to the audit log independently of `rawResponse` truncation so forensic review always has the complete label set.
- **Status:** Open

---

### [LOW] L7 — setMinorFlag allows isMinor=false with minorAgeBand set — inconsistent state writable

- **Location:** `functions/safety/minorProtection.js`
- **Impact:** Inconsistent state (`isMinor: false, minorAgeBand: '13_15'`) could cause `isMinorAccount()` to return incorrect results if it ever reads `minorAgeBand` independently of `isMinor`.
- **Remediation:** Add a validation check: if `isMinor === false`, reject any call that also provides a non-null `minorAgeBand`.
- **Status:** Open

---

### [LOW] L8 — providerRouter.js MAX_ATTEMPTS comment is self-contradictory

- **Location:** `functions/moderation/providerRouter.js`
- **Impact:** Documentation-only, but misleading comment makes the retry budget hard to audit during incident response.
- **Remediation:** Correct the comment to accurately document the actual retry budget (4 total attempts = 1 initial + 3 retries). Adjust the constant name or value to match documented intent.
- **Status:** Open

---

### [LOW] L9 — sendDailyNotificationDigest queries entire users collection without pagination

- **Location:** `functions/v2functions.js`
- **Impact:** At scale, querying all users with `digestMode==true` in a single scheduled invocation will time out or exhaust Cloud Function memory.
- **Remediation:** Add pagination to the users query (`limit` + `startAfter`) and process users in batches of 500. Store a cursor in Firestore to resume across scheduled function invocations.
- **Status:** Open

---

### [LOW] L10 — Legacy profilePhotos/ storage path still allows direct client writes, bypassing quarantine pipeline

- **Location:** `storage.rules`
- **Impact:** Users on older app builds can still upload profile photos via the legacy `profilePhotos/` path, bypassing the quarantine pipeline's MIME validation, size caps, and virus scanning.
- **Remediation:** Change the `profilePhotos/{uid}/{photoId}` rule to `allow read, write: if false` once the quarantine pipeline at `profile_photos/` is confirmed as the sole active path. Set a migration deadline and remove the legacy path after all active client builds use the quarantine path.
- **Status:** Open

---

## Open Questions

These items require human decisions from legal, compliance, product, or engineering leadership before code changes can be made.

1. **NCMEC SLA (OPEN-5):** What is the mandatory reporting SLA for CSAM escalations under U.S. law (18 U.S.C. § 2258A)? The `cyberTipline` stub must not be unblocked until a compliance-approved submission flow and SLA enforcement timer are in place. No automated NCMEC submission should go live without legal sign-off.

2. **COPPA/KOSA jurisdiction — EU GDPR-K age threshold (OPEN-1):** Is the EU GDPR-K age threshold 13 or 16 for the jurisdictions Amen targets? This determines whether the age gate must block all EU users under 16 (not just under-13), which affects `isMinorAccount()` vocabulary and the scope of the DM safety gate.

3. **Guardian consent model (OPEN-2):** What is the scope of the guardian tool? Can guardians read all their minor's DMs, or only safety alerts? This affects whether guardian relationship approval requires a separate consent record beyond the Cloud Function write, and has direct implications for privacy law compliance.

4. **Anonymous prayer identity (OPEN-3):** What level of identity shielding is required for anonymous prayer requests? If prayers are anonymous to other users but linked to UID server-side, is that sufficient, or must the UID be cryptographically separated from the prayer content entirely? This affects how `moderatePrayerRequest` stores content references.

5. **Unauthenticated visitor read on public posts (OPEN-6):** Is open unauthenticated read on public posts intentional as an SEO decision? If yes, a `robots.txt` gate and rate limit should be added. If no, `isSignedIn()` must be added to the public posts read path. This is a product and legal decision.

6. **App Check Console enforcement:** Has the Firebase Console App Check enforcement toggle been enabled for production project `amen-5e359`? If not, `enforceAppCheck: true` in Cloud Function code is a no-op and all requests pass without attestation regardless of iOS-side configuration. This must be confirmed before any beta launch.

7. **NCMEC reporting go/no-go criteria:** The `reportToNcmec` stub is gated on compliance approval (`TODO(gate: DECISION)`). Has legal/compliance reviewed the automated submission flow? What is the explicit go/no-go criterion for replacing the stub with the live NCMEC API call? A written sign-off record should exist before that gate is removed.

8. **Spaces/channel UGC moderation coverage:** Spaces-specific post collections are not covered by `moderatePost.js`. Is this an accepted gap pending a dedicated Spaces moderation trigger, or is it assumed all Spaces content goes through the top-level `posts/` collection? An explicit product decision is needed to close or accept this gap.

9. **Job seeker profile moderation scope:** Job listings and job seeker bios contain free-text fields with no moderation trigger. Are these in-scope for automated moderation, or handled entirely by the church admin who posted the listing? Product decision required before launch.

10. **Stripe webhook deduplication audit:** The canonical `stripe/stripeWebhook.js` has an idempotency guard. Has the legacy `stripeWebhook 2.js` been deployed to any environment? If so, subscription events may have already been double-written and entitlements need to be audited and corrected before any paid tier is activated.

---

*Audit conducted 2026-06-11. Auditor: Senior AppSec Engineer. Next review recommended after all Critical and High findings are resolved, and before any public launch or paid tier activation.*

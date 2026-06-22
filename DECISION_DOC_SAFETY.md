# SAFETY DECISIONS — Amen App
**Owner:** [assign safety officer]
**Date:** 2026-06-11
**Branch:** safety-hardening
**Source audit:** SAFETY_AUDIT.md

> Each decision has a RECOMMENDED DEFAULT. Accept or override with a written justification.
> Items in GROUP A are HARD BLOCKERS — the safety-hardening branch MUST NOT be deployed to production until every A-item has a completed decision and the corresponding code change is merged.

---

## GROUP A — BLOCKS SAFETY DEPLOY
> Answer every item in this group before merging safety-hardening or enabling any safety-gated flag in production.

---

### A-01: NCMEC CyberTipline Registration
**Source:** Audit Q-10, Q-19, Q-21, Q-32 / Checklist C-10, H-20
**Question:** Has legal counsel been engaged to register with NCMEC as an Electronic Service Provider per 18 U.S.C. § 2258A? The `NCMEC_SUBMISSION_ENABLED` gate, `TODO_ESP_ID`, and `TODO_ESP_API_KEY` placeholders in `ncmecReporter.js` and `cyberTiplineInterface.js` indicate registration has not been completed.
**Recommended:** Engage counsel immediately. `reportToNcmec()` and the live HTTPS POST pipeline MUST NOT run in production until registered. Registration requires a written agreement with NCMEC and issuance of an ESP ID and API key. Store both in Firebase Secret Manager before any deploy.
**Risk if skipped:** Federal criminal liability for failing to report known CSAM under 18 U.S.C. § 2258A. This is not a civil risk — it is a criminal one.
**Decision:**
- [ ] Registration in progress — attorney engaged, ETA: ___________
- [ ] Not started — ETA to engage counsel: ___________
**NCMEC ESP ID obtained:** [ ] Yes — stored in Secret Manager | [ ] No
**NCMEC API Key obtained:** [ ] Yes — stored in Secret Manager | [ ] No
**Assigned legal contact:** ___________

---

### A-02: Minimum Age Floor
**Source:** Audit Q-23 / Checklist C-11
**Question:** What is Amen's minimum supported age? The app currently relies on self-reported birth year with no verification. COPPA (US) sets 13 as the floor. GDPR-K (EU) requires parental consent for children under 16 in certain member states. If the app will be available in the EU, different floors may apply by jurisdiction.
**Recommended:** 13 (US COPPA floor). Hard-block account creation for any self-reported age under 13. If EU launch is planned, treat 16 as the floor or implement jurisdiction detection.
**Decision:**
- [ ] 13 (COPPA — US only launch)
- [ ] 16 (GDPR-K — EU launch included)
- [ ] 18 (conservative / adults-only)
- [ ] Other: ___________ — justification: ___________
**EU launch planned:** [ ] Yes | [ ] No | [ ] Undecided
**Notes:** ___________

---

### A-03: Guardian / Parental Consent for Ages 13–15
**Source:** Audit Q-11, Q-22 / Checklist C-12, M-11
**Question:** Is verifiable parental consent required for accounts aged 13–15? COPPA requires "verifiable parental consent" before collecting personal data from children under 13 in the US. For ages 13–15, COPPA does not mandate it but the FTC's "actual knowledge" standard may apply if the app is directed at minors. The current `isGuardianApprovedContact()` function returns `true` (allow) when no guardian approval document exists — meaning the guardian gate is currently a no-op.
**Recommended:** Require verifiable parental consent for all accounts self-reporting age 13–15. Invert `isGuardianApprovedContact()` to fail-closed (deny) when no approval document exists. Block DMs, space invites, and public discovery until consent is confirmed.
**Decision:**
- [ ] Required — all 13–15 accounts gated until guardian approves
- [ ] Required — gated only for DMs and Sanctuaries
- [ ] Not required — justification: ___________
**Guardian permission model (must select one):**
- [ ] Read-only oversight (guardian can read all messages but not approve/deny)
- [ ] Active approve/deny (guardian receives invite and must approve each contact)
- [ ] Emergency-only (guardian notified only when safety flag is triggered)
**Notes:** ___________

---

### A-04: Designated Safety Officer
**Source:** Audit Q-3, Q-21 / Checklist H-02
**Question:** Who is the safety officer assigned to receive CSAM escalations, manage NCMEC submissions, and hold legal hold review authority? This person must receive the `legalReviewer` Firebase custom claim. The claim is referenced in the `legalHolds` Firestore rule but is not defined or minted anywhere in the current codebase.
**Recommended:** Appoint before any beta launch. The safety officer must be reachable 24/7 during launch. Define the `legalReviewer` claim in the CF token-minting flow immediately.
**Decision:**
- Name: ___________
- Role/title: ___________
- Contact (24/7): ___________
- Firebase UID (for claim assignment): ___________
- `legalReviewer` claim defined in CF: [ ] Yes | [ ] No — ETA: ___________

---

### A-05: Age Verification Method
**Source:** Audit Q-23 / Checklist C-11
**Question:** What method beyond self-attestation will be used to verify age? Self-attestation alone is insufficient for COPPA compliance when actual knowledge of a minor's age exists or can be inferred.
**Recommended:** Self-attestation + phone signal (carrier age signal) for ages 16+. Third-party age verification vendor (e.g., Yoti, Incode, AgeID) for accounts self-reporting 13–15. Budget and privacy impact assessment required before vendor selection.
**Decision:**
- [ ] Self-attestation only — justification: ___________
- [ ] Self-attestation + phone carrier signal
- [ ] Third-party vendor: ___________ — contract signed: [ ] Yes | [ ] No
- [ ] Document-based (government ID) — privacy review required
- [ ] Other: ___________
**Notes:** ___________

---

### A-06: Which Firestore Rules File Is Deployed to Production
**Source:** Audit Q-1
**Question:** Two Firestore rules files exist: `AMENAPP/AMENAPP/firestore.deploy.rules` and `firestore.rules` at the repo root. The `firebase.json` comment says to change the `'firestore.rules'` field before deploying. The safety-hardening branch has modified both files but they have diverged — the `safetyAuditLog`/`guardianLinkRequests` coverage gap exists in `firestore.deploy.rules` but NOT in `firestore.rules`. It is not known which file is currently live.
**Recommended:** Run `firebase deploy --only firestore:rules --dry-run` to confirm which file `firebase.json` points to. Reconcile both files so a single canonical file is the source of truth. Verify the reconciled file includes `safetyAuditLog`, `guardianLinkRequests`, and `guardianApprovedContacts` rules before any deploy.
**Decision:**
- Canonical rules file: [ ] `firestore.rules` (root) | [ ] `firestore.deploy.rules` (AMENAPP/)
- Files reconciled: [ ] Yes | [ ] No — ETA: ___________
- `firebase.json` updated to point to canonical file: [ ] Yes | [ ] No
- Deploy verified with dry-run: [ ] Yes | [ ] No
**Notes:** ___________

---

### A-07: Storage Rules Deployment Status
**Source:** Audit Q-8 / Checklist C-05
**Question:** Is `storage.rules` actually deployed to production, or is the project running on default permissive rules? Several iOS upload paths (`post_media`, `chat_videos`, `profile_images`) are absent from `storage.rules`. If the hardened rules are live but missing these paths, those features are silently failing in production. If the rules have never been deployed, every Storage path is open to any authenticated user.
**Recommended:** Run `firebase deploy --only storage --dry-run` to confirm status. Add rules for all missing paths before deploying.
**Decision:**
- Storage rules deployment status: [ ] Deployed and current | [ ] Never deployed | [ ] Unknown
- Dry-run completed: [ ] Yes | [ ] No
- Missing paths (`post_media`, `chat_videos`, `profile_images`, `berean/ocr_queue`, `creator/users`) added: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

### A-08: CSAM Detection Pipeline Live Status
**Source:** Audit Q-26 / Checklist C-10
**Question:** Is the CSAM hash-matching or ML scan pipeline actually deployed and producing `detectionSource` values of `'ios_hash_match'` or `'cf_vision_scan'`? The `prepareCSAMEscalation()` method exists but no callers were confirmed during the audit. If the pipeline is not active, CSAM may be passing through the system without detection.
**Recommended:** Confirm end-to-end pipeline is live with a test hash before any public launch. Document the confirmed call chain from upload to `prepareCSAMEscalation()`.
**Decision:**
- CSAM detection pipeline status: [ ] Confirmed live and tested | [ ] Built but not confirmed | [ ] Not deployed
- Call chain documented: [ ] Yes — location: ___________ | [ ] No
- Last end-to-end test date: ___________
**Notes:** ___________

---

## GROUP B — BEFORE APP STORE LAUNCH
> These items must be decided and implemented before submitting to the App Store or enabling public registration.

---

### B-01: Pastor / Leader DMs to Minors
**Source:** Audit checklist H-13, H-15
**Question:** Should verified pastors and church leaders be permitted to send direct messages to minor members? Without explicit restriction, any adult with a church-leader role can DM any minor in their church.
**Recommended:** Allow only with a guardian-visible thread (guardian account can read all messages in the thread). Auto-notify guardian on first message from any non-family adult.
**Decision:**
- [ ] Guardian-visible thread required (recommended)
- [ ] Completely blocked — no adult-to-minor DMs from leaders
- [ ] No restriction — justification: ___________
**Notes:** ___________

---

### B-02: Paid Orgs and Moderation Bypass
**Source:** Audit (implicit from org trust model)
**Question:** Should paying church or organization accounts receive any bypass, reduction, or exemption from content moderation?
**Recommended:** NO. Paid status never grants moderation bypass. Moderation rules apply identically to free and paid accounts. A paying account that posts CSAM is handled identically to a free account.
**Decision:**
- [ ] Paid accounts never bypass moderation (recommended)
- [ ] Paid accounts receive modified moderation — specify: ___________ — requires legal review: [ ] Yes | [ ] No
**Notes:** ___________

---

### B-03: Minor Discoverability in Search and People Index
**Source:** Audit Q-25 / Checklist H-04, H-14
**Question:** Should users under the minimum age floor appear in people search, Algolia index, or directory features? Currently not all incremental Algolia sync paths call `shouldExcludeFromPeopleIndex()`.
**Recommended:** Minors are not discoverable by strangers. Only linked guardians and verified church admins of the minor's registered church can find them. Audit all Algolia sync paths for coverage.
**Decision:**
- [ ] Not discoverable (recommended)
- [ ] Discoverable with restrictions — specify: ___________
- [ ] Fully discoverable — justification: ___________
**Algolia sync paths audited for `shouldExcludeFromPeopleIndex()`: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

### B-04: Anonymous Prayer Requests
**Source:** Product (safety-adjacent)
**Question:** Should users be able to submit anonymous prayer requests to their feed or sanctuary? Anonymous content creates a moderation challenge — there is no identity to warn or ban.
**Recommended:** Allowed with rate limiting (max 3/day) and mandatory server-side moderation before posting. Author identity hidden from feed display but stored server-side for moderation and legal hold purposes. Crisis keywords auto-route to pastoral contact regardless of anonymous flag.
**Decision:**
- [ ] Allowed with rate limiting and moderation (recommended)
- [ ] Allowed without restriction
- [ ] Not allowed — justification: ___________
**Crisis keyword routing for anonymous requests:** [ ] Enabled | [ ] Disabled
**Notes:** ___________

---

### B-05: Moderation Appeal Response SLA
**Source:** Audit (implicit from moderation pipeline build)
**Question:** What is the committed response time for users who appeal a moderation decision (content removed, account actioned)?
**Recommended:** 5 business days for standard appeals. 24 hours for account suspension appeals.
**Decision:**
- Standard appeal SLA: ___________ business days
- Account suspension appeal SLA: ___________ hours
- Appeals handled by: [ ] Engineering on-call | [ ] Dedicated trust-and-safety team | [ ] Outsourced vendor: ___________
**Notes:** ___________

---

### B-06: Data Retention Policy
**Source:** Audit Q-20 / Checklist M-05
**Question:** How long are moderation reports, audit logs, NCMEC filings, and legal hold documents retained? Firestore TTL policies on `moderationQueue.expireAt` and `moderationDeadLetter` must be manually enabled in the Firebase Console and may not have been set.
**Recommended:** Moderation reports: 3 years. Safety audit logs: 5 years. NCMEC CyberTipline filings: indefinitely (per NCMEC agreement). Legal holds: indefinitely or until released by legal counsel. TTL policy enabled in Firebase Console.
**Decision:**
- Moderation reports: ___________ (recommended: 3 years)
- Safety audit logs: ___________ (recommended: 5 years)
- NCMEC filings: ___________ (recommended: indefinitely)
- Legal holds: ___________ (recommended: indefinitely)
- Firestore TTL policy enabled in Firebase Console: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

### B-07: Minors in Adult-Led Sanctuaries / Spaces
**Source:** Audit Q-22 / Checklist H-15
**Question:** Under what conditions may a minor be added to or join a sanctuary, space, or community room led by an adult who is not their guardian?
**Recommended:** Guardian approval required for any minor joining an adult-led space outside their registered church. Default: minor can only join spaces under their registered church's verified account. Firestore rule should require `churchVerified == true` for spaces containing minor members.
**Decision:**
- [ ] Guardian approval required for all adult-led spaces (recommended)
- [ ] Registered church spaces only — no guardian approval needed
- [ ] Open — any verified adult leader can add minors — justification: ___________
**Notes:** ___________

---

### B-08: Self-Harm and Crisis Content Protocol
**Source:** Audit (crisis routing in Berean AI audit findings)
**Question:** When content matching self-harm or suicidal ideation patterns is detected (in posts, DMs, prayer requests, or Berean AI queries), what is the response protocol?
**Recommended:** Block content from public posting. Show 988 Suicide and Crisis Lifeline resources inline. If account is church-linked and the church has a designated pastoral contact, notify that contact via a private CF-written Firestore document (not a push notification, to avoid unintended disclosure). Log to safety audit log. Do not delete — preserve for potential legal hold.
**Decision:**
- [ ] Accept recommended protocol
- [ ] Modify — specify: ___________
- [ ] 988 resources only, no pastoral notification
**Pastoral notification:** [ ] Enabled by default | [ ] Opt-in by church | [ ] Disabled
**Notes:** ___________

---

### B-09: Unauthenticated Read of Public Posts (OPEN-5)
**Source:** Audit Q-6
**Question:** Public posts are currently readable by unauthenticated users (the OPEN-5 flag is acknowledged in the Firestore rules header and left open). This enables SEO indexing but also means minors' public posts are readable without an account, raising COPPA risk.
**Recommended:** Make a deliberate product decision. If SEO is a priority, implement a content delivery proxy (CF-served) that strips author identity and age-sensitive metadata for unauthenticated reads rather than exposing raw Firestore documents. If SEO is not a launch priority, gate all reads behind `isSignedIn()`.
**Decision:**
- [ ] Gate all reads behind authentication — disable unauthenticated reads
- [ ] Allow unauthenticated reads via CF proxy (strips PII) — ETA for proxy build: ___________
- [ ] Allow unauthenticated reads directly from Firestore — justification: ___________
**SEO is a launch requirement:** [ ] Yes | [ ] No | [ ] Undecided
**Notes:** ___________

---

### B-10: MusicContentLayer Firestore Rules Coverage
**Source:** Audit Q-7 / Checklist (implicit)
**Question:** The `RightsMonetizationService`, `FaithMusicGraphService`, and `AmenPulseDigestService` files are modified on the safety-hardening branch and likely write to music-specific Firestore collections. These collections were not audited for rules coverage.
**Recommended:** Enumerate all Firestore collections written by the MusicContentLayer. Add explicit rules for each. Default-deny any path not covered.
**Decision:**
- MusicContentLayer collections audited: [ ] Yes | [ ] No — ETA: ___________
- Firestore rules added for each: [ ] Yes | [ ] No
**Collections identified (list when complete):** ___________
**Notes:** ___________

---

### B-11: moderationQueue End-to-End iOS Client Test
**Source:** Audit Q-2 / Checklist C-02
**Question:** Has the `moderationQueue 'allow create: if isAdminSDK()'` restriction been tested end-to-end with actual iOS clients? The silently-failing `try?` calls in `AmenChildSafetyService`, `AmenModerationService`, and `AntiHarassmentEngine` mean no runtime error surfaces if writes are being rejected — this failure mode may have gone completely undetected.
**Recommended:** Before any deploy, run a manual test from a real iOS device: trigger a moderation event, confirm the queue document is created, and confirm the CF pipeline picks it up. Route all iOS-originated creates through a CF callable.
**Decision:**
- End-to-end test completed: [ ] Yes — date: ___________ | [ ] No — ETA: ___________
- iOS writes routed through CF callable: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

### B-12: `legalReviewer` Custom Claim Definition
**Source:** Audit Q-3 / Checklist H-02
**Question:** The `legalHolds` Firestore rule references a `legalReviewer` custom claim, but no Cloud Function is confirmed to define or mint this claim. If the claim is never minted, the `legalHolds` rule may never permit legitimate access — or worse, may be written with a fallback that permits wider access.
**Recommended:** Define `legalReviewer` in the CF admin token-minting flow before deploying the `legalHolds` rule. Assign the claim only to the designated safety officer (A-04).
**Decision:**
- Claim defined in CF: [ ] Yes — function name: ___________ | [ ] No — ETA: ___________
- Claim assigned to safety officer: [ ] Yes | [ ] No
**Notes:** ___________

---

### B-13: Guardian Approval Scope (OPEN-2)
**Source:** Audit Q-11, Q-22 / Checklist C-12
**Question:** The `isGuardianApprovedContact()` function currently returns `true` (allow) when the approval document does not exist. Until OPEN-2 is resolved, the entire guardian DM gate is non-functional. A product decision is required on what "guardian approval" means in practice.
**Recommended:** Invert the default to fail-closed (deny when document does not exist). Implement the `onDocumentCreated` CF for `/guardianLinkRequests` (Q-24). Guardian model should be active approve/deny, not passive.
**Decision:**
- Guardian permission model (must match A-03 decision):
  - [ ] Read-only oversight
  - [ ] Active approve/deny (recommended)
  - [ ] Emergency-only notification
- `isGuardianApprovedContact()` inverted to fail-closed: [ ] Yes | [ ] No — ETA: ___________
- `/guardianLinkRequests` CF implemented: [ ] Yes — function name: ___________ | [ ] No — ETA: ___________
**Notes:** ___________

---

### B-14: Berean AI Access Policy for Minors
**Source:** Audit AI system audit findings / Memory entry project_berean_audit_2026_06_02.md
**Question:** What is the access policy for Berean AI features when the authenticated user is a minor? Currently there is no confirmed age gate on Berean AI callables.
**Recommended:** Berean AI spiritual guidance features available to all ages. Berean AI features that involve counseling-adjacent responses (grief, mental health, relationships) restricted to 16+ or require guardian visibility. Crisis routing always enabled regardless of age.
**Decision:**
- Berean AI fully available to all ages: [ ] Yes | [ ] No
- Counseling-adjacent features restricted to age: ___________
- Guardian visibility on Berean AI sessions for minors: [ ] Required | [ ] Optional | [ ] Not required
**Notes:** ___________

---

### B-15: Prayer Request Indexing and Search Policy
**Source:** Product (privacy-adjacent)
**Question:** Are prayer requests (including anonymous ones) indexed in Algolia or any full-text search system? Prayer requests may contain highly sensitive personal information including health status, relationship problems, and crisis situations.
**Recommended:** Prayer requests are never indexed in Algolia or any external search system. Server-side full-text search (Firestore only) within the user's own church or sanctuary only. Anonymous prayer requests: no search index at all.
**Decision:**
- Prayer requests indexed in Algolia: [ ] Yes | [ ] No (recommended)
- Anonymous prayer requests indexed: [ ] Yes | [ ] No (recommended: never)
- Prayer requests searchable within church/sanctuary: [ ] Yes | [ ] No
**Notes:** ___________

---

### B-16: `chat_videos` Storage Path Write Access
**Source:** Audit Q-12 / Checklist H-07
**Question:** The `chat_videos` path is used for DM video uploads but has no Storage rule. If any authenticated user can write to any `conversationId` path, non-participants can inject media into other users' conversations.
**Recommended:** Add a Storage rule that restricts write to conversation participants only, enforces MIME type allowlist, and caps file size. Require participant validation to be performed by a CF callable rather than client-side.
**Decision:**
- Storage rule for `chat_videos` added: [ ] Yes | [ ] No — ETA: ___________
- Participant check: [ ] CF-enforced | [ ] Client-enforced (not recommended)
- Max file size cap: ___________ MB
**Notes:** ___________

---

### B-17: `moderateUploadedImage` CDN Caching Window
**Source:** Audit Q-9 / Checklist H-05
**Question:** What is the latency between a file being uploaded to `profilePhotos/` and the `moderateUploadedImage` CF completing its SafeSearch check? If this window exceeds 5 seconds under normal load, a CDN may cache the public URL before removal, making deletion insufficient.
**Recommended:** Implement pre-moderation: do not return a public download URL until the CF approves the image. Move `profilePhotos` public read to authenticated-only during the quarantine window. Measure CF latency under load before deciding.
**Decision:**
- CF latency measured: [ ] Yes — p99 latency: ___________ ms | [ ] No — ETA to measure: ___________
- Pre-moderation URL gating implemented: [ ] Yes | [ ] No — ETA: ___________
- Public read gated during quarantine: [ ] Yes | [ ] No
**Notes:** ___________

---

### B-18: Direct Client Writes to Comments Collection
**Source:** Audit Q-18 / Checklist H-10
**Question:** Are Firestore security rules preventing direct client writes to `posts/{postId}/comments/{commentId}` without going through the `addComment` callable? If not, the comment moderation gap can be exploited without any server-side enforcement — a client can bypass moderation entirely.
**Recommended:** `allow create` on the comments collection should require the write to originate from the Admin SDK (CF callable path). Client direct writes should be denied.
**Decision:**
- Firestore rule blocks direct client writes to comments: [ ] Yes — confirmed by test | [ ] No — ETA: ___________
- `moderateComment` trigger implemented: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

### B-19: `one_users/witnesses` Enforcement CF
**Source:** Audit Q-5 / Checklist H-03
**Question:** The `one_users/witnesses` subcollection comment says "CF validates both-party acceptance" but no CF callable was found during the audit. If no CF exists, the both-party acceptance constraint is not enforced before the Firestore write — only after (or never).
**Recommended:** Identify or implement the CF. Restrict client write to `allow create: if request.auth.uid == uid`. Move all other writes to CF-only. Both-party acceptance must be enforced before the document is written.
**Decision:**
- CF identified: [ ] Yes — function name: ___________ | [ ] No — build required
- Firestore rule restricts write: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

### B-20: `/users/{userId}` Minor Status Exposure
**Source:** Audit Q-4 / Checklist H-04, M-10
**Question:** Any signed-in user can currently read any other user's `/users/{uid}` document, which includes `ageTier`, `isMinor`, `birthYear`, and `churchId`. An adversary can read another user's `ageTier` to learn their minor status, then target them accordingly.
**Recommended:** Move `ageTier`, `isMinor`, and `birthYear` to a `/users/{uid}/private/` subcollection with owner-read-only and CF-write-only rules. Remove these fields from the public document.
**Decision:**
- Fields moved to private subcollection: [ ] Yes | [ ] No — ETA: ___________
- iOS and CF callers of `isMinorAccount()` updated to new path: [ ] Yes | [ ] No
**Notes:** ___________

---

### B-21: App Check Project-Level Enforcement
**Source:** Audit Q-35 / Checklist H-18, H-19
**Question:** Firebase App Check can be bypassed if the project-level enforcement toggle is off in the Firebase Console, even when individual functions declare `enforceAppCheck: true`. Additionally, 33+ Berean OS and Selah Cloud Functions currently have `enforceAppCheck: false`.
**Recommended:** Enable App Check enforcement in the Firebase Console project settings. Enable `enforceAppCheck: true` on all Berean OS and Selah CFs. Use `FUNCTIONS_EMULATOR` guard for local dev only.
**Decision:**
- Firebase Console App Check enforcement enabled: [ ] Yes | [ ] No — ETA: ___________
- Berean OS / Selah CFs migrated to `enforceAppCheck: true`: [ ] Yes | [ ] No — ETA: ___________
- App Check migration ticket status: ___________
**Notes:** ___________

---

### B-22: Stripe Webhook Canonical File
**Source:** Audit Q-29 / Checklist H-17, M-14
**Question:** Two Stripe webhook files exist: legacy `stripeWebhook.js` at the repo root and `stripe/stripeWebhook.js`. It is not confirmed which is deployed. If both are deployed, duplicate event processing creates idempotency and financial integrity risk.
**Recommended:** Trace the `stripeFunctions.js` import chain. Remove the legacy file. Route all Stripe webhook traffic to `stripe/stripeWebhook.js`.
**Decision:**
- Active Stripe webhook file: [ ] `stripe/stripeWebhook.js` | [ ] root `stripeWebhook.js` | [ ] Unknown
- Legacy file removed: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

### B-23: `safeMessagingGateway.js` Direct Write Bypass
**Source:** Audit Q-33 / Checklist M-13
**Question:** The `safeMessagingGateway.js` performs an `isBanned` check before writing DM messages. However, if Firestore security rules do not also block direct client writes to the messages collection, a client can bypass the gateway entirely and write messages without the ban check.
**Recommended:** Confirm Firestore rules deny all direct client writes to the DM messages collection. Update the `senderData.isBanned` check to use `admin.auth().getUser(uid).disabled` for real-time ban status.
**Decision:**
- Firestore rules block direct client writes to DM messages: [ ] Yes — confirmed by test | [ ] Unknown — needs audit
- Ban check updated to use `admin.auth().getUser()`: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

### B-24: RBAC Firestore Path Consistency
**Source:** Audit Q-34
**Question:** The iOS `AmenRBACService.resolveRole` uses path `roles/{contextType}/{contextId}/members/{uid}/membership`. It is not confirmed whether Cloud Functions use the same path or a different schema. Inconsistency would mean CF-side RBAC checks use different data than iOS-side checks.
**Recommended:** Document the canonical RBAC Firestore path. Confirm that all CFs reading roles use the same path as the iOS client. Fix any divergence.
**Decision:**
- Canonical RBAC path confirmed: [ ] Yes | [ ] No — ETA: ___________
- iOS and CF paths consistent: [ ] Yes | [ ] No
**Notes:** ___________

---

### B-25: `backfillUsernameLookup` Admin Claim Guard
**Source:** Audit checklist H-16
**Question:** The `backfillUsernameLookup` callable has no admin-claim guard, meaning any authenticated user can invoke it and trigger a bulk username lookup backfill.
**Recommended:** Add `admin` custom claim check as the first line of the callable before any Firestore operations.
**Decision:**
- Admin claim guard added: [ ] Yes | [ ] No — ETA: ___________
**Notes:** ___________

---

## GROUP C — POST-LAUNCH POLICY
> These items do not block the initial deploy but must be decided and documented within 90 days of launch.

---

### C-01: Moderation Team Staffing Model
**Question:** Who performs human moderation review for the appeal queue, escalated AI-flagged content, and legal hold requests?
**Decision:**
- [ ] Internal trust-and-safety team (headcount: ___)
- [ ] Outsourced vendor: ___________
- [ ] Hybrid — specify: ___________
**Target date to staff:** ___________

---

### C-02: Human vs AI Review Ratio
**Question:** What percentage of flagged content items require human review vs. automated resolution?
**Decision:**
- CSAM: [ ] 100% human | [ ] AI-only — (CSAM must be 100% human-reviewed per NCMEC guidance)
- Self-harm: [ ] 100% human | [ ] AI with human escalation threshold
- Hate speech / harassment: ___________ % human review
- Routine spam / low-severity: [ ] AI-only
**Notes:** ___________

---

### C-03: Long-Term Age Assurance Vendor Selection
**Question:** Which third-party age verification vendor will be used for 13–15 accounts once the platform reaches scale?
**Decision:**
- Vendor shortlist: ___________
- Selection deadline: ___________
- Privacy impact assessment required: [ ] Yes | [ ] No

---

### C-04: Berean AI Access Policy for Minors (Detail)
**Question:** (See B-14 for the blocking version.) Post-launch: as Berean AI capabilities expand, what is the ongoing review cadence for minor access policies?
**Decision:**
- Review cadence: ___________ (recommended: quarterly)
- Owner: ___________

---

### C-05: Prayer Request Indexing and Search Policy (Detail)
**Question:** (See B-15 for the blocking version.) Post-launch: as the platform grows, are prayer request archives made available for research, pastoral analytics, or partner access?
**Decision:**
- Prayer archives available for pastoral analytics: [ ] Yes | [ ] No
- Third-party research access: [ ] Never | [ ] With consent | [ ] Anonymized aggregate only
- Policy review cadence: ___________

---

### C-06: `resolveUsernameToEmail` Migration Timeline
**Source:** Audit L-02
**Question:** The legacy `resolveUsernameToEmail` CF exposes user email to any caller who knows a valid username, enabling email harvesting. `signInWithUsername` was built to replace it. A timeline for migrating all iOS callers and removing the export is needed.
**Decision:**
- iOS callers migrated to `signInWithUsername`: [ ] Yes | [ ] No — ETA: ___________
- `resolveUsernameToEmail` export removed: [ ] Yes | [ ] No — ETA: ___________

---

### C-07: Phone Auth Rate-Limit Gen2 Migration
**Source:** Audit L-03
**Question:** `phoneAuthRateLimit.js` functions use the Gen1 `runWith` pattern without `defineSecret` migration, providing lower process isolation for functions handling phone number hashes.
**Decision:**
- Migration to Firebase Functions v2 with `defineSecret`: [ ] Complete | [ ] In progress — ETA: ___________

---

### C-08: Legacy `users/{uid}/profileImages/` Path Retirement
**Source:** Audit Q-13
**Question:** The legacy path uses `allow read: if isSignedIn()` while the newer `profilePhotos/{uid}/{photoId}` uses `allow read: if true` (unauthenticated). Both paths may be in active use with inconsistent access models.
**Decision:**
- Legacy path still in active use: [ ] Yes | [ ] No | [ ] Unknown — ETA to confirm: ___________
- Migration to `profilePhotos/` path: [ ] Complete | [ ] In progress | [ ] Not started

---

### C-09: `withRetry` HTTP Status Inspection
**Source:** Audit Q-14
**Question:** `withRetry` in `retryHelper.js` may only retry on caught exceptions, not on HTTP 429/5xx status codes. This means transient NIM API failures in `moderateUGC.js` may not be retried.
**Decision:**
- `withRetry` inspects HTTP status codes: [ ] Yes — confirmed | [ ] No — must be fixed
- Fix ETA: ___________

---

### C-10: `aiModeration.moderateContent` Fail-Closed Audit
**Source:** Audit Q-15
**Question:** The `aiModeration.moderateContent` export overwrites `contentModeration` at `index.js` line 300. Its fail-closed posture (whether it uses the `!/unsafe/i.test` fallback or a proper exact-match check) has not been confirmed.
**Decision:**
- `aiModeration.moderateContent` fail-closed posture confirmed: [ ] Yes | [ ] No — ETA: ___________

---

### C-11: Hidden Comment Moderation Trigger Confirmation
**Source:** Audit Q-16
**Question:** No server-side comment moderation trigger was found in the `functions/` directory. It is possible a trigger exists in `Backend/functions/src/index.ts` or `v2functions.js`.
**Decision:**
- `Backend/functions/src/index.ts` searched for comment trigger: [ ] Yes — found: ___________ | [ ] Yes — not found | [ ] No
- If not found: `moderateComment` trigger added per checklist H-10: [ ] Yes | [ ] No — ETA: ___________

---

### C-12: Gen-1 Quota Impact on `moderateDMMessage`
**Source:** Audit Q-17
**Question:** The `moderateDMMessage` trigger is Gen-1. If Cloud Run quota exhaustion is affecting other Gen-1 functions, DM moderation reliability may be degraded.
**Decision:**
- Gen-1 quota impact assessed: [ ] Yes — findings: ___________ | [ ] No — ETA: ___________
- Migration to Gen-2 planned: [ ] Yes — ETA: ___________ | [ ] No

---

### C-13: Firestore TTL Policy Enablement
**Source:** Audit Q-20 / Checklist M-05 (footnote)
**Question:** Firestore TTL policies on `moderationQueue.expireAt` and `moderationDeadLetter` require a manual Firebase Console step. It is not confirmed this has been done.
**Decision:**
- Firestore TTL policy enabled for `moderationQueue`: [ ] Yes — confirmed in Console | [ ] No — ETA: ___________
- Firestore TTL policy enabled for `moderationDeadLetter`: [ ] Yes — confirmed in Console | [ ] No — ETA: ___________

---

### C-14: Firestore `POLICY_VERSION` Stamping
**Source:** Checklist M-09
**Question:** Moderation subdocuments and queue entries are not stamped with a `POLICY_VERSION` constant, making it impossible to audit which policy version produced a given moderation decision.
**Decision:**
- `POLICY_VERSION` constant added to `moderateUGC.js`: [ ] Yes | [ ] No — ETA: ___________
- Applied to all moderation subdocuments and queue entries: [ ] Yes | [ ] No

---

### C-15: Admin Console `ageTier` Override Protection
**Source:** Audit Q-28
**Question:** The `allow update: if false` Firestore rule applies only to clients, not to the Firebase Console or Admin SDK. An admin with console access could manually set `ageTier: 'tierD'` for a minor, bypassing the I-8 invariant.
**Decision:**
- Documented policy prohibiting console `ageTier` overrides for minor accounts: [ ] Yes | [ ] No — ETA: ___________
- Audit log CF for all `ageTier` writes: [ ] Yes | [ ] No — ETA: ___________

---

## AUDIT OPEN QUESTIONS — ENGINEERING DECISIONS REQUIRED
> These 35 questions from the audit must each receive a documented answer. Assigned owners and ETAs are required for all items marked OPEN.

| Q# | Question (summary) | Owner | Status | ETA |
|---|---|---|---|---|
| Q-1 | Which Firestore rules file is deployed to production — `firestore.deploy.rules` or `firestore.rules`? | | OPEN | |
| Q-2 | Has `moderationQueue` create been tested end-to-end from an iOS client? | | OPEN | |
| Q-3 | Is `legalReviewer` custom claim defined in any CF? | | OPEN | |
| Q-4 | Do any CFs read `/users/{userId}` fields for auth decisions, exposing minor status? | | OPEN | |
| Q-5 | Which CF enforces `one_users/witnesses` both-party acceptance? | | OPEN | |
| Q-6 | Is unauthenticated post read intentional? Product decision on OPEN-5. | | OPEN | |
| Q-7 | Are MusicContentLayer write collections covered by Firestore rules? | | OPEN | |
| Q-8 | Is `storage.rules` deployed to production? | | OPEN | |
| Q-9 | What is `moderateUploadedImage` p99 latency under load? CDN caching risk? | | OPEN | |
| Q-10 | Is `NCMEC_SUBMISSION_ENABLED` set to `'true'` in production? | | OPEN | |
| Q-11 | `isGuardianApprovedContact()` returns true when doc missing — T&S decision on OPEN-2 | | OPEN | |
| Q-12 | Who has write access to `chat_videos/{conversationId}/`? | | OPEN | |
| Q-13 | Is legacy `users/{uid}/profileImages/` path still active? Inconsistent access model. | | OPEN | |
| Q-14 | Does `withRetry` inspect HTTP status codes or only exceptions? | | OPEN | |
| Q-15 | Does `aiModeration.moderateContent` use fail-closed pattern? | | OPEN | |
| Q-16 | Is there a hidden comment moderation trigger in `Backend/functions/src/index.ts`? | | OPEN | |
| Q-17 | Is Gen-1 quota exhaustion degrading `moderateDMMessage` reliability? | | OPEN | |
| Q-18 | Do Firestore rules block direct client writes to comments collection? | | OPEN | |
| Q-19 | Has a real NCMEC API key been configured for text-detected CSAM in `moderatePost.js`? | | OPEN | |
| Q-20 | Is Firestore TTL policy enabled on `moderationQueue` and `moderationDeadLetter`? | | OPEN | |
| Q-21 | Who is the NCMEC SLA key holder? What is max time to file? (OPEN-4) | | OPEN | |
| Q-22 | Guardian tools scope decision (OPEN-2) — read-only, approve/deny, or emergency-only? | | OPEN | |
| Q-23 | Minimum age floor — 13 (COPPA) or 16 (GDPR-K)? (OPEN-1) | | OPEN | |
| Q-24 | Is `onDocumentCreated` CF for `/guardianLinkRequests` implemented anywhere? | | OPEN | |
| Q-25 | Do all incremental Algolia sync paths call `shouldExcludeFromPeopleIndex()`? | | OPEN | |
| Q-26 | Is the CSAM detection pipeline deployed and producing `detectionSource` values? | | OPEN | |
| Q-27 | Is a report/flag button present on every minor-visible surface? | | OPEN | |
| Q-28 | Can an admin with console access bypass I-8 by setting `ageTier: 'tierD'` for a minor? | | OPEN | |
| Q-29 | Which `stripeWebhook.js` is live? Trace the `stripeFunctions.js` import chain. | | OPEN | |
| Q-30 | Current App Check migration ticket status for 33+ Berean OS functions? | | OPEN | |
| Q-31 | Do `covenantFunctions.js` and `spacesLivekitFunctions.js` do server-side RBAC reads? | | OPEN | |
| Q-32 | Has NCMEC ESP registration been initiated? Timeline for `TODO_ESP_ID`? | | OPEN | |
| Q-33 | Do Firestore rules block direct client writes to DM messages collection? | | OPEN | |
| Q-34 | Canonical RBAC Firestore path — same in CFs and iOS `AmenRBACService`? | | OPEN | |
| Q-35 | Is Firebase project-level App Check enforcement toggle enabled in the console? | | OPEN | |

---

## SIGN-OFF REQUIRED BEFORE DEPLOY

All items in GROUP A must have a completed decision before this document can be signed.

| Role | Name | Signature | Date |
|---|---|---|---|
| Founder / CEO | | | |
| Legal Counsel | | | |
| Safety Officer | | | |
| Engineering Lead | | | |

---

## REVISION HISTORY

| Date | Author | Change |
|---|---|---|
| 2026-06-11 | (generated from SAFETY_AUDIT.md) | Initial draft — all items OPEN |

---

*This document is a safety artifact. Changes require sign-off from at least two of the four roles in the sign-off table above. Do not delete or rewrite audit question references — append resolutions as new rows in the revision history.*

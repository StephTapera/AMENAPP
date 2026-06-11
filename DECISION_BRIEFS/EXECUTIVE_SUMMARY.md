# Safety Decision Executive Summary
**For:** Owner of the Amen App
**Prepared by:** Launch Readiness Swarm — Agent 3 (Decision Counsel Briefer)
**Date:** 2026-06-11
**Branch:** safety-hardening
**Source doc:** DECISION_DOC_SAFETY.md (35 decisions)

---

## Read This First

This document summarizes all 35 safety decisions required before, at, and after launch. Every decision in GROUP A is a hard blocker. The safety-hardening branch MUST NOT be deployed to production until every A-item has a signed decision and the corresponding code change is merged.

---

## Critical Path to Launch (Three Actions Required Today)

**1. A-01 — NCMEC Registration: ENGAGE AN ATTORNEY TODAY.**
Federal criminal liability under 18 U.S.C. § 2258A. The code is ready (queue-only pipeline in `ncmecReporter.js`, full `cyberTiplineInterface.js`), but `TODO_ESP_ID` and `TODO_ESP_API_KEY` are literal placeholder strings. No live report can be filed until registration is complete. Do not set `NCMEC_SUBMISSION_ENABLED=true` until credentials are in Firebase Secret Manager and counsel has approved the submission procedure.

**2. A-02 — Minimum age floor: DECIDE 13 OR 16.**
`ageTier.js` is ready for either. Choosing 13 means US-only launch for now. Choosing 16 means GDPR-K compliance is built in. One configuration value to change in `ageTier.js`. If EU launch is ever planned, changing from 13 to 16 later requires a migration of existing minor accounts.

**3. A-03 — Guardian consent model: FIX THE FAIL-OPEN BUG.**
`isGuardianApprovedContact()` in `AmenChildSafetyService.swift` line 566 returns `true` when no guardian document exists. This is documented as OPEN-2. In production this means every 13-year-old's DMs are ungated by the guardian check. One line change: `return true` → `return false`. This fix must follow the A-03 decision on which guardian model to use.

---

## WARNING: Safety Deploy Blockers

The following 5 decisions from DECISION_DOC_SAFETY.md Group A must be answered before
deploying the safety-hardening branch. They are the highest-priority items on this board.

- **A-01 — NCMEC Registration:** Engage attorney TODAY. Do not enable live NCMEC submission until ESP credentials are in Firebase Secret Manager. (Criminal liability: 18 U.S.C. § 2258A)
- **A-02 — Minimum Age Floor:** Decide 13 (US only) or 16 (EU included). Add server-side creation block when `ageTier === "blocked"`.
- **A-03 — Guardian Consent + OPEN-2 Bug:** Invert `isGuardianApprovedContact()` line 566 from fail-open to fail-closed. Select guardian permission model (active approve/deny recommended).
- **A-04 — Safety Officer:** Appoint a named person with 24/7 reachability. Add `setLegalReviewerClaim` CF — without it, no one can read NCMEC queued reports.
- **A-05 — Age Verification Method:** Decide on method beyond self-attestation for 13–15 accounts. Third-party vendor (Yoti/AgeID/Incode) recommended; budget and privacy review required.

Full decision worksheets: DECISION_BRIEFS/A-SAFETY-BLOCKERS.md

---

## GROUP A — Answer-Now Decisions (8 Items — HARD BLOCKERS)

| ID | Plain-language question | Recommended answer |
|---|---|---|
| A-01 | Has legal counsel been engaged to register with NCMEC as an ESP? | Engage attorney TODAY; do not enable live NCMEC submission without credentials |
| A-02 | What is the minimum supported age: 13, 16, or 18? | 13 for US-only launch; 16 if EU launch is planned |
| A-03 | Is guardian/parental consent required for ages 13–15? | Yes — active approve/deny model; fix fail-open bug in `isGuardianApprovedContact()` |
| A-04 | Who is the designated safety officer? | Appoint a named person before beta; define `legalReviewer` Firebase custom claim |
| A-05 | What age verification method beyond self-attestation will be used? | Self-attestation + phone signal for 16+; third-party vendor for 13–15 |
| A-06 | Which Firestore rules file (`firestore.rules` or `firestore.deploy.rules`) is canonical? | Run dry-run to confirm; reconcile to one file; update `firebase.json` |
| A-07 | Is `storage.rules` actually deployed to production? | Run dry-run; add missing paths (`chat_videos`, `post_media`, `profile_images`) |
| A-08 | Is the CSAM detection pipeline deployed and end-to-end tested? | Confirm with test hash before any public launch; document the call chain |

---

## GROUP B — Before-Launch Decisions (17 Items)

All must be decided and implemented before App Store submission or public registration.

| ID | Plain-language question | Recommended answer |
|---|---|---|
| B-01 | Can pastors DM minor members? | Guardian-visible thread only; auto-notify guardian on first message |
| B-02 | Do paid church accounts get moderation bypass? | NO — paid status never grants moderation bypass |
| B-03 | Do minors appear in people search and Algolia? | Not discoverable; audit all Algolia sync paths |
| B-04 | Are anonymous prayer requests allowed? | Yes — with rate limit (3/day), server-side moderation, server-side identity stored |
| B-05 | What is the appeal response SLA? | 5 business days standard; 24 hours for account suspension |
| B-06 | How long are moderation reports retained? | Moderation: 3yr; audit logs: 5yr; NCMEC filings: indefinitely; legal holds: indefinitely |
| B-07 | Can minors join adult-led spaces outside their church? | Guardian approval required; restrict to church-verified spaces by default |
| B-08 | What happens when self-harm content is detected? | Block post; show 988 resources; notify pastoral contact privately; preserve (don't delete) |
| B-09 | Are public posts readable by unauthenticated users? | Gate behind auth for launch; CF proxy if SEO is required |
| B-10 | Are MusicContentLayer Firestore collections covered by rules? | Enumerate all collections; add explicit rules; default-deny |
| B-11 | Has `moderationQueue` been tested end-to-end from an iOS client? | Test before deploy; route iOS writes through CF callable |
| B-12 | Where is the `legalReviewer` custom claim minted? | Add `setLegalReviewerClaim` CF; assign to safety officer |
| B-13 | What does "guardian approval" mean in practice? | Active approve/deny; invert `isGuardianApprovedContact()` to fail-closed |
| B-14 | Can minors access all Berean AI features? | Spiritual guidance: all ages; counseling-adjacent: 16+ or guardian-visible |
| B-15 | Are prayer requests indexed in Algolia? | Never indexed externally; no search index for anonymous requests |
| B-16 | Is there a Storage rule for `chat_videos`? | Add rule; CF-enforced participant check; MIME allowlist; file size cap |
| B-17 | Can CDN cache a profile photo before moderation completes? | Implement pre-moderation URL gating; measure CF p99 latency |
| B-18 | Can clients write directly to comments without going through `addComment`? | Confirm Firestore rule blocks direct client writes; add `moderateComment` trigger |
| B-19 | Which CF enforces `one_users/witnesses` both-party acceptance? | Identify or implement; restrict direct client write |
| B-20 | Can any user read another user's `ageTier` / `isMinor` / `birthYear`? | Move to `/users/{uid}/private/` subcollection; owner-read-only |
| B-21 | Is Firebase App Check enforcement enabled project-wide? | Enable in Console; migrate 33+ Berean OS / Selah CFs to `enforceAppCheck: true` |
| B-22 | Which `stripeWebhook.js` is canonical? | `stripe/stripeWebhook.js`; delete root copy |
| B-23 | Can a banned user bypass `safeMessagingGateway.js`? | Confirm Firestore rule blocks direct DM writes; update ban check to real-time |
| B-24 | Does iOS RBAC path match CF RBAC path? | Confirm and document canonical path; fix any divergence |
| B-25 | Does `backfillUsernameLookup` have an admin claim guard? | Guard appears present in code; confirm deployed version matches |

---

## GROUP C — Post-Launch Decisions (15 Items, 90-day window)

| ID | Plain-language question | Recommended answer |
|---|---|---|
| C-01 | Who performs human moderation review? | Safety officer for CSAM/legal holds; outsourced vendor for standard appeals |
| C-02 | What % of flagged content requires human review? | CSAM: 100%; self-harm: AI + human escalation; spam: AI-only |
| C-03 | Which age verification vendor will be used at scale? | Evaluate Yoti/AgeID/Incode within 60 days; Privacy Impact Assessment required |
| C-04 | How often is Berean AI minor access policy reviewed? | Quarterly; tag each new capability with minimum age tier |
| C-05 | Are prayer archives used for research or analytics? | Aggregate anonymized analytics only; no third-party access |
| C-06 | When is `resolveUsernameToEmail` removed? | Migrate all callers to `signInWithUsername` within 60 days; remove CF within 90 |
| C-07 | When is `phoneAuthRateLimit.js` migrated to Gen2? | Within 90 days |
| C-08 | Is the legacy `profileImages/` Storage path still active? | Confirm; migrate to `profilePhotos/`; align access model |
| C-09 | Does `withRetry` retry on HTTP 429/5xx? | Update to inspect HTTP status codes; add exponential backoff |
| C-10 | Does `aiModeration.moderateContent` fail closed? | Confirm exact-match pattern; fix from regex to `result === "safe"` if needed |
| C-11 | Is there a comment moderation trigger in `Backend/functions/src/index.ts`? | Search; implement `moderateComment` trigger if not found |
| C-12 | Is Gen-1 quota degrading `moderateDMMessage` reliability? | Monitor 60 days post-launch; migrate to Gen-2 if quota issues found |
| C-13 | Are Firestore TTL policies enabled for `moderationQueue`? | Enable in Firebase Console within 30 days |
| C-14 | Are moderation documents stamped with `POLICY_VERSION`? | Add constant to `moderateUGC.js`; stamp all writes |
| C-15 | Can an admin bypass the `ageTier` rule via Firebase Console? | Document policy; add audit log CF for all `ageTier` writes |

---

## Legal Counsel Required — Four Items

These four decisions require a lawyer before you can finalize them:

**1. A-01 — NCMEC registration** (18 U.S.C. § 2258A)
Determine ESP status, initiate registration, obtain credentials, understand safe harbor under § 2258B.

**2. A-03 — COPPA verifiable parental consent** (15 U.S.C. § 6501; 16 C.F.R. Part 312)
The guardian permission model you choose must satisfy the FTC's "verifiable parental consent" standard. Counsel must advise which of the three models (read-only, active approve/deny, emergency-only) satisfies the standard.

**3. A-05 — Age verification method** (COPPA; FTC guidance)
The FTC's "actual knowledge" standard determines whether self-attestation alone is sufficient. Counsel should advise on the acceptable verification methods for your platform.

**4. A-02 (if EU launch is planned)** — GDPR-K parental consent
GDPR Article 8 requires parental consent for children under the member-state-specific age of digital consent (13–16). Counsel should advise on the jurisdiction detection approach.

---

## Sign-Off Checklist Before Deploy

- [ ] All 8 GROUP A items have written decisions signed by Founder + Legal Counsel
- [ ] Safety Officer appointed and named
- [ ] `legalReviewer` Firebase custom claim defined and assigned to Safety Officer
- [ ] `isGuardianApprovedContact()` fail-open bug fixed (one line change)
- [ ] NCMEC attorney engaged (even if registration not yet complete)
- [ ] Firestore rules file reconciled to single canonical source
- [ ] Storage rules dry-run completed; missing paths added
- [ ] CSAM pipeline end-to-end tested with test hash

---

*All 35 decision briefs are in the DECISION_BRIEFS/ directory. Read the brief for each decision before signing.*

# CSAM / NCMEC Compliance Brief
For: Legal Counsel, Trust & Safety Lead, CTO
Prepared: 2026-06-16
Classification: CONFIDENTIAL — Legal Privileged

---

## Executive Summary

AMEN is a faith-community UGC social application that accepts user-generated posts, direct messages, media uploads, prayer room content, and Spaces. This combination of surface types makes AMEN an Electronic Service Provider (ESP) under 18 U.S.C. §2258A, obligating the company to report child sexual abuse material (CSAM) to the National Center for Missing and Exploited Children (NCMEC) CyberTipline upon actual knowledge. AMEN's engineering team has built and committed an end-to-end CSAM escalation scaffold — including a fail-closed upload gate, iOS escalation pipeline, and backend moderation queue — but the four legal and business preconditions required to activate the live reporting path have not yet been satisfied. The app cannot launch to the public, and no media-upload feature may go live, until all four gate conditions are cleared. This brief explains the legal basis, the current technical state, what must happen, and the minimum timeline to launch clearance.

---

## Legal Requirement

### 18 U.S.C. §2258A — What It Says

The PROTECT Our Children Act (codified at 18 U.S.C. §2258A) imposes reporting obligations on any "electronic service provider," defined broadly as any entity that provides electronic mail, messaging, or any other electronic communication service that enables the provision, creation, utilization, or storage of content. AMEN qualifies on all four counts.

**Triggering event.** The obligation attaches upon "actual knowledge" of an apparent violation — meaning any fact or circumstance from which a reasonable person would conclude that CSAM was present. This includes:
- User reports that identify CSAM
- Automated hash-match hits against a known CSAM database
- Cloud Vision or other ML scan results that indicate child exploitation material
- Moderation staff review that reveals apparent CSAM

**What the obligation requires.** Upon actual knowledge, the ESP must:
1. Submit an electronic report (CyberTip) to the NCMEC CyberTipline.
2. Preserve the reported content and any associated electronic data (IP address, account info, upload metadata) for 90 days, renewable upon law enforcement request.
3. Take no further distribution action that would expose the content to additional viewers.
4. Not notify the reported user in a way that might tip off an ongoing investigation (18 U.S.C. §2258E).

**Penalties for non-compliance.** An ESP that fails to report faces:
- Criminal liability: knowing failure to report is a federal crime.
- Civil liability: the statute was amended by CSAM Reporting Act provisions; NCMEC and DOJ both have referral channels to the FBI and DOJ CEOS (Child Exploitation and Obscenity Section).
- App Store delisting: Apple's App Store Review Guideline 1.1 independently prohibits CSAM and requires platforms to have detection and reporting mechanisms in place.

**Why AMEN qualifies as an ESP.** AMEN provides:
- Cloud-hosted storage for user-uploaded images, videos, and audio (Firebase/GCS)
- Direct messaging between users (1:1 and group DMs)
- Prayer Rooms and Spaces where media is shared
- Post compositions with image and video attachment

Any one of these is sufficient to trigger ESP status. Together they place AMEN squarely within the statutory definition.

### KOSA and State-Level Laws

The Kids Online Safety Act (KOSA), if enacted in final form, would impose additional duty-of-care obligations for platforms accessible to minors, including proactive safety measures for CSAM-adjacent content. Several states have enacted or are considering analogous laws:

- **Utah S.B. 152 (Social Media Regulation Act):** Requires platforms to verify user ages and applies heightened standards for minors.
- **California A.B. 2273 (AADC):** Requires platforms likely to be accessed by children under 18 to implement CSAM-adjacent child safety measures by default.
- **Florida H.B. 3 (2023):** Prohibition on minors accessing certain platforms; requires age verification.
- **Texas H.B. 18:** Similar minor-protection duties with civil enforcement mechanisms.

Compliance with §2258A is necessary but not sufficient. Legal counsel should assess which state laws apply given AMEN's user base and whether additional consent, verification, or reporting infrastructure is required before launch in any given state.

---

## Current Status

| Item | Status |
|---|---|
| NCMEC ESP registration | NOT REGISTERED |
| Hash match provider | NOT CONTRACTED |
| CyberTip submission capability | SCAFFOLD ONLY — `automatedCyberTipSubmitted: false`, `hashScanEnabled: false` (verified in code) |
| Media upload gate | FAIL-CLOSED — no upload proceeds without passing the moderation gate; safe state for pre-launch |
| Image moderation pipeline | REACTIVE — Cloud Vision scan + user reports queue to moderation; no proactive hash-match against NCMEC database |
| iOS CSAM escalation | SCAFFOLD — `prepareCSAMEscalation()` hides content + writes to `moderationQueue` + writes `safetyAuditLog`; does NOT auto-submit to NCMEC |
| Backend CSAM pipeline | SCAFFOLD — `submitReport.ts` writes `ncmecReadiness: "STUB_NOT_REGISTERED"`; `mediaModerationPipeline.ts` has `CSAM_HASH_LOOKUP_URL` env var wired but throws if empty |
| Evidence preservation | NOT CONFIGURED — `evidenceVault: null` in scaffold; requires legal sign-off to configure retention policy |
| 4-part legal gate | NOT CLEARED — all four conditions remain open |

**What "fail-closed" means in practice.** The current scaffold is safe for pre-launch: no CSAM-adjacent content can be submitted to NCMEC (no auto-submission exists), the upload gate blocks media that fails the moderation check, and any CSAM signal routes to a human-staffed moderation queue. The platform cannot satisfy the §2258A reporting obligation in this state — but it also cannot accidentally submit a malformed or unauthorized report.

---

## What Must Happen Before Launch (ordered)

### Step 1 — NCMEC ESP Registration (external, legal-led)

**Who:** Legal Counsel, Trust & Safety Lead
**What:** Complete the NCMEC Electronic Service Provider registration process. This creates the ESP account credentials required to submit CyberTips through the CyberTipline API.
**Why it must come first:** All subsequent steps depend on having a valid NCMEC ESP registration ID. The hash provider integration (Step 2) requires the registration to be complete so submissions can be attributed to a registered entity. Without registration, any "submission" to NCMEC is legally meaningless.
**What it unlocks:** Legally valid CyberTip submission credentials; access to NCMEC Connect (hash database access); test credentials for engineering integration testing.
**Time estimate:** 1–3 weeks. NCMEC processes registrations in batches and may require supplemental documentation about platform type and user base.
**Contact:** esp@ncmec.org | cybertipline.org/esp-registration | 1-800-843-5678 (NCMEC main line)

### Step 2 — Hash Provider Contract (legal + procurement)

**Who:** Legal, Procurement, Trust & Safety Lead
**What:** Contract with a hash-match provider to enable proactive detection of known CSAM against a database of hashes. Do not implement before Step 1.

**Options:**

| Provider | Notes |
|---|---|
| **NCMEC HashConnect** | Available post-registration. NCMEC's own hash database accessed via NCMEC Connect API. No additional vendor contract; included in ESP registration. Lower operational overhead. |
| **Microsoft PhotoDNA** | Enterprise licensing. Robust, widely used, matches perceptual hashes. Requires Microsoft commercial agreement. Good fit if AMEN scales to high upload volume. |
| **Thorn Project Protect** | Purpose-built for platforms; hash-matching API with policy guidance. NGO pricing available for nonprofits. Thorn also provides CSAM pipeline consulting. |
| **AWS Rekognition** | `DetectModerationLabels` has CSAM-adjacent detection but is not a hash-match database; it is probabilistic ML. Does not satisfy the known-hash-match standard expected by NCMEC. Not recommended as sole solution. |

**Recommendation:** Start with NCMEC HashConnect (included post-registration) for the minimum viable compliant path. If upload volume projections exceed 10,000 images/day, add PhotoDNA or Thorn as a secondary layer. NCMEC HashConnect is zero incremental cost and uses the authoritative NCMEC hash database, making it the most legally defensible choice for a v1 launch.

**Time estimate:** 2–4 weeks for procurement review and integration scoping (NCMEC HashConnect can be shorter if included in ESP registration).

### Step 3 — Technical Integration (engineering, after Steps 1 and 2)

**Who:** Engineering (backend), Trust & Safety Lead (pipeline review)
**What:**
1. Load hash provider credentials (API URL, token) into Firebase Secret Manager as `CSAM_HASH_LOOKUP_URL` and `CSAM_HASH_LOOKUP_TOKEN` — the env vars are already wired in `mediaModerationPipeline.ts`.
2. Replace the `NCMEC_STUB_NOT_REGISTERED` scaffold value in `submitReport.ts` with the live ESP registration ID.
3. Implement the live NCMEC CyberTipline API call in `mediaModerationPipeline.ts` (the function body at line 106 currently throws if `CSAM_HASH_LOOKUP_URL` is empty — engineers activate it by loading credentials).
4. Run end-to-end integration tests using NCMEC's test credentials (available post-registration) before touching production credentials.
5. Verify that evidence preservation (the `evidenceVault` field, currently `null`) is wired with the correct 90-day retention policy before activating.

**What does NOT need to be written from scratch:** The iOS `prepareCSAMEscalation()` pipeline is complete. The backend `moderationQueue` listener, `safetyAuditLog`, and `criticalSafetyAlerts` collections are operational. The four-gate comment block in `submitReport.ts` documents exactly which lines flip from false to true after sign-off.

**Engineering estimate:** 1–2 weeks, contingent on provider API documentation availability.

### Step 4 — Non-Engineer Review + Legal Sign-off

**Who:** Legal Counsel (written sign-off), Trust & Safety Lead (pipeline review), NOT the engineering team that built it
**What:**
- Legal counsel must produce written sign-off on the complete CSAM reporting procedure, covering: triggering criteria, submission workflow, evidence retention, user notification prohibition (§2258E), and staff escalation SLA.
- A non-engineer (Trust & Safety Lead or designated counsel) must review the complete pipeline end-to-end — not just the code comments, but the actual data flow from detection to CyberTip submission — and approve it in writing.
- This written approval is the final gate before `hashScanEnabled` and `automatedCyberTipSubmitted` can be changed to `true` in the Cloud Function environment.

**This step is non-negotiable.** The four-gate check in `submitReport.ts` (lines 234–241) is a hard comment-contract. Engineering is not authorized to flip these values without the written approvals documented here.

---

## The Four-Part Gate (all must be true before go-live)

The following four conditions are codified in `Backend/functions/src/submitReport.ts` (lines 234–241). No engineer may set `hashScanEnabled=true` or `automatedCyberTipSubmitted=true` until all four are satisfied with written documentation on file.

1. [ ] NCMEC ESP registration confirmed — registration ID on file with Legal and in Secret Manager
2. [ ] Hash provider contracted and credentials loaded to Firebase Secret Manager (`CSAM_HASH_LOOKUP_URL`, `CSAM_HASH_LOOKUP_TOKEN`)
3. [ ] Written legal sign-off from counsel on the CSAM reporting procedure (dated, signed, version-controlled)
4. [ ] Non-engineer (T&S Lead or Legal) has reviewed and approved the complete pipeline end-to-end

---

## What Happens If AMEN Launches Without This

This section is provided for planning purposes only — the intent is to be clear about the legal exposure so the right resources are allocated.

- **Active §2258A exposure.** Any image uploaded by any user that constitutes CSAM, once it creates "actual knowledge" on the platform (via user report, ML scan hit, or staff review), triggers a reporting obligation the platform currently cannot satisfy. The obligation exists regardless of whether the platform intended to satisfy it.
- **Criminal liability.** Knowing failure to report is a federal crime. Liability attaches to the company and potentially to officers who were aware of the obligation.
- **App Store rejection or removal.** Apple's App Store Review Guideline 1.1 states apps may not include content that sexualizes minors and requires that platforms have detection and reporting mechanisms. A reviewer who identifies that AMEN has no live CSAM reporting capability may reject the submission or remove the app post-approval.
- **Reputational catastrophe.** A single CSAM incident reported publicly — without an activated CyberTip pathway — is an existential reputational event for a faith-community platform.
- **Civil and regulatory exposure.** NCMEC coordinates with DOJ CEOS. A complaint or referral could trigger a civil investigative demand or grand jury subpoena.

The cost of the 4–6 week delay to clear the gate is far smaller than the cost of any one of these outcomes.

---

## Recommended Timeline

| Week | Milestone | Owner |
|---|---|---|
| Now (Week 0) | Legal team initiates NCMEC ESP registration; procurement begins hash provider evaluation | Legal, T&S Lead |
| +1 | Hash provider shortlisted; procurement process started; engineering briefed on API specs | Legal, Engineering |
| +2–3 | NCMEC ESP registration confirmed; registration ID delivered to Engineering for Secret Manager | NCMEC / Legal |
| +3–4 | Hash provider contract signed; credentials loaded to Secret Manager | Procurement, Engineering |
| +4–5 | Technical integration: credential wiring, live endpoint swap, integration tests with NCMEC test credentials | Engineering |
| +5–6 | Non-engineer review of complete pipeline; legal sign-off document produced and dated | T&S Lead, Legal |
| +6 | Four-part gate cleared; `hashScanEnabled` and `automatedCyberTipSubmitted` can flip to `true` in production | CTO sign-off |

**Minimum time to launch clearance: 4–6 weeks from today (2026-06-16), driven entirely by external parties (NCMEC registration, vendor procurement).**

No code changes shorten this timeline. The scaffold engineering is complete. The clock starts when Legal initiates NCMEC registration.

---

## Current Code State (for technical handoff)

This section summarizes what is built and what engineering must do after the four-part gate clears. It is intended for the CTO and lead engineer — not for external parties.

### What is built and operational (scaffold state)

| File | State | Notes |
|---|---|---|
| `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` | Complete scaffold | `prepareCSAMEscalation()` hides content, writes `moderationQueue` + `safetyAuditLog`; NCMEC submission requires human auth (documented in file header) |
| `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyModels.swift` | Supporting models | Age categories, minor protection config, escalation models |
| `Backend/functions/src/submitReport.ts` | Scaffold with gate | `ncmecReadiness: "STUB_NOT_REGISTERED"`, `automatedCyberTipSubmitted: false`, `hashScanEnabled: false` — gate comment at lines 234–241 |
| `Backend/functions/src/mediaModerationPipeline.ts` | Scaffold with env gate | `CSAM_HASH_LOOKUP_URL` and `CSAM_HASH_LOOKUP_TOKEN` env vars wired; throws `Error("CSAM hash lookup provider is not configured.")` if URL is empty (fail-closed) |
| `Backend/functions/src/mediaScanning.ts` | Operational | Cloud Vision scan on `onFinalize`; TIER 1 CSAM signals delete file + write `moderationQueue` (type=`csam_detection`) + write `violationLog` + suspend account |
| `Backend/functions/src/safetyOS.ts` | Operational | `csam` severity=`critical`; immediate block + escalation on CSAM label match |
| `Backend/functions/src/securityLaunchReadiness.test.ts` | Operational | Tests verify `automatedCyberTipSubmitted: false` and `CSAM hash lookup provider` throw remain in source; regression protection against accidental activation |

### What engineering does after the gate clears (in order)

1. Load `CSAM_HASH_LOOKUP_URL` and `CSAM_HASH_LOOKUP_TOKEN` to Firebase Secret Manager (backend).
2. Replace `ncmecReadiness: "STUB_NOT_REGISTERED"` in `submitReport.ts` with the live ESP registration ID.
3. Implement the live hash lookup call body in `mediaModerationPipeline.ts` (the function at line 106 is ready for the API call; the env var guard is already in place).
4. Wire `evidenceVault` retention (currently `null`) with the 90-day preservation policy per §2258A.
5. Run full integration test suite with NCMEC test credentials.
6. Set `hashScanEnabled: true` and `automatedCyberTipSubmitted: true` in Cloud Function environment config ONLY after written legal sign-off is on file.
7. Tag the release commit with `csam-gate-cleared` and attach the sign-off document reference.

---

## Contacts and Resources

| Resource | URL / Contact |
|---|---|
| NCMEC CyberTipline | cybertipline.org |
| NCMEC ESP portal (report submission) | report.cybertip.org |
| NCMEC ESP registration | cybertipline.org/esp-registration |
| NCMEC technical documentation for ESPs | missingkids.org/gethelpnow/csam/esp |
| NCMEC ESP contact | esp@ncmec.org |
| NCMEC general line | 1-800-843-5678 |
| Thorn Project Protect | thorn.org/solutions/detect |
| Microsoft PhotoDNA | microsoft.com/en-us/photodna |
| DOJ CEOS (reference) | justice.gov/criminal-ceos |
| 18 U.S.C. §2258A (statute text) | law.cornell.edu/uscode/text/18/2258A |

---

*This document was prepared by the AMEN engineering team for review by Legal Counsel and the Trust & Safety Lead. It describes platform architecture and legal obligations. It is not a legal opinion and should be reviewed by qualified counsel before being relied upon for compliance decisions.*

*Classification: CONFIDENTIAL — Legal Privileged*
*Version: 1.0.0 — 2026-06-16*

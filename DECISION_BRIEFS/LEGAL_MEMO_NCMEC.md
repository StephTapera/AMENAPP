# Legal Memo: NCMEC Registration and 18 U.S.C. § 2258A

**Prepared for:** Amen App — Safety Officer and Legal Counsel
**Prepared by:** Launch Readiness Swarm — Agent 3
**Date:** 2026-06-11
**Confidentiality:** This memo is for attorney-client discussion. Do not distribute outside the founding team and retained counsel.

---

## The Statute

18 U.S.C. § 2258A (PROTECT Our Children Act of 2008, as amended) requires any **Electronic Service Provider (ESP)** that obtains actual knowledge of an apparent violation involving child sexual abuse material (CSAM) to:

1. Submit a report to the National Center for Missing and Exploited Children (NCMEC) CyberTipline.
2. Preserve copies of the reported content for at least 90 days pending law enforcement request.
3. Refrain from disclosing the existence of the report to the subject of the report (except under specific conditions).

**Failure to report is a federal criminal offense** — not a civil penalty. The statute has no de minimis carve-out based on platform size or revenue.

---

## What "Actual Knowledge" Means

The "actual knowledge" standard was clarified in subsequent court interpretations and FTC guidance. It applies when:

- An automated detection system (hash-match, ML classifier, PhotoDNA) flags content as CSAM.
- A user report to the platform describes what appears to be CSAM.
- A human reviewer observes CSAM during moderation review.
- A law enforcement contact notifies the platform.

The platform does not need certainty — "apparent violation" is sufficient to trigger the reporting obligation.

---

## The Registration Requirement

NCMEC operates the CyberTipline and requires ESPs to register before submitting reports. Registration involves:

1. Contacting NCMEC's Technology Coalition or CyberTipline team to begin the ESP agreement process.
2. Executing a written agreement with NCMEC that governs submission format, data handling, and access to the CyberTipline intake API.
3. Receiving an ESP ID and API key from NCMEC after the agreement is executed.
4. Implementing the CyberTipline submission API using the NCMEC-provided technical specifications (available post-registration).

**There is no public registration portal.** The process is initiated by contacting NCMEC directly. The starting point is: https://www.missingkids.org/gethelpnow/cybertipline

---

## The Integration Point in Current Code

The Amen App codebase has a complete NCMEC reporting pipeline that is intentionally disabled:

**`functions/ncmecReporter.js`**
- Line 47: `NCMEC_SUBMISSION_ENABLED = process.env.NCMEC_SUBMISSION_ENABLED === "true"` — currently false
- Lines 60–115: `fileNCMECReport()` — writes queue-only records to Firestore; no live HTTP call
- Lines 208–217: `reportToNcmec()` — **throws intentionally** with message "This is a LAUNCH BLOCKER"
- Lines 321–398: `flagForNCMECReview` callable — human-triggered, writes to `mandatory_reports/`
- Lines 416–502: `onModerationRequiresMandatoryReport` trigger — fires on moderation result, queues record

**`functions/moderation/cyberTiplineInterface.js`**
- Line 99: `espId: "TODO_ESP_ID"` — literal placeholder; NCMEC-issued ID required
- Line 100: `espApiKey: "TODO_ESP_API_KEY"` — literal placeholder; from Secret Manager after registration
- Lines 65–139: `prepareCyberTiplineReport()` — builds structured report in NCMEC shape (ready for submission)
- Lines 156–185: `markReportSubmitted()` — records confirmed submission with NCMEC-issued `confirmationId`

**Current status:** Every CSAM detection creates a Firestore record and alerts admins via FCM. Human operators must manually submit to NCMEC via the NCMEC website until the API integration is complete. This is a legally acceptable interim measure only if the manual submission is reliably performed within the SLA.

---

## The Safe Harbor (18 U.S.C. § 2258B)

ESPs that act in good faith in reporting to NCMEC are protected from civil liability for:
- The act of reporting.
- Preserving, retaining, or providing content to law enforcement.
- Not disclosing the report to the subject.

The safe harbor requires registration and compliance with § 2258A. An unregistered ESP does not benefit from § 2258B protection.

---

## Questions for Your Attorney

1. **Does Amen qualify as an ESP under 18 U.S.C. § 2258A** given its current user-generated content feature set (posts, DMs, video uploads, comments)? The statutory definition of ESP covers "a provider of remote computing service or electronic communication service to the public." Amen almost certainly qualifies; counsel should confirm.

2. **What is the process to register with NCMEC as an ESP** for a mobile application with Firebase Storage as the underlying media storage? Is Firebase (Google) already a registered ESP, and does that registration extend to apps built on Firebase?

3. **What data elements must a CyberTipline report contain?** The current `prepareCyberTiplineReport()` function builds a report object — counsel should verify it contains all required elements under the NCMEC Technical Specifications.

4. **What is the SLA for filing a report?** The code uses `NCMEC_SLA_HOURS = 24` as a default. Counsel should confirm whether 24 hours meets NCMEC's expectations and whether a faster response is required for certain content types.

5. **What are the evidence preservation requirements?** 18 U.S.C. § 2258A requires preserving content for at least 90 days. The current code writes `legalHold: true` to CSAM records and never deletes them. Counsel should confirm this satisfies the statute.

6. **Does the interim manual submission process satisfy the statutory obligation?** Until the API integration is complete, admins must manually file with NCMEC via the website. Counsel should advise whether this is legally sufficient.

---

## Action Items (for Founder and Legal Counsel)

- [ ] Engage attorney with experience in 18 U.S.C. § 2258A compliance
- [ ] Confirm Amen's ESP status under the statute
- [ ] Contact NCMEC to initiate ESP registration: https://www.missingkids.org/gethelpnow/cybertipline
- [ ] Execute NCMEC ESP agreement
- [ ] Obtain NCMEC ESP ID → store in Firebase Secret Manager as `NCMEC_ESP_ID`
- [ ] Obtain NCMEC API Key → store in Firebase Secret Manager as `NCMEC_API_KEY`
- [ ] Engineering: replace `TODO_ESP_ID` and `TODO_ESP_API_KEY` with Secret Manager references
- [ ] Engineering: implement the live HTTPS POST in `reportToNcmec()` per NCMEC Technical Specifications
- [ ] Legal counsel approves automated submission procedure
- [ ] Engineering: set `NCMEC_SUBMISSION_ENABLED=true` in Cloud Functions environment
- [ ] Appoint Safety Officer to receive NCMEC escalation alerts (FCM) and hold `legalReviewer` custom claim

---

## Do Not Do These Things

- Do NOT set `NCMEC_SUBMISSION_ENABLED=true` before registration is complete.
- Do NOT implement the live HTTPS POST before counsel has reviewed the submission procedure.
- Do NOT share this memo or the existence of the NCMEC queue with any user or external party.
- Do NOT delete any document in `ncmecReports/`, `ncmecSubmissionQueue/`, or `mandatory_reports/` — these are legal hold records.

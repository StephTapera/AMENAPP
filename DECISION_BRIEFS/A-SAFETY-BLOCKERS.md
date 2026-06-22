# SAFETY BLOCKERS — ANSWER NOW (Group A)
**These 5 decisions block the safety deploy package. Answer before merging safety-hardening.**

**Branch:** safety-hardening
**Source:** DECISION_DOC_SAFETY.md Group A (items A-01 through A-05)
**Date filed:** 2026-06-11
**Status:** All 5 OPEN

---

## A-01: NCMEC CyberTipline Registration

**Question:** Has legal counsel been engaged to register with NCMEC as an Electronic Service Provider under 18 U.S.C. § 2258A? The `TODO_ESP_ID` and `TODO_ESP_API_KEY` placeholders in `ncmecReporter.js` and `cyberTiplineInterface.js` confirm registration has not been completed.

**Recommended default:** Engage an attorney TODAY. `reportToNcmec()` currently throws by design and `NCMEC_SUBMISSION_ENABLED` is hard-gated to false. Do not enable live NCMEC submission until credentials are in Firebase Secret Manager and counsel has approved the submission procedure.

**Risk if not answered:** Federal criminal liability under 18 U.S.C. § 2258A (PROTECT Our Children Act). This is not a civil risk — it is a criminal statute. Missed or delayed CSAM reports expose the company to criminal prosecution. The pipeline is queue-only until registration is complete; manual submissions carry SLA risk.

- [ ] Decision: Registration status — attorney engaged / ETA: ___________

---

## A-02: Minimum Age Floor

**Question:** What is Amen's minimum supported age — 13 (COPPA/US), 16 (GDPR-K/EU), or 18 (conservative)? `ageTier.js` returns `"blocked"` for age < 13, but there is no confirmed server-side account-creation block enforcing this.

**Recommended default:** 13 for a US-only launch. If EU launch is planned, choose 16 now — migrating 13-year-old accounts after launch creates legal and technical debt. In both cases, add a server-side creation block in the auth CF when `computeAgeTier() === "blocked"`.

**Risk if not answered:** COPPA violation if under-13 accounts are created without parental consent. Retroactive GDPR-K exposure if EU users are onboarded without meeting member-state consent age. Migration complexity increases with scale.

- [ ] Decision: Minimum age — 13 / 16 / 18 / other: ___________

---

## A-03: Guardian / Parental Consent for Ages 13–15

**Question:** Is verifiable parental consent required for accounts aged 13–15, and which guardian permission model will be used (read-only / active approve/deny / emergency-only)? **Critical code bug (OPEN-2):** `AmenChildSafetyService.swift:566` — `isGuardianApprovedContact()` returns `true` (allow) when no guardian document exists, meaning the guardian DM gate is currently a no-op in production.

**Recommended default:** Active approve/deny model required. Invert line 566 from `return true` to `return false` immediately after this decision is made. Guardian must receive a notification and approve each new contact before DMs are permitted for any 13–15 account.

**Risk if not answered:** With the fail-open bug live, every 13-year-old's DMs are ungated regardless of guardian settings. COPPA "verifiable parental consent" requirements for 13-year-olds are not met. FTC enforcement risk under the "actual knowledge" standard.

- [ ] Decision: Guardian model — active approve/deny (recommended) / read-only / emergency-only / not required
- [ ] Code fix: `isGuardianApprovedContact()` inverted to fail-closed — ETA: ___________

---

## A-04: Designated Safety Officer

**Question:** Who is the safety officer assigned to receive CSAM escalations, manage NCMEC submissions, and hold legal hold review authority? The `legalReviewer` Firebase custom claim is required by `firestore.rules:2833` to read legal holds, but no Cloud Function that mints this claim was found during audit.

**Recommended default:** Appoint a named person with 24/7 reachability before any beta launch. Add a `setLegalReviewerClaim` admin-only CF. Without this, queued NCMEC reports and legal hold documents are inaccessible through the app.

**Risk if not answered:** Legal hold documents queued by the NCMEC pipeline cannot be acted on by any operator. NCMEC SLA (24 hours from actual knowledge) cannot be met if no one has access to the queue. Chain-of-custody for CSAM evidence is broken.

- [ ] Decision: Safety officer appointed — Name / Role / Contact: ___________
- [ ] Code fix: `setLegalReviewerClaim` CF added and claim assigned — ETA: ___________

---

## A-05: Age Verification Method

**Question:** What method beyond self-attestation will be used to verify age, particularly for accounts self-reporting 13–15? The current `AgeVerificationOnboardingView.swift` collects birth year via self-attestation only. The `ageAssuranceStatus` field supports `"verified"` but no third-party integration exists.

**Recommended default:** Self-attestation + phone carrier age signal for ages 16+. Third-party age verification vendor (Yoti, AgeID, or Incode) for accounts self-reporting 13–15. Budget and a privacy impact assessment are required before vendor selection.

**Risk if not answered:** Self-attestation alone does not satisfy COPPA's "actual knowledge" standard. If the FTC determines the platform had or should have had actual knowledge of a user's minor status, the "they said they were 14" defense collapses. Retroactive enforcement risk scales with user base size.

- [ ] Decision: Verification method selected — self-attestation only / carrier signal / third-party vendor: ___________ / document-based
- [ ] Vendor contract signed (if applicable): [ ] Yes / [ ] No — ETA: ___________

---

## Sign-Off (required before merging safety-hardening)

All 5 decisions above must have written answers signed by at least two of the four roles below.

| Role | Name | Signature | Date |
|---|---|---|---|
| Founder / CEO | | | |
| Legal Counsel | | | |
| Safety Officer | | | |
| Engineering Lead | | | |

---

*Source briefs: A-01 through A-05 in DECISION_BRIEFS/. Full 35-item decision set in DECISION_DOC_SAFETY.md. Do not merge safety-hardening until this sheet is signed.*

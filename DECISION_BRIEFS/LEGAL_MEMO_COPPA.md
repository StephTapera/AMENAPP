# Legal Memo: COPPA Compliance and Verifiable Parental Consent

**Prepared for:** Amen App — Safety Officer and Legal Counsel
**Prepared by:** Launch Readiness Swarm — Agent 3
**Date:** 2026-06-11
**Confidentiality:** This memo is for attorney-client discussion. Do not distribute outside the founding team and retained counsel.

---

## The Statute

The Children's Online Privacy Protection Act (COPPA), 15 U.S.C. § 6501 et seq., and its implementing rule (16 C.F.R. Part 312, as amended in 2013) govern the collection, use, and disclosure of personal information from children under 13 in the United States.

The FTC enforces COPPA. Violations can result in civil penalties up to $51,744 per violation per day (as adjusted for inflation). "Per violation" can mean per child affected, not per incident.

---

## Does COPPA Apply to Amen?

COPPA applies to operators of websites and online services that are either:
- **Directed at children** (the primary audience is children under 13), or
- **Have actual knowledge** that they are collecting personal information from children under 13.

**Directed-at-children analysis:** Amen is a faith-community social platform. Its primary audience is adults and faith communities, which includes families with children. Amen does not appear to be primarily directed at children. However, if Amen explicitly permits users aged 13–17 to register and uses features (animations, youth-oriented design, youth ministry content) that attract younger users, the FTC may apply a mixed-audience analysis.

**Actual knowledge analysis:** If a user self-reports a birth year that makes them under 13, the platform has actual knowledge that the user is a child. The current code in `ageTier.js` returns `"blocked"` for age < 13 and the `AgeVerificationOnboardingView` collects birth year. If registration is not hard-blocked for `ageTier === "blocked"`, the platform may have actual knowledge of collecting information from a child under 13.

**Recommendation for legal counsel:** Perform a COPPA directed-at-children analysis for Amen's current feature set and user acquisition strategy.

---

## The "Verifiable Parental Consent" Requirement

For users under 13, COPPA requires obtaining "verifiable parental consent" (VPC) before collecting, using, or disclosing personal information. 16 C.F.R. § 312.5(b) lists acceptable VPC methods:

1. **Consent form** — A consent form that is signed by the parent and returned to the operator (including electronic signature).
2. **Credit card or online payment** — A credit card, debit card, or other online payment system transaction, accompanied by notice to the account holder.
3. **Toll-free phone number** — A toll-free number staffed by trained personnel.
4. **Video conference** — Video conference with trained personnel.
5. **Government ID** — Checking a form of government-issued photo ID against a database, provided the ID is deleted after verification.
6. **Knowledge-based authentication (KBA)** — KBA testing using information specific to the parent.
7. **Facial age estimation** — Technology that uses facial age estimation with parental email confirmation.

**Self-attestation by the child is not on this list.** A child entering their parent's email address is not VPC.

---

## For Ages 13–15: The "Actual Knowledge" and Neutral Age Analysis

COPPA does not require VPC for ages 13–15. However:

- If Amen is **directed at children** (mixed-audience analysis), COPPA may apply to 13–15 users as well.
- If Amen has **actual knowledge** that a specific user is under 13 (e.g., they state their age as 12 in a profile or DM), COPPA applies regardless of the minimum age policy.
- The FTC has taken enforcement actions against platforms that allowed users to self-report "13+" when the platform had constructive knowledge of younger users.

For Amen's purposes, the recommendation is to treat 13–15 accounts with heightened protection even where COPPA does not strictly require it, because:
- The faith-community context creates parental expectations of oversight.
- Guardian-visible DM threads and active approve/deny models are expected by parents who enroll their children in church apps.
- A VPC-like guardian consent step for 13–15 provides a strong defense against FTC inquiry.

---

## The Guardian Consent Model in Current Code

The current code has three relevant files:

**`AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift`**
- `isGuardianApprovedContact()` at line 549 — currently **fail-open**: returns `true` when no guardian document exists (OPEN-2 bug)
- `requestGuardianLink()` at line 222 — correctly writes to `guardianLinkRequests/`; the downstream CF is unconfirmed

**`functions/safety/minorProtection.js`**
- `USER_SAFETY_SCHEMA` at line 44 — defines `ageAssuranceStatus`, `guardianLinked`, `guardianIds`, `dmSafetyMode`
- Framework for guardian linking exists but active approve/deny is not wired end-to-end

**Firestore**
- `/guardianApprovedContacts/{minorId}/contacts/{contactId}` — the approval document structure exists
- `/guardianLinkRequests/{requestId}` — the link request is written; no confirmed CF processes it

---

## Questions for Your Attorney

1. **Is Amen "directed at children"** under the FTC's mixed-audience analysis? The answer determines whether COPPA's full requirements apply to 13–15 accounts.

2. **Does the current `ageTier === "blocked"` flow** (which classifies users under 13 but may not hard-block account creation) constitute "actual knowledge" under COPPA? If registration is permitted for self-reported age 12, the platform is collecting personal information from a child.

3. **Which VPC method is appropriate for Amen?** Given the faith-community context and budget constraints, the email-based guardian approval flow (with parent receiving a confirmation email to click) may satisfy a consent-form-style VPC. Counsel should advise on whether the current `requestGuardianLink()` email flow qualifies.

4. **Does the active approve/deny model for ages 13–15 satisfy FTC expectations** even though COPPA does not strictly require VPC for that age band? FTC guidance on mixed-audience platforms may provide a safe harbor.

5. **What are the privacy policy disclosure requirements?** COPPA requires a clearly-written privacy policy that specifically discloses what personal information is collected from children, how it is used, and who it is disclosed to. The current `AmenLegalDocumentModels.swift` has privacy text; counsel should review it for COPPA-required disclosures.

6. **GDPR-K (if EU launch is planned):** GDPR Article 8 requires member-state-specific age of digital consent (13–16). The UK Children's Code (Age Appropriate Design Code) imposes additional requirements including data minimization, default privacy settings, and prohibition on profiling minors. Counsel should advise on jurisdiction-specific requirements.

---

## Action Items (for Founder and Legal Counsel)

- [ ] Conduct directed-at-children analysis with FTC-experienced counsel
- [ ] Determine whether the `ageTier === "blocked"` flow constitutes actual knowledge
- [ ] Select a VPC method for under-13 accounts (if allowed at all)
- [ ] Determine guardian consent model for 13–15 (see A-03 decision brief)
- [ ] Engineering: fix `isGuardianApprovedContact()` fail-open bug (line 566)
- [ ] Engineering: implement `onDocumentCreated` CF for `/guardianLinkRequests`
- [ ] Legal counsel: review privacy policy text for COPPA-required disclosures
- [ ] Legal counsel: advise on GDPR-K if EU launch is planned
- [ ] Document the VPC method selected in DECISION_DOC_SAFETY.md A-03

---

## Key FTC Enforcement Cases for Context

- **Musical.ly (TikTok) — $5.7M fine (2019):** Collected personal information from children under 13 without parental consent; failed to delete such information when requested.
- **YouTube — $170M settlement (2019):** Collected personal information from child viewers; targeted advertising to children.
- **Instagram — FTC inquiry (ongoing):** Age verification adequacy for users 13–17.

These cases establish that the FTC pursues COPPA violations aggressively. The fine is per child, per day — a platform with thousands of minor users facing even a small number of violations can face massive civil penalties.

---

## Do Not Do These Things

- Do NOT allow account creation to complete for self-reported age < 13 without either hard-blocking or VPC.
- Do NOT collect additional personal information (phone, location, contacts) from 13–15 accounts before guardian consent is confirmed.
- Do NOT use behavioral advertising targeted at any user under 18.
- Do NOT permit birthday or birth year to be publicly visible on minor profiles.

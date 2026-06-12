# AMEN App — Decision Log

Decisions made under safety-hardening that require explicit human review before reversal.

---

## P0-8 — requireParentalConsentUnder16 protective default

**Date:** 2026-06-12
**Branch:** safety-hardening
**File:** AMENAPP/AMENAPP/AgeAssuranceModels.swift

**Decision:**
`requireParentalConsentUnder16` was `false`, making the COPPA/GDPR-K parental consent
code path dead code. Under-16 users (EU: all 13-15 year olds; US: under-13 already
blocked by minimumAge) had data collected without verifiable parental consent,
contradicting the Terms of Service and EU GDPR Article 8 / UK GDPR AADC requirements.

**Change:** Set `requireParentalConsentUnder16 = true`.

**Effect:** Teen-tier users (age 13-17) are blocked from directMessages, sensitiveContent,
liveStreaming, and commerce feature access until a guardian consent UI is complete and
consent is on file. Public profile access is still permitted for teens.

**Open item (OPEN-2):** Guardian consent UI is not yet built. Until it is, all teen-tier
users are restricted — this is intentionally conservative. When OPEN-2 is complete and
the UI is shipping, the gate can be relaxed to "teen with consent on file → access allowed"
rather than reverting to `false`.

**To relax this default:** Steph explicit decision required. Do not set
`requireParentalConsentUnder16 = false` without a written product decision and legal review.
The correct path is: build OPEN-2 guardian consent UI, then gate on `hasConsent == true`
rather than removing the gate entirely.

---

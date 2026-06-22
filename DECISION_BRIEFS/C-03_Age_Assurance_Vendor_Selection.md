# C-03: Long-Term Age Assurance Vendor Selection
**Group:** LATER (post-launch, within 90 days)
**Decision:** Which third-party age verification vendor will be used for 13–15 accounts at scale?

---

## Recommended Answer
Conduct a vendor shortlist evaluation of Yoti, AgeID, and Incode within 60 days of launch. Require a Privacy Impact Assessment before selecting any vendor. Target vendor contract signed within 90 days of launch.

## Rationale
Self-attestation alone is insufficient for COPPA compliance at scale. The decision in A-05 covers the launch-day approach; this decision covers the longer-term solution once the platform has real users and regulators may scrutinize the age verification method. Vendors differ significantly on privacy posture: some store biometric data, some use phone signals only. A Privacy Impact Assessment is required to understand what data the vendor collects and retains, and whether that creates additional COPPA or GDPR obligations.

## What the code already does (file:line)
- `AMENAPP/AgeAssuranceService.swift` — service exists with `ageAssuranceStatus` field support for `"verified"` status
- `functions/safety/minorProtection.js:46` — schema supports `"verified"` assurance status; no vendor integration wired
- Gap: No vendor SDK integration in current codebase

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Third-party vendor (recommended) | Integrate vendor SDK in `AgeAssuranceService`; update `ageAssuranceStatus` to `"verified"` | Budget; Privacy Impact Assessment required |
| Continue self-attestation | No change | FTC regulatory risk as platform grows |
| Government ID | Build ID capture and OCR flow | High privacy risk; strict data handling obligations |

## Legal consultation required?
YES — vendor Data Processing Agreement, privacy policy update, and potentially COPPA-specific vendor compliance certification required.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Founder + Legal counsel

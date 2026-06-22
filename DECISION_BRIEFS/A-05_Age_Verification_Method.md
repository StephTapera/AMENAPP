# A-05: Age Verification Method
**Group:** ANSWER-NOW (HARD BLOCKER)
**Decision:** What method beyond self-attestation will be used to verify age, particularly for accounts self-reporting ages 13–15?

---

## Recommended Answer
Self-attestation plus phone carrier age signal for ages 16+ as a first pass. For accounts self-reporting ages 13–15, require third-party age verification (vendor TBD) or verified parental consent document before full account activation. Budget and a privacy impact assessment are required before vendor selection.

## Rationale
Self-attestation alone does not satisfy COPPA's "actual knowledge" standard. If the FTC determines that Amen has — or should have had — actual knowledge that a user is under 13, the defense of "they said they were 14" collapses. The current code collects birth year via `AgeVerificationOnboardingView.swift` with no verification step. For ages 13–15, the `ageTier.js` tier is `tierB` (minor, restricted), but the underlying data is purely self-reported. Third-party age verification vendors (Yoti, AgeID, Incode) provide phone-based or ID-based verification that creates a defensible paper trail.

## What the code already does (file:line)
- `AMENAPP/AgeVerificationOnboardingView.swift` — collects birth year; self-attestation only
- `AMENAPP/AgeAssuranceService.swift` — orchestrates age assurance; no third-party vendor call found
- `functions/ageTier.js:24–31` — `computeAgeTier()` classifies tier from birth year; no verification layer
- `functions/safety/minorProtection.js:46` — `ageAssuranceStatus` field: values include `"self_attested"`, `"guardian_verified"`, `"verified"` — framework exists but `"verified"` path not implemented
- Gap: No CF callable or webhook that integrates with an external age verification vendor

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Self-attestation + phone carrier | Add carrier age-signal SDK; update `ageAssuranceStatus` to `"carrier_verified"` | Partial mitigation; not foolproof; requires carrier partnership |
| Third-party vendor (Yoti/AgeID/Incode) | Add vendor SDK; CF callable to verify token; update `ageAssuranceStatus` to `"verified"` | Budget + privacy review required; best legal protection |
| Document-based (government ID) | Add ID capture flow; OCR or manual review CF | High friction; significant privacy implications; requires PII storage policy |
| Self-attestation only | No code change | COPPA enforcement risk if FTC determines actual knowledge of minor status |

## Legal consultation required?
YES — statute: COPPA 16 C.F.R. § 312.5(b) "verifiable parental consent" methods. FTC guidance on acceptable verification methods for teen accounts is evolving.

---
**Status:** ☐ OPEN
**Owner:** Founder (budget) + Legal counsel (vendor selection) + Engineering Lead (integration)

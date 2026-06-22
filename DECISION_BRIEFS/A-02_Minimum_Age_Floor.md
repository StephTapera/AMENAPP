# A-02: Minimum Age Floor
**Group:** ANSWER-NOW (HARD BLOCKER)
**Decision:** What is Amen's minimum supported age — 13 (COPPA/US), 16 (GDPR-K/EU), or 18 (conservative)?

---

## Recommended Answer
Set the minimum age to 13 for a US-only launch. If an EU launch is planned at any point, immediately switch the floor to 16 or implement jurisdiction-aware detection. In both cases, the hard block must be code-enforced — the current self-report flow has no server-side creation block for age < 13.

## Rationale
COPPA (Children's Online Privacy Protection Act) sets 13 as the US floor. The code already implements the `blocked` tier for age < 13 in `ageTier.js`, but there is no confirmed server-side account-creation block that prevents a user from self-reporting age 12 and completing registration. The `computeAgeTier()` function returns `"blocked"` for those ages, which should gate capabilities, but account creation itself may proceed. GDPR-K (EU) requires parental consent for children under 16 in most member states — choosing 13 now and later needing EU compliance creates technical debt. Choosing 16 now is the cleaner long-term path if EU is on the roadmap.

## What the code already does (file:line)
- `functions/ageTier.js:27–28` — age < 13 returns `"blocked"` tier; no account is supposed to operate in this tier
- `functions/ageTier.js:28–29` — ages 13–15 return `"tierB"` (minor, restricted)
- `AMENAPP/MinorSafetyGate.swift` — iOS-side gate references `ageTier` to block certain flows
- `AMENAPP/AgeVerificationOnboardingView.swift` — collects birth year via self-attestation
- Gap: No confirmed CF callable or Firestore rule that hard-blocks account creation when `computeAgeTier(birthYear, currentYear) === "blocked"`

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| 13 — US only | Add server-side creation block in auth CF when ageTier === "blocked" | COPPA compliance for US; EU launch requires re-work |
| 16 — EU included | Change ageTier.js threshold; update GDPR-K consent flow; add jurisdiction detection | Larger scope; blocks some 13–15 US users who might have been allowed |
| 18 — adults only | Hard-block all tiers below tierD; remove entire minor-safety pipeline | Simplest legally; eliminates youth faith community use case |

## Legal consultation required?
YES — if EU launch is planned: GDPR-K parental consent standard by member state varies. Statute: GDPR Article 8 (each EU member state sets the age of consent for digital services, between 13–16).

---
**Status:** ☐ OPEN
**Owner:** Founder / Legal counsel

# AMEN Minor Safety Specification

**Status:** DRAFT — policy decisions required before any enforcement code is activated  
**Last updated:** 2026-05-29  
**Branch:** berean/ui-consolidation-v1  
**Owner:** Trust & Safety  

---

## 1. Current State

### What exists today

| Component | Location | Status |
|-----------|----------|--------|
| Guardian alert write path | `users/{uid}/guardianAlerts/{alertId}` | ACTIVE — writes on high-risk events |
| Guardian connection service | `Backend/functions/src/safety/GuardianConnectionService.ts` | ACTIVE — request / approve / revoke / approved-contacts |
| Youth safety check callable | `Backend/functions/src/safety/YouthSafetyService.ts` | ACTIVE — ageTier-gated DM / follow / media rules |
| Age gate UI | `AMENAPP/AgeGateView.swift` | ACTIVE — blocks < `AppConfig.Legal.minimumAge` (currently 13) at sign-up |
| Age assurance service | `AMENAPP/AgeAssuranceService.swift` | ACTIVE — layered DOB + triggered ID-check + AI risk scoring |
| Age assurance models | `AMENAPP/AgeAssuranceModels.swift` | ACTIVE — `AMENAgeAssuranceTier`: underMinimum / teen / adult |
| Minor safety service (iOS) | `AMENAPP/MinorSafetyService.swift` | ACTIVE — DM policy resolution, trust-tier computation, evidence preservation |
| `minorSafetyHook.js` scaffold | `functions/minorSafetyHook.js` | SCAFFOLDED — feature-flagged off; grooming pattern detection |
| Firestore rule: isMinor client-write denial | `firestore.rules` line 156-157 | ACTIVE — `isMinor` is server-derived only |

### Known gaps / open questions

- **`[VERIFY]`** Age gate exists in UI (`AgeGateView`) but requires confirmation that it fires on every cold-launch path (deep-link, push-notification launch, SSO) — not only the standard onboarding flow.
- **`[VERIFY]`** `ageTier` field on `users/{uid}` is set by Cloud Function from `ageBand`; confirm the CF is deployed and that no client write path can set `ageTier` directly (Firestore rules line 156–157 deny `isMinor` but `ageTier` client-write restriction needs separate audit).
- **`[VERIFY]`** DOB stored in `users/{uid}/private/age_assurance` — confirm Firestore rules restrict this subcollection to owner + admin only.
- **`[VERIFY]`** `AgeGateConfig.default` sets `minimumAgeByCountry: ["US": 13, "EU": 13, "UK": 13, "KR": 14]` — confirm country detection is working and GDPR-K / UK Age Appropriate Design Code thresholds are correctly applied per detected region.
- **`[VERIFY]`** `YouthSafetyService.enforceYouthAccountDefaults` trigger covers account creation and `ageTier` changes — confirm it is exported in `functions/index.js` (or the Backend equivalent) and deployed.
- Grooming pattern detection scaffold in `functions/minorSafetyHook.js` is **NOT active** — gated by `config/featureFlags.minorSafetyEnabled`.

---

## 2. Proposed Age Model

**`[DECISION REQUIRED]`** — The following is a proposed framework. None of these values are active policy until approved by legal, compliance, and product leadership.

### 2a. Minimum Age

| Tier | Proposed Age Range | Access |
|------|-------------------|--------|
| `underMinimum` | < 13 (US/EU/UK) | Blocked at sign-up; no account created |
| `teen` | 13–17 | Restricted defaults (see Section 3) |
| `adult` | 18+ | Standard access |

- **`[DECISION REQUIRED]`** Confirm minimum age = 13 globally, with country exceptions (e.g. KR = 14, Germany = 16 with parental consent for data processing).
- **`[DECISION REQUIRED]`** Whether to allow any under-13 use case (e.g. family/church mode supervised by guardian). Current code: hard block.

### 2b. Age Verification Approach

Current system uses **declared age** (DOB at sign-up) as tier 1, with:
- **Tier 2:** Triggered ID/selfie verification when AI risk score > 0.6 or suspicious activity detected (`AgeAssuranceService.requestVerification`)
- **Tier 3:** Background AI age-estimation risk score (`AgeAssuranceService.updateAIRiskScore`)

**`[DECISION REQUIRED]`** Whether to add:
1. Phone number verification as a lightweight age proxy (already partially built — `hasVerifiedPhone` in `MinorSafetyService`)
2. Government ID upload for teen→adult transitions (already partially built — `AgeVerificationMethod.governmentID`)
3. Parental consent flow for 13–15 year olds (already partially built — `AgeVerificationMethod.parentalConsent`, `requireParentalConsentUnder16` flag in `AgeGateConfig`)

**`[DECISION REQUIRED]`** Whether the `parentalConsent` + mutual-follow unlock for adult→minor DMs (currently coded in `MinorSafetyService.resolvePolicy`) is the intended policy or should be removed entirely.

---

## 3. Age-Appropriate Defaults for Minor (Teen Tier) Accounts

These defaults are already partially implemented in `YouthSafetyService.enforceYouthAccountDefaults`. This section documents the complete intended set. **`[DECISION REQUIRED]`** — confirm each default.

### 3a. Direct Messages

| Rule | Current Code | Proposed |
|------|-------------|---------|
| DMs off by default | `dmEnabled: false` on account creation | Confirm |
| Adults cannot DM teens without guardian approval | `checkYouthSafety("dm")` → blocks + alerts | Confirm |
| Teens can DM other teens (same age band ± 3 years) | `MinorSafetyService.resolvePolicy` — `.minorToMinorSameBand` | Confirm age-band tolerance (3 years?) |
| No media in teen-to-teen DMs | `.minorToMinorSameBand.canSendMedia = false` | **`[DECISION REQUIRED]`** relax for teens only? |
| No link sharing in teen-to-teen DMs | `.minorToMinorSameBand.canSendLinks = false` | **`[DECISION REQUIRED]`** |
| Guardian-approved adults may DM teen (mutual follow required) | `parentalConsent + hasMutualFollow` path in `MinorSafetyService` | **`[DECISION REQUIRED]`** keep or remove? |

### 3b. Discoverability

| Rule | Current Code | Proposed |
|------|-------------|---------|
| Not shown in People Discovery | `[NOT YET IMPLEMENTED]` | Required — add `showInPeopleDiscovery: false` default |
| Reduced ranking in Discover feed | `[NOT YET IMPLEMENTED]` | **`[DECISION REQUIRED]`** suppress entirely or just deprioritize? |
| Not returned in public user search | `[NOT YET IMPLEMENTED]` | **`[DECISION REQUIRED]`** |
| Profile not indexable / not public by default | Partially — `publicProfile` feature is blocked for `underMinimum` but not `teen` | **`[DECISION REQUIRED]`** teen profiles: public or private-by-default? |

**`[DECISION REQUIRED]`** — `minorSafetyHook.js` scaffold includes `showInSearch: false` and `discoverability: 'restricted'` as proposed defaults. These are NOT applied until the flag is on.

### 3c. Content Defaults

| Rule | Current Code | Proposed |
|------|-------------|---------|
| Mature content: always off | `matureContentAllowed: false` in `YouthSafetyService` | Confirm |
| Sensitive content filter: always on | `[NOT YET IMPLEMENTED as distinct from matureContent]` | **`[DECISION REQUIRED]`** |
| Discussion-only mode (no image/video posting) | `discussionOnlyMode: true` for `minor` ageTier | **`[DECISION REQUIRED]`** apply to `teen` as well? |
| Location exposure: always off | `locationExposureAllowed: false` | Confirm |
| Anonymous messaging: always off | `anonymousMessagingAllowed: false` | Confirm |

### 3d. Social Actions

| Rule | Current Code | Proposed |
|------|-------------|---------|
| Adults cannot follow `minor` ageTier without guardian approval | `checkYouthSafety("follow")` blocks adult→minor follows | Confirm |
| Adults following `teen` accounts: no current restriction | No rule for adult→teen follows | **`[DECISION REQUIRED]`** add restriction for teen tier too? |
| Teen can only join Youth Group-approved Spaces | `youthGroupMode: true` for `minor` | **`[DECISION REQUIRED]`** apply to teen tier? |
| No direct contact from adults without mutual follow or church affiliation | `adultToMinor` policy — hard block even with mutual follow (except `parentalConsent`) | **`[DECISION REQUIRED]`** church affiliation as an approved-contact channel? |

---

## 4. Grooming Pattern Detection

The `functions/minorSafetyHook.js` scaffold includes a `detectGroomingSignals()` function. This section documents the detection categories and the proposed review workflow. **All detection is flagged for human review — no autonomous action is taken.**

### 4a. Pattern Categories Implemented in Scaffold

| Category | Example Signals | Confidence |
|----------|----------------|-----------|
| Fast intimacy / age-leveraging | "you're so mature for your age", "you're so special" | 0.8 |
| Secrecy / isolation from caregivers | "keep this between us", "don't tell your parents" | 0.8 |
| In-person meeting solicitation | "meet me in person", "come see me" | 0.8 |
| Off-platform migration | "move to WhatsApp/Telegram/Snapchat/Instagram" | 0.8 |
| Personal info extraction | "give me your number / address / school / location" | 0.8 |

### 4b. Additional Patterns to Consider

**`[DECISION REQUIRED]`** — the following categories are NOT yet in the scaffold but should be reviewed for inclusion:

- Gift / reward offers to minors ("I'll buy you", "I can send you")
- Excessive personal flattery combined with age references
- Gradual boundary testing (sexual topic introduction — requires content moderation, not regex alone)
- Repeated contact attempts after a block or no-response
- Frequency anomalies (many messages in a short window from adult to minor account)

### 4c. Detection Architecture

- **Current scaffold:** regex pattern matching on DM content in a Firestore trigger (`conversations/{conversationId}/messages/{messageId}`)
- **Limitation:** regex alone has high false-positive rate; must be combined with age-pair context (sender adult, recipient minor)
- **`[DECISION REQUIRED]`** Whether to add ML-based grooming detection (e.g. Vertex AI call) in addition to regex
- **Important:** message content is NOT logged in safety review records — only metadata (senderId, recipientId, signal count, pattern labels) is written to `safetyReviews/`

### 4d. Detection Triggers

The full detection pipeline should run when ALL of the following are true:
1. Sender is `adult` ageTier (or unverified — treated as adult for safety purposes)
2. Recipient is `teen` or `minor` ageTier
3. Conversation is a private DM (not a group Space or public thread)
4. Feature flag `minorSafetyEnabled` is `true`

---

## 5. Hard Blocks on Highest-Risk Interactions

The following interactions are blocked outright (not queued for review) pending policy confirmation. These are currently enforced by `YouthSafetyService` and `MinorSafetyService`:

| Interaction | Block Location | Audit Trail |
|------------|---------------|-------------|
| Adult DM attempt to `minor` ageTier (no guardian approval) | `YouthSafetyService.checkYouthSafety("dm")` | `users/{minorUid}/safety/{alertId}` + `moderationQueue/` |
| Adult follow attempt to `minor` ageTier | `YouthSafetyService.checkYouthSafety("follow")` | Same as above |
| DM to minor when `dmEnabled: false` | `YouthSafetyService` | `users/{minorUid}/safety/{alertId}` |
| Minor joining non-youth-approved Space | `YouthSafetyService.checkYouthSafety("join_group")` | Not currently written to audit log — **`[GAP]`** add audit write |
| Media posting in `discussionOnlyMode` | `YouthSafetyService.checkYouthSafety("post_media")` | Not currently audited — **`[GAP]`** add audit write |
| Location exposure for any minor | `YouthSafetyService.checkYouthSafety("view_location")` | Not currently audited — **`[GAP]`** add audit write |

All block events should write to:
1. `users/{minorUid}/safety/{alertId}` — minor's own safety subcollection
2. `moderationQueue/{docId}` — Trust & Safety review queue
3. Guardian alert delivery via `GuardianConnectionService.forwardYouthAlertToGuardians` trigger

---

## 6. Guardian Notifications

Guardian alerts are currently written by `GuardianConnectionService.deliverSafetyAlertToGuardians()` when a `users/{minorUid}/safety/{alertId}` document is written with a high-risk `alertType`.

### 6a. Currently Triggering Guardian Alerts

| Alert Type | Trigger |
|-----------|---------|
| `adult_dm_attempt_to_minor` | Adult attempted DM to minor without guardian approval |
| `adult_follow_attempt_to_minor` | Adult attempted follow of `minor` ageTier account |
| `dm_attempted_to_minor_with_dm_off` | Any DM attempt when teen/minor has DMs disabled |
| `minor_safety_pattern` | Generic safety pattern detected |

### 6b. Additional Events That Should Trigger Guardian Alerts

**`[DECISION REQUIRED]`** — confirm and implement each:

| Proposed Alert Event | Priority |
|---------------------|---------|
| Grooming signal detected in DM to minor (from `minorSafetyHook.js`) | P0 |
| Off-platform migration attempt detected | P0 |
| Minor account profile changed from private to public | P1 |
| Minor account ageTier changed (especially teen → adult) | P1 |
| Guardian-approved contact revoked by minor without guardian confirmation | P1 |
| Minor reports content or another user | P2 |
| Minor account login from new device / unusual location | P2 |
| Minor account access to age-gated feature blocked | P3 |

### 6c. Guardian Alert Delivery SLA

**`[DECISION REQUIRED]`** — the following SLA targets are proposed but not yet implemented:

| Alert Priority | Proposed SLA |
|---------------|-------------|
| P0 (grooming signal, off-platform migration) | Push notification within 60 seconds |
| P1 (account change, age change) | Push notification within 5 minutes |
| P2 (device/location anomaly) | In-app notification within 15 minutes |
| P3 (informational) | In-app notification within 1 hour |

---

## 7. Decision Table

All items below require explicit sign-off before the corresponding code is activated.

| Decision | Options | Recommended | Status |
|----------|---------|-------------|--------|
| Minimum platform age | 13 / 16 / 18 | 13 (COPPA minimum for US) | **`[DECISION REQUIRED]`** |
| Age verification approach | Declared only / Declared + ID / Declared + Phone / Declared + AI | Declared + Phone + triggered ID | **`[DECISION REQUIRED]`** |
| Parental consent required for 13–15 | Yes (GDPR-K route) / No | Yes for EU/UK users | **`[DECISION REQUIRED]`** |
| Teen profile visibility default | Public / Private | Private (follow-request required) | **`[DECISION REQUIRED]`** |
| Teen discoverability in People Discovery | Shown / Hidden | Hidden | **`[DECISION REQUIRED]`** |
| Adult→teen follow restriction | Block (same as minor) / Allow (current) / Allow with notification | Notify guardian + require approval | **`[DECISION REQUIRED]`** |
| Guardian account model | Separate account / Permission on parent account | Separate account with connection (current architecture) | **`[DECISION REQUIRED]`** |
| Mandatory reporting to authorities | Yes (implement workflow) / No | **`[LEGAL REVIEW REQUIRED]`** | **`[DECISION REQUIRED]`** |
| Grooming detection ML augmentation | Regex only / Regex + Vertex AI | Regex + Vertex AI | **`[DECISION REQUIRED]`** |
| Grooming review SLA | 1 hour / 4 hours / 24 hours | 1 hour for P0 | **`[DECISION REQUIRED]`** |
| `minorSafetyEnabled` flag activation | Immediately / After policy sign-off | After policy sign-off | **`[DECISION REQUIRED]`** |
| Evidence preservation on grooming flag | Immediate freeze / Queue for review | Immediate preservation, queue for review | **`[DECISION REQUIRED]`** |

---

## 8. Legal Notes

**`[LEGAL REVIEW REQUIRED]`** — The following is informational only and is not legal advice.

### 8a. COPPA (US — Children's Online Privacy Protection Act)

- Applies to users under 13.
- Requires verifiable parental consent before collecting personal information from children under 13.
- **Current approach:** Hard block at sign-up for users under `AppConfig.Legal.minimumAge` (= 13). No account is created; no data is collected.
- **Gap:** COPPA also applies if the service has "actual knowledge" that a user is under 13 — even if they lied about their age at sign-up. The AI risk scoring in `AgeAssuranceService` addresses this partially but needs a documented response workflow (delete data, notify parent).
- **`[DECISION REQUIRED]`** Confirm a documented COPPA response workflow exists for the "actual knowledge" scenario.

### 8b. GDPR-K / Article 8 (EU — General Data Protection Regulation, minors)

- Under GDPR, processing of a child's personal data (under 16, or lower national threshold — minimum 13) requires parental consent unless the member state has lowered the age.
- Germany, France, and Netherlands use 16; Ireland and UK (pre-Brexit era) used 13.
- **`[DECISION REQUIRED]`** Country-level parental consent workflow for EU 13–15 users.
- The `AgeGateConfig.default` only enforces the minimum age, not the parental consent requirement for 13–15 in high-threshold EU states.

### 8c. UK Age Appropriate Design Code (Children's Code / KOPA)

- The UK ICO's Children's Code applies to any online service "likely to be accessed by children" (under 18).
- Requires: privacy by default, data minimization, no profiling by default for minors, geolocation off by default, no nudge techniques, parental controls.
- **Current gaps:**
  - `[VERIFY]` Profiling / personalization algorithms — confirm teens are excluded from behavioral profiling.
  - `[VERIFY]` Push notifications / nudge patterns — confirm no engagement-maximizing nudges for teen accounts.
  - `[VERIFY]` Geolocation — `locationExposureAllowed: false` in `YouthSafetyService` covers server-side; confirm no client-side location is collected for teen accounts.

### 8d. Mandatory Reporting (US — NCMEC CyberTipline)

- 18 U.S.C. § 2258A requires electronic service providers to report apparent child sexual exploitation material (CSAM) to NCMEC.
- **`[DECISION REQUIRED]`** Implement a documented mandatory reporting workflow including:
  1. Detection trigger (AI moderation + human review)
  2. Preservation of evidence (already partially built in `MinorSafetyService.preserveEvidenceForFrozenAccount`)
  3. Submission to NCMEC CyberTipline
  4. Account action (suspend, not delete — evidence must be preserved)
- Current `moderationQueue` pipeline does not include a NCMEC reporting step.

### 8e. KOSA (US — Kids Online Safety Act, pending)

- As of 2026-05-29, KOSA has not been enacted federally but is progressing. Some states have equivalent legislation.
- **`[DECISION REQUIRED]`** Monitor and plan for KOSA compliance (duty of care, default safety settings, access to parental controls).
- Most of the proposed architecture in this spec aligns with KOSA requirements.

---

## 9. Implementation Checklist (Pre-Activation)

Before setting `config/featureFlags.minorSafetyEnabled = true`:

- [ ] Policy decisions in Section 7 signed off by legal, compliance, and product
- [ ] Age gate verified on all cold-launch paths (deep link, push, SSO)
- [ ] `ageTier` client-write restriction confirmed in Firestore rules
- [ ] DOB private subcollection access restrictions confirmed in Firestore rules
- [ ] `YouthSafetyService.enforceYouthAccountDefaults` confirmed deployed
- [ ] `GuardianConnectionService.forwardYouthAlertToGuardians` confirmed deployed
- [ ] People Discovery exclusion for teen/minor accounts implemented
- [ ] Discover feed ranking suppression for teen/minor accounts implemented (`[NOT YET IMPLEMENTED]`)
- [ ] Guardian alert SLA (Section 6c) FCM push path implemented
- [ ] Grooming detection recipient minor-check completed in `minorSafetyHook.js`
- [ ] `safetyReviews` collection human review queue and tooling operational
- [ ] Evidence preservation workflow (freeze → NCMEC path) documented and tested
- [ ] COPPA "actual knowledge" response workflow documented
- [ ] EU parental consent workflow for 13–15 users implemented (if required)
- [ ] Privacy manifest updated to reflect DOB collection and age assurance processing
- [ ] App Store age rating confirmed (4+? 12+? 17+?)

---

*This document is a living spec. All `[DECISION REQUIRED]` items must be resolved and this document updated before any enforcement code is activated. Ping Trust & Safety + Legal for sign-off.*

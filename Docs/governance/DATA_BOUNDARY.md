# Data Boundary — Spiritual Surveillance & Crisis Data (Wave 4, Invariant 4)

Three red lines bind here: `crisis_data_export`, `spiritual_surveillance`, `spiritual_scoring`.

## Enforced now (hard gate)

`functions/context/amenExclusionValidator.ts` — the pure, unit-tested gate that
`exportAmenFile` runs as a **HARD REJECT** — is extended with two new denylist sets.
Any portable `.amen` payload containing these keys aborts the export with `HttpsError`:

| Set | Keys (normalized) | Red line |
|-----|-------------------|----------|
| `CRISIS_DATA_KEYS` | crisisSessionEvents, crisisFollowUps, crisisAlertLogs, safetyPlan, crisisSafetyPlan, selfHarmFlag, suicidalRisk, crisisRisk/Score/State/Triage, trustedContacts | `crisis_data_export` |
| `SPIRITUAL_SURVEILLANCE_KEYS` | prayerFrequency/Streak/Count, givingAmount/Total, titheAmount, attendanceStreak/Rate/Count, pietyScore, faithfulnessScore/Rank, doctrinalSoundness(Score), spiritualGrowthScore, sanctificationScore, holinessScore, devotionScore, spiritualScore/Rank | `spiritual_surveillance`, `spiritual_scoring` |

Keys are **precise field names** (scoring/surveillance), not topic words like "prayer",
so legitimate context facets that merely mention prayer are unaffected. The in-app export
path calls this same CF, so the boundary holds on both sides (there is no separate Swift
exclusion validator).

## Specified, tracked as follow-up (client-side)

These belong to invariant 4 but live in client storage and are logged in the gaps register
(Wave 7) rather than silently claimed as done:

1. **Crisis field-level encryption at rest.** Crisis state and safety plans are stored in
   `UserDefaults` (device-keychain protection only), not field-level encrypted. The
   invariant requires field-level encryption with **fail-closed** behavior if encryption
   cannot be verified. Recommended: route crisis persistence through the existing
   `ChurchNotesDiscipleshipEncryption` field-level path and refuse to persist/sync if the
   key is unavailable.
2. **Analytics SDK boundary.** Crisis writes already carry only aggregate flags (no
   sensitive text) per the existing crisis services. The standing assertion that **no
   spiritual-performance metric is ever computed or rendered** is enforced by the red-line
   test suite (Wave 6), which greps the SwiftUI surfaces for the surveillance field names.

## Why fail-closed

The export validator descends the whole object graph and treats a denylisted key as the
violation without descending into its subtree — so a smuggled crisis/surveillance field
aborts the entire export rather than being partially emitted.

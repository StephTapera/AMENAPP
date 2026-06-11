# B-10: MusicContentLayer Firestore Rules Coverage
**Group:** BEFORE-LAUNCH
**Decision:** Have all Firestore collections written by `RightsMonetizationService`, `FaithMusicGraphService`, and `AmenPulseDigestService` been enumerated and covered by explicit Firestore rules?

---

## Recommended Answer
Enumerate all collections written by the MusicContentLayer before launching. Add explicit Firestore rules for each. Any path not explicitly covered defaults to deny.

## Rationale
Undocumented Firestore collections written by new services are a common source of security gaps. If `RightsMonetizationService` writes royalty data, licensing records, or payment-adjacent documents to a collection not covered by rules, any authenticated user can read or overwrite those documents. The MusicContentLayer is marked as modified on the safety-hardening branch, meaning these collections are potentially new and have not yet been audited.

## What the code already does (file:line)
- `MusicContentLayer/` directory exists in project root — modified on safety-hardening branch
- `AMENAPP/AMENAPP/AMENAPP/Pulse/PulseService.swift` — `minorSafe` flag referenced; writes to Pulse collections
- Gap: MusicContentLayer Firestore collections not enumerated in rules during safety audit
- Gap: No rule block found for `faithMusicGraph/`, `rightsMonetization/`, or similar collection paths

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Enumerate + add rules (recommended) | Read all `db.collection()` calls in MusicContentLayer services; add rules for each | Correct; prevents data leakage |
| Deploy without auditing | No change | Any authenticated user may read/write music rights, royalty, or monetization data |
| Disable MusicContentLayer at launch | Feature flag OFF; no rule changes needed immediately | Acceptable if feature is not part of v1 launch scope |

## Legal consultation required?
NO — technical infrastructure decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead

# B-06: Data Retention Policy
**Group:** BEFORE-LAUNCH
**Decision:** How long are moderation reports, audit logs, NCMEC filings, and legal hold documents retained? Have Firestore TTL policies been enabled?

---

## Recommended Answer
Moderation reports: 3 years. Safety audit logs: 5 years. NCMEC CyberTipline filings: indefinitely (or per NCMEC agreement terms). Legal holds: indefinitely until released by legal counsel. Enable Firestore TTL policy in Firebase Console for `moderationQueue.expireAt` and `moderationDeadLetter` before launch.

## Rationale
Retention periods serve two purposes: preserving evidence for legal proceedings and not hoarding data beyond what is legally required. CSAM-related records must be preserved per NCMEC agreement terms (typically until the case is resolved). Safety audit logs are the basis for any future legal defense or regulatory inquiry and should be kept long enough to cover the statute of limitations for relevant offenses. Firestore TTL policies must be manually enabled in the Firebase Console — they do not activate from rules or code alone.

## What the code already does (file:line)
- `functions/ncmecReporter.js:75–93` — NCMEC report documents have `legalHold: true` field; never deleted by any code found
- `functions/ncmecReporter.js:86` — `preservedAt` timestamp written; no TTL or deletion logic found
- `firestore.rules` (implied) — `legalHolds` write is blocked for all clients
- Gap: No `expireAt` field found on `moderationQueue` documents in the write path examined
- Gap: Firestore TTL policy for `moderationQueue` and `moderationDeadLetter` not confirmed enabled in Console (manual step required)

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Recommended periods + TTL enabled | Add `expireAt` to `moderationQueue` writes; enable TTL in Console | Clean compliance posture |
| Shorter retention (1 year) | Change retention periods; update expireAt calculation | May violate NCMEC agreement; insufficient for litigation hold |
| Indefinite retention for all | Remove TTL; keep all records | Storage cost; potential GDPR right-to-erasure conflict for non-safety data |

## Legal consultation required?
YES — Statute: GDPR Article 17 (right to erasure) conflicts with indefinite retention for general moderation data. NCMEC agreement terms may specify minimum retention for CSAM-related records. Legal counsel should specify which categories are exempt from right-to-erasure.

---
**Status:** ☐ OPEN
**Owner:** Legal counsel + Engineering Lead

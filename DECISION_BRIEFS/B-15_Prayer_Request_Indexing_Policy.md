# B-15: Prayer Request Indexing and Search Policy
**Group:** BEFORE-LAUNCH
**Decision:** Are prayer requests (including anonymous ones) indexed in Algolia or any full-text search system?

---

## Recommended Answer
Prayer requests are never indexed in Algolia or any external search system. Server-side full-text search within the user's own church or sanctuary only, using Firestore directly. Anonymous prayer requests: no search index at all, anywhere.

## Rationale
Prayer requests contain some of the most sensitive personal information a person will share: health diagnoses, family crises, addiction, grief, suicidal ideation. Indexing these in Algolia — even with proper access controls — creates a third-party data exposure risk. Algolia is an external vendor whose access to this data would require disclosure in the privacy policy and potentially a Data Processing Agreement under GDPR. Anonymous prayer requests indexed anywhere defeat the purpose of anonymity: if the index contains the text, the author's privacy protection is illusory.

## What the code already does (file:line)
- `AMENAPP/AlgoliaSyncService.swift` — syncs user profiles and posts; prayer request indexing not found in audit
- `AMENAPP/AlgoliaSyncService.swift:351–355` — `shouldExcludeFromPeopleIndex()` excludes minors but no prayer-specific exclusion found
- Gap: No confirmed prayer request sync path to Algolia found; but no confirmed explicit exclusion either
- Gap: No `isPrayerRequest` field gate found in the Algolia sync path

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Never indexed (recommended) | Add `isPrayerRequest == true` exclusion check in all Algolia sync paths | Correct; minimal code change |
| Indexed within church only | Add church-scoped Algolia index filter; never index cross-church | Complex to enforce in Algolia security rules |
| Fully indexed | No change if not currently indexed; add sync if desired | GDPR DPA required; privacy policy update required; severe trust risk |

## Legal consultation required?
NO — GDPR Article 9 covers health data as a special category requiring explicit consent. Indexing prayer requests (which often contain health information) in any external system requires explicit consent and a DPA. The recommendation (no indexing) avoids this entirely.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead (confirm current Algolia sync scope) + Product

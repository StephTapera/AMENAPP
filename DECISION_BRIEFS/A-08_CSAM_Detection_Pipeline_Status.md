# A-08: CSAM Detection Pipeline Live Status
**Group:** ANSWER-NOW (HARD BLOCKER)
**Decision:** Is the CSAM hash-matching or ML scan pipeline actually deployed, tested end-to-end, and producing `detectionSource` values of `'ios_hash_match'` or `'cf_vision_scan'`?

---

## Recommended Answer
Before any public launch, run a documented end-to-end test using a known test hash (NCMEC provides test vectors to registered ESPs). Confirm the call chain from image upload through `prepareCSAMEscalation()`. Document the confirmed chain. If the pipeline is not confirmed live, treat this as a launch blocker.

## Rationale
The `prepareCSAMEscalation()` method exists in `AmenChildSafetyService.swift` and is well-implemented, but no callers were confirmed during the audit — it is unclear what trigger actually calls it. The legal documents shown to users (`AmenLegalDocumentModels.swift:548`) explicitly state that "all user-uploaded media is scanned using industry-standard hash-matching (PhotoDNA or equivalent) and AI-based classifiers before publication." If this representation to users is not backed by a live pipeline, the platform faces both legal liability and the actual risk of CSAM passing through without detection or reporting.

## What the code already does (file:line)
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:278–361` — `prepareCSAMEscalation(contentRef:authorId:detectionSource:)` fully implemented; writes to `moderationQueue` and `safetyAuditLog`
- `AmenChildSafetyService.swift:277` — documents accepted `detectionSource` values: `"ios_hash_match"` | `"cf_vision_scan"` | `"user_report"`
- `AMENAPP/AMENAPP/ConnectSpaces/Legal/AmenLegalDocumentModels.swift:548` — user-facing legal text claims PhotoDNA-equivalent scanning is active
- `functions/imageModeration.js` — contains NCMEC-related logic
- Gap: No confirmed caller of `prepareCSAMEscalation()` found in iOS codebase during audit
- Gap: No confirmed deployment record showing hash-matching or Vision API scan is live

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Confirm pipeline live + test with test hash | Document the call chain; no code change if working | Correct path; resolves gap |
| Wire confirmed caller to `prepareCSAMEscalation()` | Add caller in upload pipeline (e.g., post creation, DM media upload) | Required if pipeline is not already wired |
| Launch without confirmed pipeline | No change | CSAM may pass undetected; user-facing legal text is false; federal liability |

## Legal consultation required?
NO — this is a technical confirmation task. However, the result directly impacts A-01 (NCMEC registration) — a pipeline that fires but cannot submit to NCMEC is incomplete.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead + Safety Officer

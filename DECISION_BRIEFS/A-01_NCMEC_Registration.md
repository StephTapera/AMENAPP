# A-01: NCMEC CyberTipline Registration
**Group:** ANSWER-NOW (HARD BLOCKER)
**Decision:** Has legal counsel been engaged to register with NCMEC as an ESP under 18 U.S.C. § 2258A, and have real credentials replaced the `TODO_ESP_ID` / `TODO_ESP_API_KEY` placeholders?

---

## Recommended Answer
Engage an attorney TODAY and begin the NCMEC ESP registration process. Do not enable `NCMEC_SUBMISSION_ENABLED=true` or deploy the NCMEC pipeline to production until registration is complete and both secrets are stored in Firebase Secret Manager.

## Rationale
18 U.S.C. § 2258A (PROTECT Our Children Act) is not a civil compliance question — it is a criminal statute. Any ESP with actual knowledge of CSAM that fails to report faces federal criminal liability. The code already has a full NCMEC reporting pipeline (`ncmecReporter.js`, `cyberTiplineInterface.js`) but it is deliberately gated off behind `NCMEC_SUBMISSION_ENABLED=false` and contains literal placeholder strings for the ESP ID and API key. The `reportToNcmec()` function throws by design so that no caller can accidentally believe a live report was filed. Until an attorney has navigated the NCMEC ESP agreement process and obtained real credentials, the entire pipeline must remain queue-only (admins receive FCM alerts and must submit manually).

## What the code already does (file:line)
- `functions/ncmecReporter.js:47` — `NCMEC_SUBMISSION_ENABLED = process.env.NCMEC_SUBMISSION_ENABLED === "true"` (gate is false; env var not set)
- `functions/ncmecReporter.js:208–217` — `reportToNcmec()` throws explicitly: "This is a LAUNCH BLOCKER"
- `functions/moderation/cyberTiplineInterface.js:99–101` — `espId: "TODO_ESP_ID"`, `espApiKey: "TODO_ESP_API_KEY"` hardcoded placeholders
- `functions/ncmecReporter.js:60–115` — `fileNCMECReport()` writes to `ncmecReports/` and `ncmecSubmissionQueue/` (queue-only; no live HTTP call)
- `functions/ncmecReporter.js:124–192` — `onCSAMDetected` trigger alerts admin FCM tokens when queue entry created
- `functions/ncmecReporter.js:416–502` — `onModerationRequiresMandatoryReport` trigger fires on `moderationResults/` set

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Register with NCMEC, obtain ESP ID + key | Store in Secret Manager; replace placeholders; set `NCMEC_SUBMISSION_ENABLED=true` | None if done correctly |
| Skip registration, use queue-only indefinitely | No code change; operators submit manually | Criminal liability if submissions are delayed beyond SLA or missed entirely |
| Restrict to adults-only app (no minor accounts) | Age floor hard-block at 18; remove entire minor-safety tier | Major product pivot; still requires NCMEC if CSAM is ever uploaded by adults |

## Legal consultation required?
YES — statute: 18 U.S.C. § 2258A / 18 U.S.C. § 2258B (safe harbor)
Obligations: ESP agreement with NCMEC; mandatory report contents; safe harbor conditions; SLA for filing (NCMEC expects within 24 hours of actual knowledge).

---
**Status:** ☐ OPEN
**Owner:** Legal counsel + Safety Officer

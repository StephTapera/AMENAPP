# B-05: Moderation Appeal Response SLA
**Group:** BEFORE-LAUNCH
**Decision:** What is the committed response time for users who appeal a moderation decision (content removed or account actioned)?

---

## Recommended Answer
5 business days for standard content-removal appeals. 24 hours for account suspension appeals. Appeals handled by the designated safety officer until a dedicated trust-and-safety team is staffed.

## Rationale
Apple's App Store Review Guidelines and platform best practices for social apps require that users have a meaningful appeals process. If the platform cannot commit to a response time, the appeals queue may grow unboundedly, creating legal and reputational exposure. Account suspension especially requires fast turnaround because a wrongly suspended account loses access to their community. The 24-hour SLA for suspensions is industry standard (Facebook, Instagram follow similar policies).

## What the code already does (file:line)
- `functions/moderation/escalation.js` — escalation pipeline writes to `moderationQueue`; no SLA tracking field found
- Gap: No `appealDeadlineAt` or `slaDeadline` field found on appeal queue documents
- Gap: No CF or cron job found that escalates overdue appeals to a pager or secondary reviewer

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| 5-day standard / 24-hour suspension (recommended) | Add `appealDeadlineAt` to moderation queue; add SLA monitor CF | Manageable; aligned with industry standard |
| Best-efforts / no commitment | No code change | Legally risky; App Store rejection risk if no process documented |
| 48-hour all appeals | Adjust SLA fields | Acceptable; harder operationally at launch |

## Legal consultation required?
NO — operational SLA decision. Include in Terms of Service / Community Guidelines.

---
**Status:** ☐ OPEN
**Owner:** Safety Officer + Product

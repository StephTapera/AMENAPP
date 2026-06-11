# C-01: Moderation Team Staffing Model
**Group:** LATER (post-launch, within 90 days)
**Decision:** Who performs human moderation review for the appeal queue, escalated AI-flagged content, and legal hold requests?

---

## Recommended Answer
Hybrid model at launch: safety officer handles CSAM and legal holds; a contracted outsourced vendor handles standard content appeals and escalations. Transition to in-house trust-and-safety team as MAU grows past 10,000.

## Rationale
At launch scale, a full in-house trust-and-safety team is cost-prohibitive. However, CSAM and legal hold reviews should always be handled by an internal named individual (the safety officer) to maintain chain of custody and legal accountability. Outsourced vendors (e.g., Teleperformance, Accenture Content Moderation) can handle the volume of standard appeals without the legal exposure of outsourcing CSAM handling.

## What the code already does (file:line)
- `functions/moderation/escalation.js` — escalation pipeline writes to `moderationQueue` and `moderatorAlerts`; human reviewers access via admin tooling (admin tool not in scope of this audit)
- Gap: No admin moderation dashboard found in the codebase; human review tooling TBD

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Internal team | No code change; headcount decision | Expensive at launch; correct at scale |
| Outsourced vendor | No code change; vendor contract + data processing agreement | DPA required for GDPR; CSAM handling must stay internal |
| No staffing plan | No change | Moderation queue grows unbounded; App Store violation |

## Legal consultation required?
YES — if outsourcing content moderation, a Data Processing Agreement (DPA) is required under GDPR and CCPA for vendors accessing user content.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Founder

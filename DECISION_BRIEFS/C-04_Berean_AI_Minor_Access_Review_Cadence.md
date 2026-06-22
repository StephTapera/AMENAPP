# C-04: Berean AI Access Policy for Minors — Review Cadence
**Group:** LATER (post-launch, within 90 days)
**Decision:** As Berean AI capabilities expand post-launch, what is the ongoing review cadence for minor access policies?

---

## Recommended Answer
Quarterly review cadence, owned by the Safety Officer. Each new Berean AI capability must be tagged with a minimum age tier before deployment. Any capability touching mental health, relationships, or grief must be evaluated against the minor access policy before enabling.

## Rationale
B-14 covers the launch-day access policy. This decision covers the ongoing governance process. AI capabilities evolve rapidly, and a policy set at launch will be outdated within months. A quarterly review ensures the policy keeps pace with new features. Tagging each capability with a minimum age tier at design time (rather than retrofitting after complaints) is the correct process.

## What the code already does (file:line)
- No current review cadence or capability tagging system found in the codebase
- Gap: Berean AI callables are not tagged with minimum age tier in code; age gate is not enforced at callable entry point

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Quarterly review + capability tagging (recommended) | Add `minAgeTier` metadata to Berean AI callable definitions; add to code review checklist | Correct governance posture |
| Annual review | No code change; calendar reminder | Policy may lag new capabilities |
| No formal review | No change | Feature creep into unsafe territory for minors |

## Legal consultation required?
NO — operational governance decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Safety Officer

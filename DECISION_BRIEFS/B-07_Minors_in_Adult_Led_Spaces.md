# B-07: Minors in Adult-Led Sanctuaries / Spaces
**Group:** BEFORE-LAUNCH
**Decision:** Under what conditions may a minor be added to or join a sanctuary, space, or community room led by an adult who is not their guardian?

---

## Recommended Answer
Guardian approval required for any minor joining an adult-led space outside their registered church. By default, minors can only join spaces under their registered church's verified account. Any space containing minor members must have `churchVerified == true` on the space document.

## Rationale
Spaces and sanctuaries create private group environments where adult-to-minor contact can occur away from the minor's public timeline. This is the same grooming risk vector as DMs but at group scale. A minor whose church uses Amen should be joinable to that church's official spaces without extra friction (trusted environment). Any space outside that context (a third-party adult's prayer group, a ministry from another church) requires guardian sign-off because the minor is entering an unvetted environment.

## What the code already does (file:line)
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyModels.swift` — minor protection models exist
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenMinorExperienceView.swift` — minor experience view references guardian
- Gap: No confirmed `churchVerified` check on space-join path for minor accounts
- Gap: No confirmed guardian-approval gate on Spaces/Sanctuaries join CF

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Guardian approval for outside-church spaces (recommended) | Add `ageTier` check in space-join CF; require `guardianApproval` field for non-church spaces | Correct protection; some UX friction for legitimate youth ministries |
| Registered church spaces only | Block all space joins for minors except church-owned spaces | Simpler; may be too restrictive for legitimate cross-church youth events |
| Open — any adult can add minors | No change | Grooming vector in group contexts |

## Legal consultation required?
NO — safety policy decision with product implications.

---
**Status:** ☐ OPEN
**Owner:** Safety Officer + Product

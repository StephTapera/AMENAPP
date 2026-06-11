# C-05: Prayer Request Archive Policy — Post-Launch Detail
**Group:** LATER (post-launch, within 90 days)
**Decision:** Post-launch: are prayer request archives made available for research, pastoral analytics, or partner access?

---

## Recommended Answer
Prayer archives available for pastoral analytics only in aggregate, anonymized form (no individual prayer request readable by analytics tools). Third-party research access: never without explicit user consent and separate opt-in. Policy review cadence: annual.

## Rationale
B-15 establishes that prayer requests are not indexed in Algolia. This decision covers what happens to stored prayer request data over time. Pastoral analytics (e.g., "what percentage of prayers in this church are about health concerns this month?") can provide meaningful insights to church leadership without compromising individual privacy — but only if the analytics layer never surfaces individual prayer text with attribution. Third-party research access to prayer requests is a bright line that should require opt-in because prayer content is as sensitive as health data.

## What the code already does (file:line)
- No prayer request analytics service found in the codebase currently
- `AMENAPP/AMENAPP/CommunityOS/` — general community data pipeline; prayer-specific analytics not confirmed

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Aggregate anonymized analytics only (recommended) | Build analytics aggregation CF that never surfaces individual text | Privacy-preserving; useful to pastors |
| No analytics | No change | Lost insight; acceptable |
| Individual prayer text in analytics | Build analytics tool; add explicit consent flow | GDPR Article 9 (health data); requires explicit opt-in |

## Legal consultation required?
YES — if any pastoral analytics involve health, mental health, or relationship content (common in prayer requests), GDPR Article 9 and HIPAA-adjacent state laws may apply.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Product + Legal counsel

# Find a Church v2 — Safety Gate Sign-Off Checklist (ABSOLUTE STOPS)

> Source: `FIND_CHURCH_V2_SPEC.md` §5. These are **blockers, not TODOs**. Each
> gated capability **cannot launch** until its gate is signed off. Treated under
> the existing CSAM/COPPA absolute-stop doctrine. `child_safety_concern` reports
> use the existing absolute-stop escalation path, **not** the normal queue.

Legend: ☐ = open blocker · the capability behind an open gate must not ship.

---

## GATE A — Location privacy (all users) · §5.1
- ☐ A1. Any query that may be logged or sent to a church snaps user location to a
  coarse geohash (≤ precision 6, ~1.2 km cell) **before** transmission.
- ☐ A2. Exact device location is used only locally for distance display; it is
  **never** written to Firestore and **never** transmitted to a church.
- ☐ A3. No "user is nearby" signal is ever exposed to any church or user.
- ☐ A4. `churchSearchHistory` is owner-only; user can delete individual entries
  and clear all; private-search toggle suppresses writes entirely
  (`ChurchPreferences.privateSearch`).
- ☐ A5. Saved home/work locations are blurred to neighborhood radius in any
  shared context.

## GATE B — Minor protection branch (HARD) · §5.2
`isMinor` resolved server-side from auth. When true, ALL of:
- ☐ B1. `church_visit_presence_enabled` is **force-OFF** regardless of flag/user
  setting.
- ☐ B2. `planVisit` may create only a **private** plan (`sharedWithChurch: false`
  ALWAYS); never mirrored to the church; admin never receives minor identity,
  contact, or intent-to-visit.
- ☐ B3. A minor is **never** shown as publicly attending/visiting any church,
  under any opt-in. The opt-in does not exist for minors.
- ☐ B4. Messaging a church from a minor routes through GUARDIAN/Aegis moderation
  and existing minor-DM safeguards; no direct unmoderated org channel.
- ☐ B5. No location-presence broadcast of any kind for minors.

## GATE C — Visit plans (adults) · §5.3
- ☐ C1. `users/{uid}/visitPlans/{id}` is private by default.
- ☐ C2. Mirroring to `churches/{churchId}/visitorIntents/{id}` requires **ALL**:
  church `verification.status === 'verified'` **AND** explicit user opt-in
  **AND** non-minor. Missing any → private only. Enforced **in-function** AND
  re-asserted in rules.

## GATE D — Church-uploaded media → MEDIA-GATE (fail-closed) · §5.4
- ☐ D1. Hero images/videos, guide covers, sermon thumbnails enter
  `heroMediaState/thumbnailMediaState: 'pending_gate'` and are **not served**
  until `approved`.
- ☐ D2. Fail-closed: gate error → media stays hidden.
- ☐ D3. Wired to the **existing** MEDIA-GATE pipeline; no parallel pipeline built.

## GATE E — Trust surface (verification as safety) · §5.5
- ☐ E1. Unverified churches show a persistent "Not officially verified" label and
  **cannot** use presence/visitor-intent features that touch users until verified.
- ☐ E2. `reportChurch` writes to `churchReports` (create by any authed user; read
  by moderators only) → existing abuse-moderation queue.
- ☐ E3. `child_safety_concern` reports follow the **absolute-stop escalation
  path**, not the normal queue.

---

## Launch-blocking summary (maps gates → flags)
| Capability | Flag | Gates that must be signed off to launch it |
|---|---|---|
| Visitor presence / visitor-intent mirror | `church_visit_presence_enabled` | A, B, C, E (HARD-OFF for minors regardless) |
| Plan a visit (private path) | `church_plan_visit_enabled` | A, B2, C1 |
| Church-uploaded media display | (within v2 surface) | D |
| Discovery feed (logs/sends location) | `church_discovery_engine_enabled` | A |
| Whole v2 surface | `find_church_v2_enabled` | all of the above for the features it exposes |

**No capability behind an open gate may be flipped on in production.**

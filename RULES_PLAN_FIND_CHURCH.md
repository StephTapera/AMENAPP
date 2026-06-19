# Find a Church v2 — Firestore Rules Plan (Wave 0 direction)

> Source: `FIND_CHURCH_V2_SPEC.md` §6. This is the **direction** only. Exact rules
> are written in **Wave 2** and must pass **two-sided emulator verification**
> (allow-cases pass AND deny-cases fail) before any PASS. Project `amen-5e359`,
> functions region `us-east1`.

## Guiding invariant
The client may **read** public church data and **write only its own descriptive
intent**. Everything that implies trust, safety, presence, or moderation state is
**server-only**. Minor PII never reaches any church-readable path.

## Collection-by-collection direction

| Path | read | create | update | delete | server-only fields (deny client write) |
|---|---|---|---|---|---|
| `churches/{id}` | public read of public fields | server / claim flow only | church admins (in `churches/{id}/admins/{uid}`) may write **descriptive** fields only | denied (soft-delete server-side) | `verification.status`, `verification.verifiedAt`, `reportState`, `profileCompleteness`, `heroMediaState`, `followerCount` |
| `churches/{id}/serviceTimes/{id}` | public | church admin | church admin | church admin | — |
| `churches/{id}/ministries/{id}` | public | church admin | church admin | church admin | — |
| `churches/{id}/smallGroups/{id}` | public | church admin | church admin | church admin | — |
| `churches/{id}/events/{id}` | public | church admin | church admin | church admin | — |
| `churches/{id}/sermons/{id}` | public | church admin | church admin | church admin | `thumbnailMediaState` (gate) |
| `churches/{id}/admins/{uid}` | self + existing admins | claim/verify flow (server) | server | server | entire doc server-managed |
| `churches/{id}/visitorIntents/{id}` | church admins (verified only) | **CF `planVisit` ONLY** — client create denied | denied | server | entire doc; never contains minor PII |
| `users/{uid}/savedChurches/{churchId}` | owner only | owner | owner | owner | — |
| `users/{uid}/churchSearchHistory/{id}` | owner only | owner | owner | owner (individual + clear-all) | — |
| `users/{uid}/churchPreferences` (singleton) | owner only | owner | owner | owner | — |
| `users/{uid}/visitPlans/{id}` | owner only | owner / CF | owner / CF | owner | `sharedWithChurch` (CF-controlled) |
| `churchReports/{id}` | **moderators only** | any authed user | moderators only | moderators only | `reporterUid` (server-stamped), `state` |
| `churchVerificationRequests/{id}` | requester self + moderators | claiming admin | moderators / server | moderators | `status` (server) |

## Hard rules to encode (and emulator-prove both sides)
1. **Server-only fields uneditable by client** — deny-case: an authed user (even a
   church admin) writing `verification.status` / `verifiedAt` / `reportState` /
   `profileCompleteness` / `heroMediaState` / `followerCount` must FAIL.
2. **`visitorIntents` unwritable by client** — deny-case: any direct client
   create/update/delete on `churches/{id}/visitorIntents/**` must FAIL. Only the
   `planVisit` CF (admin SDK) writes here, and only when church `verification.status
   == 'verified'` AND user opt-in AND non-minor (re-asserted in-function per §5.3).
3. **Minor PII never reaches church-readable paths** — deny-case: nothing a church
   admin can read may contain a minor's identity/contact/intent. visitorIntents
   carries no PII by schema; verify no path leaks it.
4. **Reports readable only by moderators** — allow-case: any authed user can
   `create` a `churchReports/{id}`. deny-case: a non-moderator `read`/`update` must
   FAIL.
5. **Owner-only user docs** — deny-case: user B reading/writing user A's
   `savedChurches` / `churchSearchHistory` / `churchPreferences` / `visitPlans`
   must FAIL.
6. **`heroMediaState` / `thumbnailMediaState` are server-only** — the MEDIA-GATE
   pipeline sets them; client writes FAIL (fail-closed: unset/`pending_gate` media
   is never served).

## Helpers expected to exist / reuse
- `isChurchAdmin(churchId)` → membership in `churches/{churchId}/admins/{uid}`
  (mirror the existing `isChurchMember(churchId)` pattern at `firestore.rules:1153`).
- `isModerator()` → existing moderator/admin-claim helper used by the abuse queue.
- `isMinor()` — resolved server-side from auth/age-tier; rules re-assert where a
  field gate depends on it, but the authoritative minor branch lives in the CF.

## Out of scope for Wave 0
No rules are written or deployed in Wave 0. This file is the contract for what
Wave 2 must implement and emulator-verify. Two-sided green required before PASS.

# CONNECT_WAVE0_SAFETY_CHECKLIST.md — §5 gates as explicit blockers (Phase 0 deliverable #7)

**Date:** 2026-06-18 · **Spec:** `AMEN_CONNECT_V1_SPEC.md` §5. Connect handles children's physical presence, guardian relationships, and sensitive prayer/medical data. Every box below is a launch blocker. The three HELD features require a **named human/counsel decision** — they are absolute stops, not TODOs.

---

## A. Verified guardian link (§5.1) — the foundation

- [ ] `guardianLinks` is server-verified only; no self-asserted link ever flows child PII. (contract: `contracts/connect.ts` `GuardianLink`, `RequestGuardianLinkRequest`)
- [ ] State machine `pending → verified | revoked`; only `verified` unlocks any child read.
- [ ] **HELD FOR "PROCEED":** `requestGuardianLink` + `getChildCheckInStatus` function *bodies*. Phase 0 froze the contract + state machine + the `hasVerifiedGuardianLink` rule. Bodies land after contract-freeze approval (kept out of the hot tree until then). Human decision required: land in Phase 0 now, or in Phase 2 with the other callables?

## B. Minor PII containment (§5.2)

- [ ] Minor data is guardian-only. Never staff-broadcast beyond operational need.
- [ ] **Never** individual-granularity in analytics, dashboard, pulse, or matchmaking — aggregate-only or excluded. (Enforced server-side; rule R7.)
- [ ] Minors never subjects/attributes of Matchmaking, Attendance individual views, Pulse, or Follow-Up targeting.

## C. Check-in & pickup (§5.3) — the only V1 path

- [ ] Kids check-in = QR + numeric pickup-authorization code + authorized-guardian list. (contract: `CheckInRecord`)
- [ ] Pickup is access-control-grade: only listed, verified guardians/authorized adults collect a child.
- [ ] Facial verification is **NOT** a V1 path (see §F).

## D. MEDIA-GATE (§5.4) — fail-closed

- [ ] All uploaded media enters `pending_gate`/quarantine, not served until `approved`. (`mediaRef: null` until approved across all contracts.)
- [ ] Photos containing minors carry an additional consent + visibility gate; default deny; not surfaced to non-guardians.
- [ ] Wire to existing `creatorProfiles` MEDIA-GATE pipeline, do not invent a parallel one.

## E. CalmCap / anti-manipulation (§5.5)

- [ ] No guilt mechanics, streaks, FOMO, or engine-spawned re-engagement notifications. (`ConnectCalmCap.guiltMechanics: false`, `infiniteScroll: false`.)
- [ ] `groupInactivity` ranking input is pastoral re-invitation, never punitive. (`CONNECT_RANKING_WEIGHTS` comment.)
- [ ] Follow-Up / at-risk is care-role-scoped + consented, never minors individually.
- [ ] Engagement signals (dwell/clicks/opens/retention) weight = 0, forbidden.

## F. HELD features (§5.6) — NAMED HUMAN/COUNSEL DECISION REQUIRED (absolute stops)

| Feature | Flag (hard-off) | Required decision before ANY build |
|---|---|---|
| **Kids facial verification (#11) — BLOCKED** | `connect_kids_facial_verification_enabled` | Four-part compliance gate: (1) biometric-vendor contract, (2) **written legal sign-off**, (3) non-engineer review, (4) COPPA counsel. Recommendation: do not ship, possibly ever. Capability is NOT scaffolded. |
| **Community Matchmaking (#15)** | `connect_matchmaking_enabled` | Counsel review of the adult-only, mutual-opt-in, **zero-child-data** redesign. Original "families with kids near your age" form is a permanent red line. Not at V1. |
| **Family Dashboard child data (#12)** | `connect_family_dashboard_enabled` | Gated behind verified guardian link (§A). Without it, dashboard shows the parent's own adult data only. |

**Signal check (from the spec):** if the work starts reframing facial verification as acceptable, that is the signal to STOP, not proceed.

## G. Escalation routing

- [ ] `child_safety_concern` reports use the existing absolute-stop escalation (`SafetyReportingService.swift:168-210` Tier-1 immediate freeze), **not** the normal `connectReports` queue.

---

### Phase 0 status of these gates
Contracts and rules **encode** A–E and G (types, server-only markers, `hasVerifiedGuardianLink`, MEDIA-GATE `null`-until-approved, CalmCap constants, escalation note). Enforcement (function bodies + rules + emulator proof) lands in Wave 1 / Phases 2–3. **F is blocked on named human/counsel decisions and is not built.**

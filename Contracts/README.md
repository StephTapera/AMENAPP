# AMEN Community OS — Phase 0 Frozen Contracts

**Version:** v1.0.0  
**Status:** DRAFT — awaiting human sign-off  
**Date:** 2026-06-05  
**Branch:** amen-discussion-v1  

---

## Index

| Contract | File(s) | Status |
|----------|---------|--------|
| C1 — Object Model & Graph Schema | [C1-object-model.md](C1-object-model.md) | DRAFT |
| C2 — Intent / Action Taxonomy + Transform | [C2-intent-taxonomy.md](C2-intent-taxonomy.md) | FROZEN |
| C3 — Design Tokens + Component API | [C3-design-tokens.md](C3-design-tokens.md) · [stubs/AmenDesignSystem.swift](stubs/AmenDesignSystem.swift) | LOCKED |
| C4 — Cloud Function Signatures | [C4-cf-signatures.md](C4-cf-signatures.md) | DRAFT |
| C5 — Security Rules + RBAC Matrix | [C5-security-rules.md](C5-security-rules.md) · [C5-rbac-test-matrix.md](C5-rbac-test-matrix.md) · [firestore.rules.skeleton](firestore.rules.skeleton) | FROZEN (Phase 0 stubs) |
| C6 — Navigation Contract | [C6-navigation.md](C6-navigation.md) | FROZEN |

### Supporting assets
- `schema.md` — Discussion system Firestore schema (FROZEN)
- `api.ts` / `types.ts` / `index.ts` — Discussion system CF API signatures (FROZEN)
- `SpiritualOS/` — Spiritual OS feature contracts (prior build, FROZEN 2026-06-02)
- `VERSION.md` — Version tag for this contract set

---

## Freeze Protocol

1. Human reviews each contract against the Decision Register below.  
2. Human changes this file's status from `DRAFT` to `FROZEN` and tags the commit `contracts/v1.0.0`.  
3. No agent in Phases 1–6 may touch a contract file after freeze without opening a contract change request (new PR, reviewed by Orchestrator + human).

## Decision Register (humans answer before freeze)

| # | Question | Status |
|---|----------|--------|
| D0 | Theme authority — **RESOLVED: white Liquid Glass, Apple Photos/Mail aesthetic** | ✅ Resolved |
| D1 | Graph cost ceiling — max edge fan-out before denormalize vs. async queue | ❓ Open |
| D2 | Minor age gate + guardian model — confirm thresholds and v1 guardian tools scope | ❓ Open |
| D3 | NCMEC integration timing — when does human-authorized pipeline land | ❓ Open |
| D4 | Anonymous prayer/identity shielding scope for public objects | ❓ Open |

---

## Global Invariants (all agents, all phases)

- **Adapter pattern** for all external dependencies (payments, moderation, TTS, push, AI).
- **Fail closed on safety** — unavailable service ⇒ restrict, never silently allow.
- **Provenance never stripped** — every spawned object carries immutable `ObjectProvenance`.
- **Anti-engagement is testable** — no infinite scroll, no public vanity counters, no comparative metrics, private opt-in streaks, no manipulative notification timing.
- **Privacy defaults conservative** — minors default fully private.
- **Soft-delete + audit everywhere**.
- **White Liquid Glass only** — no dark theme, no gold, no accent purple, no Cormorant Garamond.
- **Extend, do not rebuild** — `moderatePost`, `BibleProvider`, `AmenGlass.swift`, notification engine, Stripe, Firebase Auth.

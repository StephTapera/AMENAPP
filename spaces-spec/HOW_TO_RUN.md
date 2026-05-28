# AMEN Spaces — How to run the agents

Six agents, end-to-end: **audit → fix gaps → implement**. They build the hub layer that
fuses Slack + Outlook/Teams + Patreon into AMEN, in Liquid Glass, made smarter by Berean.

## Files in this directory

- `00_MASTER_CONTRACT.md` — **every agent reads this first.** Schema, boundaries, design,
  agent map. Single source of truth.
- `AGENT_A_data_rules.md` — schema, security rules, entitlements, Stripe-webhook lifecycle.
- `AGENT_B_chat_core.md` — messages/threads/DMs/reactions, Berean SSE reuse, @MainActor.
- `AGENT_C_spaces_shell.md` — navigation + the shared cross-community design components.
- `AGENT_D_creation_wizard.md` — the smart Liquid Glass start flow + Berean scaffolding.
- `AGENT_E_monetization.md` — per-Space Stripe Connect, entitlements, paywall.
- `AGENT_F_cross_community.md` — generic community linking + the "evident" attachment UX.

## Run order (prevents merge/crash chaos)

```
        ┌──────────────┐
        │   AGENT A    │  schema + rules + entitlements  ── MERGES FIRST
        └──────┬───────┘
               │ (CONTRACT_A.md published, rules green)
   ┌───────────┼───────────┬───────────┐
   ▼           ▼           ▼           │
┌──────┐   ┌──────┐    ┌──────┐       │
│  B   │   │  C   │    │  E   │       │
│ chat │   │ shell│    │ pay  │       │
└──┬───┘   └──┬───┘    └──────┘       │
   │           │                      │
   └─────┬─────┘                      │
         │ B and C contracts published │
   ┌─────┴──────┐                     │
   ▼            ▼                     │
┌──────┐    ┌──────┐                  │
│  D   │    │  F   │                  │
│wizard│    │links │                  │
└──────┘    └──────┘                  │
```

1. **A goes alone and merges first.** Nobody wires against A until A is on a branch and
   `CONTRACT_A.md` is published ending with "AGENT_A_COMPLETE".
2. **B, C, E start in parallel** off A. (E only needs A's entitlements.)
3. **D and F start** once B and C have published their contracts (D needs B/C; F needs C).
4. Each agent finishes by publishing its `CONTRACT_x.md` and a 3-line handoff.

## Non-negotiables (from the Master Contract)

- Generic **Community** language — never "church."
- Entitlements flat + Space-scoped; gate = one `get()`.
- **No hard-deletes of in-render data** — status flips only.
- **Money never crosses a community Link (v1).**
- Create-first / link-second (no co-creation in v1).
- One shared style file; tokens only; shared components live in Agent C.
- Reuse existing infra: Berean SSE, SCN block model, Stripe Connect + fee math, RTDB
  presence. Don't fork parallel systems.

## v1 scope vs. fast-follow

- **In v1:** hierarchy (Community→Space→Thread/Study), chat core, the smart wizard,
  per-Space monetization, generic cross-community linking with the evident signal.
- **Fast-follow:** simultaneous co-creation of a shared Space; revenue-sharing across
  linked communities (multi-party Connect + tax); artifact-scoped entitlements.

## Kickoff prompt template for each Claude Code session

```
You are Agent [X] for AMEN Spaces. Read `spaces-spec/00_MASTER_CONTRACT.md` and any
upstream `spaces-spec/CONTRACT_*.md` files that exist, then your task file
`spaces-spec/AGENT_[X]_*.md`. Perform the AUDIT step first and post a gap report
before changing any code. Respect every hard boundary in the Master Contract. Finish
by publishing `spaces-spec/CONTRACT_[X].md` ending with "AGENT_[X]_COMPLETE".
Project root: ~/Desktop/AMEN/AMENAPP copy/
Workspace: AMENAPP.xcworkspace
```

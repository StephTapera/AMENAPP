# ONE — Master Build Plan
# Generated: 2026-06-01 | Lead Orchestrator: Claude Sonnet 4.6
# Status: STEP A COMPLETE — awaiting gate review before P0 work begins

---

## 0. Guiding Invariants

1. **ONE-FINDING → ONE-FIX → ONE-VERIFIED-BUILD.** No batched unverified edits.
2. **CONTRACTS.md is frozen.** Any amendment requires a logged entry in RUNLOG.md and orchestrator approval before any agent implements against the changed contract.
3. **HTML proto exists before SwiftUI.** Every screen/flow must have an HTML/CSS/JS Liquid Glass prototype that proves layout and interaction before native code is written.
4. **No broad deploy.** Each phase gate produces a narrowly-scoped deploy checklist; nothing auto-runs.
5. **Honesty over theater.** If a feature cannot be fully enforced (screenshot blocking, E2E + AI), the implementation is labeled best-effort in both UX copy and code comments.

---

## 1. Phase List

| Phase | Name | Depends On | Gate Condition |
|-------|------|-----------|----------------|
| P0 | Foundations | — | Contracts frozen, tokens compile, Firestore rules drafted, auth wired, callable skeleton compiles, all HTML protos for P1 exist |
| P1 | People + Private Messaging | P0 | E2E thread create/send/receive works offline-safe, Living Threads on-device, consent flags enforced in UI + callable |
| P2 | Moments (Camera + Content) | P0 | Capture → format → privacy contract → send/post flow works end-to-end; provenance labels shown; decay scheduler wired |
| P3 | World (Discovery) | P1, P2 | All five feed modes navigable; reach budget decrements; context gate blocks comment without qualifying action |
| P4 | Differentiators | P1, P2, P3 | Privacy mirror symmetry verified; sticky consent travels with shared moment; repair flow opt-in proven; vault encrypted at rest |
| P5 | Safety + Hardening | P4 | Emotional safety mode friction tested; evidence path survives deletion; a11y sweep passes; moderation rules published |

---

## 2. Dependency Graph

```
P0 Foundations
├── P1 People (E2E, Living Threads, Consent)
│   └── P4 Differentiators (privacy mirror, repair flow, legacy)
├── P2 Moments (Camera, Provenance, Decay)
│   └── P3 World (feed modes, reach budget, context gate)
│       └── P4 Differentiators (symmetric visibility, witnesses, sticky consent)
└── P5 Safety (wraps all zones; last gate before ship)
```

Cross-cutting (run throughout every phase):
- Reduce-motion compliance on every new animation
- App Check token on every callable
- Accessible labels on every interactive element
- Privacy contract enforcement check before every data write

---

## 3. Frozen Shared Contracts (defined in CONTRACTS.md)

| Contract Type | Name | Immutable Core |
|--------------|------|---------------|
| Universal content object | `ONEMoment` | id, authorUID, type, privacy, provenance, content, consentDNA, reachBudget |
| Privacy first-class object | `ONEPrivacyContract` | audience, lifetime, permissions, safety |
| User identity | `ONEUser` | uid, privacyMirror, presenceState, entitlement |
| E2E thread | `ONEThread` | mlsGroupID, participantUIDs, encryptionVersion |
| Feed session | `ONEFeedMode` | mode enum, sessionBudget, autoplayEnabled |
| Content provenance | `ONEProvenanceLabel` | label enum, c2paPayload, confidence |
| Anti-virality | `ONEReachBudget` | sharesRemaining, chainDepth |
| Witness relationship | `ONEWitness` | season, expiresAt, mutualExposureLevel |
| Memory vault item | `ONEVaultItem` | encryptedPayload, accessRules, timeReleaseAt |
| Legacy directive | `ONELegacyDirective` | trustees, bequests, memorialization |
| Repair flow | `ONERepairFlow` | participants, phase, toneChecks |
| Entitlement | `ONEEntitlement` | tier (free/subscriber), stripeSubID, validUntil |

---

## 4. Work Units by Phase (parallelizable units marked ‖)

### P0 — Foundations (sequential bootstrap → parallel execution)

```
P0-A  Design tokens file (ONETokens.swift) — SEQUENTIAL FIRST
P0-B  ‖ HTML proto: Three Zones shell (People / Moments / World nav)
P0-C  ‖ HTML proto: Privacy Contract pill (Liquid Glass, all controls)
P0-D  ‖ HTML proto: Moment composer skeleton (privacy scope picker)
P0-E  ‖ Firestore schema + security rules draft (rules file only, NO deploy)
P0-F  ‖ ONEMoment + ONEPrivacyContract Swift data models (compile-gated)
P0-G  ‖ Firebase Auth + App Check wiring for ONE module
P0-H  ‖ Cloud Functions callable skeleton (one_sendMoment stub, App Check enforced)
P0-I  ‖ ONENavigationShell SwiftUI (Three Zones tab bar, glassEffect dock)
P0-J  GATE: full build verify + HTML proto review
```

### P1 — People + Private Messaging

```
P1-A  ‖ HTML proto: DM thread view (consent badges, Living Threads summary card)
P1-B  ‖ HTML proto: New message composer (per-message permission toggles)
P1-C  HTML protos gate → SwiftUI E2E thread service (MLS key exchange stub, Firestore ciphertext only)
P1-D  ‖ SwiftUI: Thread list view (ONEThreadListView)
P1-E  ‖ SwiftUI: Message view (ONEMessageView, consent badge per bubble)
P1-F  ‖ On-device Living Threads AI distillation (FoundationModels or local summarizer)
P1-G  ‖ Consent enforcement: forward/save/quote/react flags honored in UI + server reject
P1-H  ‖ Ephemeral group creation + expiry flow
P1-I  GATE: E2E round-trip smoke test, consent flags verified, build clean
```

### P2 — Moments (Camera + Content)

```
P2-A  ‖ HTML proto: Liquid Camera unified capture surface
P2-B  ‖ HTML proto: Moment format picker (snap/story/post/memory/message/etc.)
P2-C  HTML protos gate → SwiftUI ONELiquidCameraView
P2-D  ‖ SwiftUI: Moment format selector + privacy scope binding
P2-E  ‖ Provenance label service (on-device image analysis → label + C2PA stub)
P2-F  ‖ Decay scheduler CF (one_expireMoment scheduled trigger)
P2-G  ‖ Earned permanence: "Remember this" explicit action + UI
P2-H  ‖ Album + collaborative memory flow
P2-I  GATE: capture → send → appear → decay cycle verified; provenance label visible
```

### P3 — World (Discovery)

```
P3-A  ‖ HTML proto: Feed mode switcher (Close/Create/Learn/Local/Quiet)
P3-B  ‖ HTML proto: Reach budget indicator (social capital visual)
P3-C  ‖ HTML proto: Context-before-comment gate screen
P3-D  HTML protos gate → SwiftUI ONEWorldFeedView (five modes, session budget, no autoplay)
P3-E  ‖ Reach budget CF: one_relayMoment decrements sharesRemaining
P3-F  ‖ Context gate: read-source / watch-% / provenance-seen checks before comment enabled
P3-G  ‖ Witness model: follow replaced by witness request, season-scoped
P3-H  GATE: all five modes render; context gate blocks; reach budget decrements; build clean
```

### P4 — Differentiators

```
P4-A  ‖ HTML proto: Privacy mirror settings (exposure level selector)
P4-B  ‖ HTML proto: Repair flow steps (both-party opt-in, tone check, exit)
P4-C  ‖ HTML proto: Memory vault + time-release composer
P4-D  HTML protos gate → SwiftUI privacy mirror enforcement (ONEPrivacyMirrorService)
P4-E  ‖ Sticky consent: ConsentDNA attached to shared moment, honored on ingest
P4-F  ‖ Repair flow SwiftUI (ONERepairFlowView, both-party CF orchestration)
P4-G  ‖ Memory vault SwiftUI (encrypted CryptoKit, per-item rules, time-release display)
P4-H  ‖ Legacy directive composer (ONELegacyDirectiveView, trustee assignment)
P4-I  GATE: mirror symmetry test; sticky consent survives share; vault decrypts locally; repair flow both-party gate verified
```

### P5 — Safety + Hardening

```
P5-A  ‖ Emotional safety mode: slow-reply friction, tone preview, delay-send, pause thread
P5-B  ‖ Metadata-only immune signals (CF operates on public metadata, NOT E2E content)
P5-C  ‖ Abuse evidence path: one_reportMoment locks server-side evidence before decay
P5-D  ‖ Moderation rules SECURITY.md v2 + published policy text
P5-E  ‖ Accessibility sweep (all new ONE views: labels, hints, reduce-motion, contrast)
P5-F  ‖ Subscription entitlement gating (Stripe checkout, ONEEntitlement checks)
P5-G  ‖ App Check + Auth hardening audit on all new callables
P5-H  GATE: evidence path tested (report → lock → decay → evidence still exists); a11y audit passes; entitlement gates verified; final build clean
```

---

## 5. HTML Prototype Inventory

Every proto lives in `/ONE/prototypes/` as a self-contained HTML file.
Before any SwiftUI work begins on a screen, the corresponding HTML file must exist and be noted in RUNLOG.md.

| Proto File | Covers | Required Before |
|-----------|--------|----------------|
| `p0-three-zones-nav.html` | People/Moments/World shell + glass dock | P0-I |
| `p0-privacy-pill.html` | Privacy Contract pill (all controls) | P0-F |
| `p0-moment-composer.html` | Moment composer skeleton | P0-F |
| `p1-dm-thread.html` | DM thread view + consent badges | P1-C |
| `p1-message-composer.html` | Per-message permission toggles | P1-C |
| `p2-liquid-camera.html` | Unified capture surface | P2-C |
| `p2-moment-picker.html` | Format picker + privacy scope binding | P2-C |
| `p3-feed-modes.html` | Five feed modes + session budget | P3-D |
| `p3-reach-budget.html` | Reach budget / social capital indicator | P3-E |
| `p3-context-gate.html` | Context-before-comment gate screen | P3-F |
| `p4-privacy-mirror.html` | Exposure level selector | P4-D |
| `p4-repair-flow.html` | Repair flow steps | P4-F |
| `p4-vault.html` | Memory vault + time-release | P4-G |

---

## 6. File Placement in AMEN Project

New ONE code lives under `AMENAPP/AMENAPP/ONE/` with the following top-level subdirectories:

```
ONE/
  Core/           — ONEMoment, ONEPrivacyContract, ONEUser, token types
  People/         — E2E threads, Living Threads, consent UI
  Moments/        — Camera, format picker, provenance, decay
  World/          — Feed modes, reach budget, context gate, witnesses
  Differentiators/ — Privacy mirror, sticky consent, repair, vault, legacy
  Safety/         — Emotional safety, immune signals, evidence path
  Design/         — ONETokens, Liquid Glass ONE components
  Backend/        — CF callable stubs (deploy checklist only, no auto-deploy)
```

Planning docs (this file, CONTRACTS.md, SECURITY.md, RUNLOG.md) live in `/ONE/` at project root level.

---

## 7. Open Risks (P0 Gate)

| Risk | Severity | Mitigation |
|------|---------|-----------|
| MLS library not available on iOS 26 | HIGH | Use CryptoKit + custom key ratchet as fallback; document protocol downgrade |
| FoundationModels on-device for Living Threads may be iOS 26 only | MEDIUM | Gate behind availability check; fallback to rule-based extraction |
| Stripe iOS SDK not in current Firebase project deps | MEDIUM | Add via SPM in P5; flag for manual Xcode target addition |
| C2PA standard not natively supported on iOS | LOW | Use C2PA-style semantic model; degrade gracefully to "Unknown" |
| Existing AMEN types may conflict with ONE types (e.g., existing `Thread`, `Message` structs) | MEDIUM | All ONE types prefixed `ONE` to avoid collision; no existing types modified |
| glassEffect API availability (iOS 26 only) | MEDIUM | Wrap in `#if os(iOS) && swift(>=6.0)` availability guard with fallback |

---

## 8. Deploy Checklist (P0 Gate — DO NOT AUTO-RUN)

```
[ ] firebase deploy --only firestore:rules  (after rules file reviewed by human)
[ ] firebase deploy --only functions:one_sendMoment  (stub only, no logic yet)
[ ] firebase deploy --only functions:one_expireMoment  (stub only)
```
All other CF deploys are deferred to their phase gate.

---

## GATE STATUS: AWAITING P0 REVIEW
Do not proceed to P0 implementation until this PLAN.md is acknowledged.

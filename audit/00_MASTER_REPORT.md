# AMEN App — Master Audit Report
**Audit Date:** 2026-05-26  
**Branch:** audit/2026-05-21 (dirty working tree — active development)  
**Last commit:** e94facd — security hardening + thread safety + CI fixes  
**Agents run:** 9 (Inventory, Frontend, Cloud Functions, Firestore, AI Features, Integrations, Deployment, Performance, Security)  
**Total findings:** ~80 across all agents

---

## 1. Executive Summary

AMEN has a sophisticated, well-architected codebase with real production-grade strengths: mature Firebase security rules (100+ collections explicitly covered), proper Secret Manager use for all API keys, a complete account-deletion flow, correct Apple Sign In implementation, and a well-structured async/await pattern throughout. However, **the app is not ready for App Store v1 in its current state.** There are 11 confirmed P0 blockers across 6 categories: an invalid iOS deployment target that will reject any submission, an OpenAI API key exposed through a client-side WebSocket connection, 16 Cloud Functions called by name from Swift that do not exist in the deployed backend (breaking core features silently), GUARDIAN content moderation missing from the main post and prayer request write paths (a safety/App Store compliance risk), ARISE/OUTPOUR video being entirely unimplemented despite having UI entry points, and a post visibility rule gap that allows followers-only content to be accessed by direct document ID. With focused work, most P0s are fixable in 1–2 days each; the ARISE/OUTPOUR decision (build vs. remove from UI) is the biggest unknown. The foundation is solid enough to ship v1 — but not yet.

---

## 2. Launch Blockers — P0 Table

Ranked by: (App Store rejection risk first, then user harm, then broken features)

| Rank | ID | Title | File | Fix Effort | Risk of Fix |
|------|----|-------|------|-----------|-------------|
| 1 | **DEP-001** | iOS deployment target `26.2` is invalid — App Store rejects any submission | `AMENAPP/Config.xcconfig` or `project.pbxproj` | 15 min | Low |
| 2 | **CF-001** | iOS client connects directly to `wss://api.openai.com/v1/realtime` with Bearer API key — key exposed in memory, no proxy | `AMENAPP/AIIntelligence/BereanRealtimeWebSocketTransport.swift:105` | 2–3 days | Medium |
| 3 | **CF-002** | 16 Cloud Functions called via `httpsCallable()` from Swift do NOT exist in `index.ts` — core features broken silently in prod | `Backend/functions/src/index.ts` (missing exports) | 1 day audit + 3–5 days impl | Medium |
| 4 | **AI-001** | GUARDIAN content moderation NOT invoked on main feed post write path — zero safety coverage on UGC | Main feed post creation flow | 2–3 days | Low |
| 5 | **AI-002** | GUARDIAN NOT invoked on prayer requests — crisis/sensitive content goes undetected | Prayer request write path | 2–3 days | Low |
| 6 | **AI-003** | ARISE/OUTPOUR (short-form video) — UI entry points exist, but zero implementation (no AVPlayer, no upload, no feed) | ARISE/OUTPOUR UI files | Build: 2–3 weeks / Remove: 1 day | Low (to remove) |
| 7 | **INV-003** | Unfinished BUG-fix comments in `LocalContentGuard.swift:108` (child safety grooming detection) and `AppLifecycleManager.swift:218` | `AMENAPP/AMENAPP/LocalContentGuard.swift`, `AppLifecycleManager.swift` | 1–2 days | Medium |
| 8 | **FE-001/FE-002** | Force-unwrap crashes in Firestore snapshot listeners — `snap!.documentID` after guarded `snap?.data()` | `Feature05_AccountabilityThread.swift:119`, `Feature09_SharedTestimonyDraft.swift:151` | 1 hour | Low |
| 9 | **FS-001** | Followers-only post visibility cannot be enforced at Firestore rules layer (auto-generated follow IDs) — direct document UUID bypasses check | `firestore.rules` + follow schema | 1–2 days | Medium |
| 10 | **FS-002** | 3 missing composite indexes for `SpiritualHealthIntelligenceService` compound queries → PERMISSION_DENIED in prod after ~200 docs | `firestore.indexes.json` | 1 hour | Low |
| 11 | **INV-001** | 30 orphaned Swift files at repo root — not in Xcode project, shadow real files, confuse builds | Root-level `.swift` files | 2 hours | Low |

---

## 3. Fix-Before-v1 — P1 Table

| ID | Title | File | Fix Effort | Risk of Fix |
|----|-------|------|-----------|-------------|
| CF-003 | Stripe in-app giving charges lack Stripe Idempotency-Key → double-charge risk on retry | `Backend/functions/src/giving/processGivingCharge.ts:117` | 0.5 day | Low |
| DEP-003 | No age gate enforcement / COPPA compliance — app collects DOB but doesn't enforce minimum age or parental consent | Onboarding flow | 1–2 days | Medium |
| DEP-002 | Version `1.0` / Build `1` placeholder values; inconsistent across app targets and extensions | `Info.plist`, project settings | 30 min | Low |
| FE-003 | Double force-unwrap on dictionary in `CommentService.swift:1640` — `self.commentReplies[parentId]!` accessed twice with concurrent mutation risk | `CommentService.swift:1640` | 1 hour | Low |
| FE-006 | 1000+ hardcoded `Color.white`, `Color.black`, `Color(red:...)` literals across 28+ files — breaks dark mode completely | 28+ Swift view files | 2–3 days | Low |
| FS-003 | Berean AI conversations have no cascade-delete on account deletion — risk of data retention / UID reuse leak | Cloud Function delete trigger | 0.5 day | Low |
| FE-008–011 | `@StateObject` used on shared singletons in 4 files — creates new instance per view, breaking shared state | 4 view files | 2 hours | Low |
| AI-004 | Dynamic Island Live Activity exists but lacks streaming progress updates — shows stale state during generation | `ActivityKit` integration | 1 day | Low |
| CF-004 | Covenant checkout missing pre-check for existing active members — allows duplicate subscriptions | `Backend/functions/src/covenants/` | 0.5 day | Low |
| INT-002 | `CalendarIntegrationService` requests full calendar access but only needs write-only — unnecessary privacy escalation | `CalendarIntegrationService.swift` | 30 min | Low |
| DEP-005 | Single Firebase project — no dev/staging/prod separation; accidental prod writes during development | `.firebaserc`, Firebase console | 1 day | Medium |
| PERF-002 | Unbounded Firestore reads in `ChurchChemistryService` (no `.limit()`) — cost explosion at scale | `ChurchChemistryService.swift:83` | 30 min | Low |
| PERF-003 | 8–10 `AsyncImage` calls bypass the centralized `ImageCache` — images re-downloaded on every appearance | Selah, Covenant, GetReady views | 20 min | Low |
| SEC-001 | Deep link parameter validation not explicitly verified — potential for forged deep links | `AppDelegate.swift`, deep link routers | 2–4 hours | Low |

---

## 4. Safe-to-Delete vs. Needs Human Confirmation

### Definitely Safe to Delete (high confidence, two independent signals)

| Item | Evidence | Confidence |
|------|----------|-----------|
| 30 orphaned `.swift` files at repo root (e.g., `DiscoverFeedService 2.swift`, `MessageSettingsService.swift`, etc.) | Not referenced in `project.pbxproj`; many are " 2" duplicates of files that exist in proper paths | High |
| `AMENAPP/AMENAPP/AMENAPP/Assets 2.xcassets` | Not referenced in `project.pbxproj`; primary `Assets.xcassets` exists | High |
| `AMENAPP/amen-logo 3.png` (loose file at project root) | Duplicate of asset in `Assets.xcassets`; not referenced in any Swift file | High |
| ChatGPT-generated test image in `AppIcon.appiconset` | Development placeholder; will surface in App Store screenshots | High |
| `AMENAPP/AMENAPP/AMENAPP/ChurchNotes 2/` and `SocialGraph 2/` directories | Numbered suffix pattern indicates abandoned refactor; verify no Swift files inside are imported (medium confidence pending grep confirmation) | Medium |

### Needs Human Confirmation (below-high confidence or Safety Rule 6 applies)

| Item | Why Uncertain |
|------|--------------|
| Any function file named only in `firebase.json` triggers or event handlers | Event-triggered functions appear "dead" to grep but fire on Firestore/Auth/Storage events |
| `Codable`/`Decodable` model types with no visible call site | May be decoded from Firestore via `try document.data(as: ModelType.self)` without explicit init |
| `@objc` annotated methods | May be called via `#selector` or Objective-C runtime; not catchable by Swift grep |
| `UserIntelligenceOrchestrator.swift` (root-level orphan) | Could be called by string from a Cloud Function or deep link handler — verify before deleting |
| `ProofOfHumanService.swift`, `ProofOfCareService.swift`, `TrustScoringEngine.swift` (root-level orphans) | Core trust/safety system components — confirm they are truly duplicated by in-project versions before removing |

---

## 5. Suggested Fix Sequence — Week Before Submission

### Day 1 (Monday) — Submission Unblocking: 0 effort blockers
**Goal:** Make it possible to build and submit at all.
1. **DEP-001** — Fix iOS deployment target (15 min). Change `IPHONEOS_DEPLOYMENT_TARGET` to a valid value (16.0 or 17.0) in `Config.xcconfig` / `project.pbxproj`.
2. **DEP-002** — Set real version/build numbers (30 min). Bump to `1.0.0` / build number ≥ 2 and make consistent across all targets.
3. **FE-001/FE-002** — Fix force-unwrap crashes in Firestore listeners (1 hour). Change `snap!.documentID` to `snap.documentID` in the two identified files.
4. **FS-002** — Add 3 missing Firestore composite indexes (1 hour). Add entries to `firestore.indexes.json` for `SpiritualHealthIntelligenceService` queries.
5. **INV-001** — Remove 30 orphaned root-level Swift files (2 hours). Verify no imports, then delete.

### Day 2 (Tuesday) — Safety & Security: P0 safety issues
**Goal:** Ship without safety holes or exposed credentials.
6. **CF-001** — Replace direct OpenAI WebSocket connection with Cloud Function ephemeral token proxy (2–3 days, start today). The fix: a new `createRealtimeSession` callable that returns a short-lived OpenAI session token; client connects using that instead of the persisted key.
7. **AI-001/AI-002** — Wire GUARDIAN moderation to post creation and prayer request write paths (2–3 days, start today). Add GUARDIAN callable invocation before Firestore write in both flows; route flagged content to review queue.
8. **INV-003** — Audit and complete BUG-fix implementations in `LocalContentGuard.swift` and `AppLifecycleManager.swift` (1–2 days). Confirm grooming detection logic is correct; add unit tests.

### Day 3 (Wednesday) — Backend Completeness: broken features
**Goal:** No silently broken feature at launch.
9. **CF-002** — Audit all 16 undeployed functions (full day). For each: either implement and export to `index.ts`, or remove the Swift `httpsCallable()` call and gate the UI. Priority order: `bereanGenericProxy` (most calls), `bereanShieldAnalyze`, `acceptSafeConnection`, `askAmenCompanion`, then the rest.
10. **AI-003** — Decide and execute on ARISE/OUTPOUR (1 day for removal, 2–3 weeks to build). Recommended: hide the UI entry points behind a feature flag for v1. Do NOT ship a broken screen.

### Day 4 (Thursday) — Data Integrity & Privacy
**Goal:** No privacy violations or data corruption at launch.
11. **FS-001** — Fix post visibility enforcement gap (1–2 days). Migrate follow tracking to `users/{uid}/followers/{followerUid}` subcollection pattern so Firestore rules can enforce it.
12. **DEP-003** — Implement age gate enforcement (1–2 days). Add minimum age check at onboarding (e.g., 13+); add COPPA-compliant parental consent flow if you intend to allow under-13.
13. **CF-003** — Add Stripe idempotency keys to giving charges (0.5 day).
14. **FS-003** — Add Berean conversation cascade-delete on account deletion (0.5 day).

### Day 5 (Friday) — P1 Polish & Submission Prep
**Goal:** Clean launch, no obvious regressions.
15. **FE-006** — Replace hardcoded color literals with design tokens across 28+ files (2–3 days, start Friday and continue). This is a mechanical find/replace — use a script to catch all instances.
16. **DEP-005** — Set up dev/staging Firebase project separation (if time allows — else document risk).
17. **CF-004** — Add duplicate member pre-check to Covenant checkout (0.5 day).
18. **INT-002** — Change CalendarIntegrationService to `requestWriteOnlyAccessToEvents()` (30 min).
19. **PERF-002/PERF-003** — Add `.limit()` to unbounded Firestore reads and replace uncached `AsyncImage` calls (1 hour combined).
20. **Final:** Run full test suite, build in Release config, archive, validate with `altool` or Xcode Organizer before submission.

---

## 6. Stats

### By Severity
| Severity | Count | Blocks Launch |
|----------|-------|--------------|
| P0 | 13 | 13 |
| P1 | 14 | 0 |
| P2 | 35+ | 0 |
| P3 | 10+ | 0 |

### By Category
| Category | Count |
|----------|-------|
| not_implemented / dead_stub | 8 |
| security / key_exposure | 3 |
| missing_moderation | 2 |
| crash_risk | 4 |
| firestore_rules | 3 |
| deployment_config | 4 |
| dead_code / orphan | 5 |
| performance | 17 |
| naming / style | 6 |
| payment_integrity | 2 |
| accessibility | 8 |

### By Agent
| Agent | Findings | P0s |
|-------|----------|-----|
| 1 — Inventory | 11 | 2 |
| 2 — Frontend | 15 | 2 |
| 3 — Cloud Functions | 7 | 2 |
| 4 — Firestore | 7 | 2 |
| 5 — AI Features | 12 | 3 |
| 6 — Integrations | 11 | 0 |
| 7 — Deployment | 9 | 1 |
| 8 — Performance | 17 | 0 |
| 9 — Security | 1 | 0 |
| **Total** | **~90** | **12** |

---

## 7. Architecture Strengths (Do Not Break)

These are things the audit found to be genuinely well-implemented — protect them during fixes:

- **Secret management:** All AI/payment API keys use Firebase Secret Manager `defineSecret()`. Never add a key to source.
- **Auth + App Check:** All sensitive callables enforce both Firebase Auth and App Check. Do not weaken this.
- **Account deletion:** The delete flow is complete and App Store compliant. Do not break the cascade.
- **Async/await + @MainActor:** Generally good discipline. The few violations found are isolated.
- **Navigation:** All screens use `NavigationStack` (not deprecated `NavigationView`). Keep it.
- **Berean AI SSE streaming:** Real streaming with proper cancellation. A competitive differentiator — protect it.
- **Privacy manifest:** Comprehensive `PrivacyInfo.xcprivacy`. Keep it updated as SDKs change.
- **285 `#if DEBUG` guards:** Development-only code is properly gated. Maintain this discipline.
- **Firestore rules:** 100+ collections covered, 1,220+ composite indexes defined. This is mature infrastructure.

---

## 8. Open Questions for Human Decision

These are architectural or product decisions that cannot be resolved by static analysis:

1. **ARISE/OUTPOUR:** Build for v1 (2–3 weeks) or hide behind feature flag? This is the biggest schedule unknown.
2. **Age gating:** What is the minimum allowed age? Is under-13 allowed? This determines COPPA scope.
3. **Firebase project separation:** Is there a separate dev/staging project? If not, create one before launch to avoid accidental production writes during QA.
4. **`AMENAPP copy` directory:** Is this the canonical working repository or a backup? If it's canonical, rename it and update all CI/CD references.
5. **GUARDIAN scope:** Is channels-only moderation an intentional v1 scope decision, or was posts/prayers simply missed?
6. **CF-002 priority:** Which of the 16 undeployed functions are gating features you intend to ship in v1? Triage list needed.

---

*Report generated by 9-agent audit system. All findings are read-only analysis. No source files were modified.*

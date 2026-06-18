# AMEN — Uncommitted-Work Inventory (read-only snapshot)

**Date:** 2026-06-17 · **Author:** Claude (QA session) · **Method:** read-only `git status`/`stash list`. Nothing mutated.

> **STEP ZERO (do this before any convergence):** the work below is NOT in git on any branch.
> In a 7-agent shared tree with 10 stashes, one `reset --hard` / `clean` / mis-popped stash loses
> it permanently. **First action = each agent commits ITS OWN group to a durable branch,
> path-scoped (never `git add -A`).** Convergence onto `cert/clean-launch` comes AFTER, human-driven,
> one feature at a time. This map is the precursor, not a merge plan.
>
> Snapshot is volatile — 7 agents are editing live; re-run `git status` before acting.

---

## TIER A — STASHES (highest risk: on no branch, easy to lose) — 10 total
Triage each: restore to its owning branch and commit, or confirm disposable, then drop.
```
stash@{0}  On feature/berean-island-w0: pre-remediation-gate baseline unstaged (parallel agents, 2026-06-15)
stash@{1}  On audit/overnight-20260601: wip ConnectSpaces binding service
stash@{2}  On overnight/design-pass-20260530: design-pass-wip-pre-perf-20260531-0645
stash@{3}  WIP on overnight/design-pass-20260530: media isLoading/error states (AmenMediaSessionView)
stash@{4}  On audit/overnight-20260530: pre-audit stash conversationOSFunctions
stash@{5}  WIP on berean/ui-rebuild-liquid-glass-v1: audit(v4) UX/DM/privacy/CF rate limit
stash@{6}  On main: temp before restoring today stash
stash@{7}  On main: save current local changes before Xcode apply
stash@{8}  On main: pre-cleanup after pbxproj recovery
stash@{9}  On (no branch): temp before rebase continue   ← MOST fragile (detached)
```
**Action:** human triages stashes individually (`git stash show -p stash@{n}`). Do NOT blanket-drop.

## TIER B — UNTRACKED (not in git at all — vanish on `git clean`) — 6 items / 11 files
| Group | Files | Likely owner → durable branch |
|---|---|---|
| **Settings/Appearance OS** | `AMENAPP/AMENAPP/DesignSystem/Settings/AccentColorPalette.swift`, `…/AppearanceController.swift`, `AMENAPP/AMENAPP/Features/Settings/Appearance/AppearanceSettingsView.swift`, `…/Features/Settings/Foundation/{SettingsAnalytics,SettingsAuditClient,SettingsCallableClient,SettingsDisabledSurface,SettingsFlagGate,SettingsFlagsService}.swift` (9 files) | "Request for UI change" / Settings-safety agent → `feature/settings-os` |
| **Berean Study Hub** | `AMENAPP/AMENAPP/Features/Berean/Home/BereanStudyHubView.swift` | Berean agent → its branch |
| **Creator gate** | `AMENAPP/CreatorProfileGate.swift` | Creator agent |
| **Bug review report** | `BUG_REVIEW_2026_06_17.md` | "Find potential bugs" agent |

## TIER C — TRACKED but UNCOMMITTED (modified/staged/deleted) — 73 changes
Grouped by feature → who commits it to which branch:

| Feature group | Representative paths | → durable branch / owner |
|---|---|---|
| **Selah Sensory Layer** | `AIIntelligence/SELAH_SENSORY_LAYER.md` (A), `SelahMomentService.swift`, `Contracts/Protocols/SelahProtocols.swift`, `AmenHealthyImmersiveMediaSystem.swift`, `AmenLiturgicalContextStore.swift` (A) | "Selah Sensory Layer" agent → `feature/selah-sensory-layer` |
| **Berean Voice OS Wave 0** | `BereanVoiceOS/Wave0/*` (7 docs, A/AM), `BereanVoiceFeatureFlags.swift`, `BereanRealtimeTransportCoordinator.swift` | "Berean Voice OS" agent → `feature/berean-voice-os` |
| **Berean (design/system)** | `BereanAgentTopBarView`, `BereanDesignSystem`, `BereanMultilingualContracts`, `BereanSmartPillSystem`, `BereanTheologyBoundaryService`, `DesignSystem/BereanGlass/*`, `DesignSystem/BereanLight/*`; **deleted** `Features/Berean/Home/BereanHomeView.swift` (D) | Berean agent(s) — confirm the deletion is intentional |
| **Creator** | `Creator/ViewModels/{BrandKit,Export,Home,Project,Publish}ViewModel.swift` (5 M) | Creator agent |
| **Threshold (auth/reauth)** | `Threshold/ReauthGate.swift`, `ThresholdContracts.swift`, `ThresholdView.swift`; **deleted** `ProfileSessionStoreTests.swift`, `ReauthGateTests.swift` (D) | ⚠️ auth-adjacent — owner confirms; deleted tests need a reason |
| **Connect / Spaces** | `ConnectSpaces/Monetization/AmenSpaceEntitlementService.swift`, `SpacesViewModel.swift` | Connect agent |
| **Permissions / Consent** | `ContentOS/ContentPermissionEngine.swift`, `Features/PermissionsCenter/ConsentStore.swift` (A) | Permissions agent |
| **Visits / Giving** | `Features/Bridges/Visits/VisitVerificationService.swift` (A), `Bridges/GivingMemory/GivingImpactView.swift` | Bridges agent |
| **Repo hygiene / secrets** | `.github/workflows/gitleaks.yml` (A), `.gitleaks.toml` (A) | "Repo hygiene" agent → its branch |
| **Broad / uncategorized (~30)** | `AppDelegate.swift`, `ProfileView.swift`, `PushNotificationManager.swift`, `firebase.json`, `Docs/FUNCTION_INVENTORY.md`, `GlobalResilienceWiring.swift`, `MessagePrayerBridge.swift`, many `Smart*`/`Music*`/`Church*` services | mixed — needs per-file owner attribution before commit |

### ⚠️ Flags worth a human eye
- **`firebase.json` (M)** and **`AppDelegate.swift` (M)** may be the **emulator unblock-kit in progress**
  (storage:9199 + `-useFirebaseEmulator` wiring §2). If so, that's the QA-enablement work — don't lose it;
  confirm with the QA-framework agent before anyone reverts.
- **Deletions (D):** `BereanHomeView.swift`, two `Threshold/*Tests.swift` — confirm intentional (refactor)
  vs accidental before committing the deletions; they're recoverable from HEAD until then.
- **`.build-lock` (M)** — leave OUT of every commit.
- Files with index+worktree status (`AM`, `M `, `A `) are partially staged — `git add` the final state per file.

---

## Recommended sequence
1. **Commit-to-durable (each agent, NOW):** every agent path-scope-commits its own group above to its
   own branch. Untracked (Tier B) and stashes (Tier A) first — they're the losable ones.
2. **Map confirmed:** owners confirm their feature is fully committed (nothing left in working tree/stash).
3. **Converge (human-driven, later):** merge each committed feature onto `cert/clean-launch` one at a time,
   resolving overlaps deliberately — **especially safety/auth files** (Threshold, Permissions, moderation),
   where a control can be silently clobbered in a merge.
4. **Isolated build:** build `cert/clean-launch` alone (other agents paused) — that's v1's build gate.

This QA wave's own work is already safe: committed on `qa/auto-sweep-2026-06-17` (`88324f5e`, `b847cf93`).

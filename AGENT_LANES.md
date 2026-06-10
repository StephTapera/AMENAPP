# AMEN Agent Lanes

> 🚫 **GLOBAL RULE (2026-06-09, effective now): NO AGENT DELETES FILES OUTSIDE ITS OWN LANE.** Any deletion — even own-lane — is declared in this manifest with a one-line reason BEFORE staging. Undeclared deletions get restored on sight by the owning lane.

## Resolve Missing Package Products

- Owner: Codex current session
- Claimed: 2026-06-09 America/Phoenix
- PROJECT_ROOT: `/Users/stephtapera/Desktop/AMEN/AMENAPP copy`
- Active project: `./AMENAPP.xcodeproj`
- Shared package paths: `./SourcePackages`, `./DerivedData`, `./PackageCache`
- Scope: Drive `AMENAPP` generic iOS Simulator build to green by repairing Swift Package product resolution.
- Hotspot: `AMENAPP.xcodeproj/project.pbxproj`; use smallest possible package-reference diff only.
- Latest diagnostic: NoteShare runtime proof attempted 2026-06-09. Simulator is available, but install/build is blocked by unrelated dirty-worktree project membership errors, including duplicate `ChurchNotesReminderService.stringsdata`; a prior install attempt also surfaced unresolved `ActionIntelligenceSourcePayload` / `ActionIntelligenceService` symbols in `UnifiedChatView.swift`.

## NOTE_SHARE_VIEWER Closers

- Owner: Codex current session
- Status: Blocked, not DONE.
- Flag: `feature_note_share_viewer` remains OFF by default.
- Completed: Wave 1 accepted; root `amen://note-share/{shareId}` sheet routing added behind the flag; DEBUG-only runtime proof service and launch-only flag override added for simulator proof.
- Blocker: runtime simctl screenshots cannot be captured until the unrelated build failures above are resolved.
- Required before release: simctl screenshots for shared-note deep link, revoked-share empty state, and share sheet `Copy smart note link` action.

## FirebaseAI Cleanup Lane Task

- **pbxproj dedup request:** Fold the duplicate `ChurchNotesReminderService.stringsdata` target-membership fix into the FirebaseAI cleanup checkpointed commit; `project.pbxproj` is hot and must not be edited by the NoteShare lane. Literal grep for `ChurchNotesReminderService` returns no `project.pbxproj` entry, so this appears to come from synchronized group membership. Relevant lines: `AMENAPP.xcodeproj/project.pbxproj:499-504` (`Exceptions for "AMENAPP" folder in "AMENAPP" target`), `536-542` (`PBXFileSystemSynchronizedRootGroup` path `AMENAPP`), and `1219-1221` (`AMENAPP` target `fileSystemSynchronizedGroups`). Build error to clear: `Multiple commands produce .../ChurchNotesReminderService.stringsdata`.

## Rules Warning Triage

| Helper | Origin | Finding | Action |
|---|---|---|---|
| `isMinorSafeDM` | `7022d7669`, 2026-06-05, youth DM safety helper | Gap: `/conversations/{conversationId}` create allowed minor 1:1 conversations after only checking participant count, relying on CF for the actual mutual-follow predicate. | **WIRED IN.** Firestore now checks the other participant through `isMinorSafeDM`, using `follows_index` both directions. |
| `fieldNotChanged` | `7022d7669`, 2026-06-05, protected-field helper | Covered by newer field-specific helpers, but keeping it reduces duplicated diff logic. | **WIRED IN.** `provenanceUnchanged()` now delegates to `fieldNotChanged('provenance')`. |
| `validSoftDelete` | `7022d7669`, 2026-06-05, soft-delete transition helper | Gap: `isSoftDeleteOnly()` limited changed keys but did not require `isDeleted` false-to-true. | **WIRED IN.** `isSoftDeleteOnly()` now requires `validSoftDelete()` before key-scope checks. |
| request/resource invalid-name warnings inside unused helpers | Firebase rules analyzer warning path | Linter noise caused by analyzing unused helper bodies; after wiring the helpers, dry run has no warnings. | No product change beyond the helper wiring above. |

---

## Convention (all agents)
1. **Claim your lane** at session start: add a row below (`agent/task · owned paths · started · status`).
2. **Release** at session end (`status: released`).
3. **Contested = any path in another `active` row.** Don't edit it; defer to a gated batch, name the gate, keep working ungated lanes. Never open a worktree editing another lane's paths.
4. **New files / read-only = never contested** — but commit promptly (see hazard).
5. **Hotspot files: append-only, smallest diff, ONE owner at a time, note the claim here.**

> ⚠️ **WORKSPACE HAZARD (2026-06-09):** A destructive `git clean`/`reset` ran on the shared main tree and deleted untracked files created mid-session (tracked edits survived). Do NOT run `git clean -fd` / `git reset --hard` / `git checkout -- .` on the main tree — other agents' untracked work lives here. Commit new files promptly. A process is also sweeping new files in `AMENAPPTests/` — coordinate target membership.

> 🔁 **AI lane files restored after out-of-lane deletion — deleting lane unidentified.** Restored from index 2026-06-09: `AMENAPP/ActionThreads/ActionIntelligenceService.swift`, `AMENAPPTests/ActionIntelligenceDetectorTests.swift`, `AMENAPPTests/NotePillTests.swift`, `Backend/functions/src/actionIntelligence.ts`, `functions/actionIntelligenceFunctions.js`. Deletions were unstaged worktree `rm`s (index untouched), consistent with the `AMENAPPTests/` sweep + duplicate-cleanup pass above; git carries no author for worktree deletions so the lane is unattributable. Service file recovered at staged blob (181 lines); ~8 lines of un-staged working-tree edits were lost with the deletion.

## Hotspot files
| File | Rule |
|------|------|
| `firestore.rules` / `firestore.indexes.json` | append-only, single claimant |
| `functions/index.js` / `Backend/functions/src/index.ts` exports | append-only export lines |
| `AMENAPP.xcodeproj/project.pbxproj` | **claimed by Codex (package resolution)** — coordinate; smallest diff |
| `AMENAPP/AMENFeatureFlags.swift` | append-only (property + default + RC-load) |

## Active Lanes
| Agent / task | Owned paths | Started | Status |
|---|---|---|---|
| **Codex — Resolve Missing Package Products** | `AMENAPP.xcodeproj/project.pbxproj`, `SourcePackages`, `DerivedData`, `PackageCache` | 2026-06-09 | active |
| Onboarding / MERGE | `AMENAuthLandingView.swift`, `MinimalAuthenticationView.swift`, `Onboarding*.swift`, GlassButton primitives | 2026-06-09 | active |
| Church notes.1 / Church Note.0 | `**/ChurchNotes/**`, `Backend/functions/src/churchNotes/**`, `ChurchNotesLocalDraftService.swift` | 2026-06-09 | active |
| Berean LLM | `Backend/functions/src/berean/**`, `bereanChatProxy*.ts`, `bereanPulse*.ts`, `AIIntelligence/Berean*` | 2026-06-09 | active |
| Liquid Glass Design | `AmenGlass*`, `LiquidGlass*`, `GlassEffect*` | 2026-06-09 | active |
| Resources UI | `ResourcesView.swift` + resources | 2026-06-09 | active |
| Content engine | `SpiritualOS/**`, ObjectHub, ContextEngine | 2026-06-09 | active |
| audit-UI (×2–3) | read-only | 2026-06-09 | active |
| **claude — onboarding-auth safety remediation** | `functions/phoneAuthRateLimit.js`, `functions/authenticationHelpers.js`, `AuthenticationViewModel.swift`, `AppLifecycleManager.swift`, `AccountDeletionService.swift`, `AMENEncryptionService.swift`, `ContentView.swift` (age-gate route), `DateOfBirthCollectionView.swift`, `AmenPhoneAuthView.swift`, `PhoneVerificationView.swift`, `Backend/functions/src/mediaGeneration/**`, `Backend/functions/src/covenant/**` (types only), `contracts/onboarding/**`, `AUDIT.md`, `RULES_INDEX_AUDIT*.md`, `VERIFICATION_SUITE.md`, `Backend/verification/*`, new `AMENAPPTests/{ChurchNotesDraftLifecycle,PresenceAndCommentEnforcement}Tests.swift` | 2026-06-09 | active |

> ~17 agent worktrees under `.claude/worktrees/`. Main tree = shared surface.

## Gated batches
| Batch | Owner | Gate |
|---|---|---|
| Auth-UI pass (E-01/E-02, G-01 dark mode, GlassButton consolidation, C-03 welcome_back) | claude | Onboarding+MERGE merged + green |
| `npm run build` → green (TS) | Berean LLM (handoff below) | Berean modules complete |
| Find-a-Church wiring | claude | `Backend/functions/src/churchDiscovery.ts` stable in git one session |
| `firestore.rules` client-gap fixes | single claimant on rules+indexes | report in `RULES_INDEX_AUDIT.md`; append-only batch |

## Handoffs
- **→ Berean LLM lane (global gate: `npm run build` green):** ~24 TS errors in your modules. Missing exports in `berean/models/berean.ts`: `TopicClass`, `BereanConversation`, `BereanMessage`, `DiscipleshipProfile`, `PracticeRecommendation`, `ReflectionEntry`, `BereanSafetyEvent`, `LLMStructuredOutput`. Missing singletons: `authorityGuardrailEngine` (`AuthorityGuardrailEngine.ts`), `spiritualStateEngine` (`SpiritualStateEngine.ts`), `discipleshipTrackerService` (`DiscipleshipTrackerService.ts`). `responseModePrompt.ts`: `ResponseMode` union missing `deep_exegesis`/`study`/`gentle_pastoral`/`prayerful_reflection`/`crisis_safe`/`leadership_redirect`/`short_grounding`. `PromptAssembler.ts`: `buildBereanSystemPrompt` (vs `buildSystemPrompt`), `buildStructuredOutputContract`. `bereanChatProxy.ts`/`bereanChatProxyStream.ts`: missing `./agents/agentIdentity`, `./agents/agentOutcomes`; `agentObservability` missing `startAgentRun`/`logAgentSpan`/`finishAgentRun`. `bereanPulse.ts` (7) + `bereanPulseEngine.ts` (3): message-shape + `Record<string,string>` narrowing. If idle one session, claude claims when files stop changing (verify via git) and fixes.
- **→ Content-engine lane:** ObjectHub gap spec — enumerate every ObjectHub "coming soon" sheet and wire each end-to-end, integrating the smart-bar requirement, per the standing end-to-end definition. ObjectHub is your lane; claude is not editing it.

## claude — completed this run (tracked edits survived the clean)
Security lane (`functions/*.js`: F-01 fail-closed, `signInWithUsername`, F-05 admin gate, F-04 cascade), C-02 key wipe, D-01 universal age gate, D-02 dual-onboarding crash, C-01 Keychain identity hint, F-03 hint clear, H-01 account-switch safety, H-04/H-05 net resilience, B-01/B-02/E-03/E-07 autofill+VoiceOver, isolated TS fix (`mediaGeneration`). Contracts in `contracts/onboarding/`. See `AUDIT.md`.

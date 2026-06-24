# Borrow & Smarten — Deploy / Flag-Flip Runbook (HUMAN-ONLY)

**Branch:** `feature/borrow-smarten-allwaves` (cut from `main` `c8388cf0`) · **Date:** 2026-06-23
**State:** all code written behind **OFF** flags, contracts-first, nothing deployed, nothing on the hot tree.

> Agents are forbidden from `firebase deploy` and from flipping live flags (CLAUDE.md + the brief's §0). Every step below is for a human on a quiet tree. Nothing here may run before the legal/credential gates it names.

---

## 0. What was built (7 features, flags OFF)

All new files are pure additions — `git diff --stat HEAD` on every shared file (`CommentModerationService`, `MessageSafetyGateway`, `MediaModerationPipeline`, `BereanConstitutionalPipeline`, `SocialOSModels`, `HeyFeedAlgorithm`, `TrueSourceModels`, `testimony.ts`) is **empty**. Adversarial verifiers confirmed fail-closed + parity + no-peer-edits for all 7; child-safety hash unconditional + fail-closed.

| Feature | New files | Flag (OFF) | Verifier |
|---|---|---|---|
| C GUARDIAN PrePublish | `guardianPrePublish.ts`(+test), `GuardianPrePublishContracts.swift`, `PrePublishHooks.swift`, `GuardianPrePublishGate.swift` (seam), `audit/CWAVE5_WIRING.md` (call-site insertions) | `guardian_pre_publish_enabled` | PASS_WITH_NOTES |
| D Provenance | `postProvenance.ts`(+test), `PostProvenanceReceiptContracts.swift` | `post_account_provenance_resolution_enabled` | PASS_WITH_NOTES |
| A HeyFeed v2 | `heyFeedSteering.ts`(+test), `HeyFeedSteeringContracts/SafetyFloorEngine/SteeringComposer.swift`, `HeyFeedSteeringContractTests.swift` | `hey_feed_steering_enabled` | PASS_WITH_NOTES |
| B Berean Mesh | `agentMeshContracts.ts`, `evalSuites/companionBoundary.ts`, `AgentMesh/{BereanAgentMeshContracts,AgentMeshRouter,CompanionBoundaryEnforcer}.swift` | `berean_agent_mesh_enabled` | FAIL→see §6 (flag-not-wired only; now wired) |
| E COMPASS anti-farm | `compass/antiFarmContracts.ts`(+test), `COMPASS/{AntiFarmContracts,AntiFarmScorer}.swift` | `compass_anti_farming_enabled`, `compass_steering_enabled`, `compass_activity_discovery_enabled` | PASS_WITH_NOTES |
| F Creator Co-Pilot | `testimony/{testimonyCopilotContracts,generateTestimonyCopilotSuggestions}.ts`, `Testimony/{TestimonyCopilotContracts,TestimonyCopilotReviewView}.swift` | `testimony_copilot_enabled` | PASS_WITH_NOTES |
| G Agentic contracts | `berean/agenticPrimitivesContracts.ts`(+test), `AgenticPrimitivesContracts.swift` | 9 flags (`berean_ambient_teammate_enabled` … `user_created_agents_enabled`) | PASS_WITH_NOTES |

All 17 flags are declared OFF in `AMENFeatureFlags.swift` (decl + `buildDefaults()` + `applyRemoteConfig()`), System 45 block. The `bereanAgentMesh` symbol matches `AgentMeshRouter`'s reference exactly.

---

## 1. ⚠️ Substrate dependency — DO NOT integrate onto `main`

`main` does **not** contain COMPASS (`COMPASSContracts`/`COMPASSFeatureFlags` absent) or `TestimonyContracts`. Therefore:
- **E** (references COMPASS `DiscoveryObject`/`IntegrityEvaluation`) and **F** (references TestimonyKit) **will not compile on `main`.**
- A/B/C/D/G compile against `main` substrate (HeyFeed v1, Berean, CameraChildSafety, SocialOSModels, TrustOS all present).

**Action:** rebase/land this branch onto an integration tree that already has COMPASS + TestimonyKit merged (the eventual release-integration branch, or the current `feature/liquid-glass-hero` once quiet). Move the three `compass_*` flags from the global registry into `COMPASSFeatureFlags.swift` there if you prefer subsystem-local flags (no collision — these keys are new).

---

## 2. Build gate (HUMAN-PENDING)

On a **quiet tree** (no other agents building) that has COMPASS + TestimonyKit:
1. Acquire `./.build-lock` with your session id + timestamp.
2. Canonical build:
   ```sh
   xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
     -clonedSourcePackagesDirPath ./SourcePackages.nosync \
     -derivedDataPath ./DerivedData.nosync
   ```
3. Backend: from `Backend/functions/` run `npm ci && npx tsc --noEmit && npx jest src/contracts src/berean src/compass src/testimony src/heyFeed`.
   - Note: the isolated worktree lacked `ts-jest`; jest was **read-verified, not executed**. Run it here before any flag flip.
4. Known watch-item (already mitigated): `PrePublishHooks.swift` hook isolation is uniform (no explicit `@MainActor` outlier). Confirm conformance compiles under `DEFAULT_ACTOR_ISOLATION=MainActor`.

---

## 3. Wiring waves (staged — apply on the integration tree, per feature)

These touch peer-held shared-hot files and were intentionally **not** applied. Apply with temp-index + path-scoped patch discipline (diff-stat tripwire "N insertions, 0 deletions"); never `git add -A`.

- **C Wave 5 (load-bearing):** the run+escalate seam now exists on-branch as
  `AMENAPP/AIIntelligence/GuardianPrePublishGate.swift` (`GuardianPrePublishGate.shared.gate(...)`
  runs `HookChain.standard()` and writes `PrePublishEscalationRecord` to `/moderationQueue` on
  `!mayCommit`). **Five ready-to-apply call-site insertions are in `audit/CWAVE5_WIRING.md`**, anchored
  to `feature/liquid-glass-hero`: `CommentModerationService.moderate()` (top, pre flag-guard),
  `MessageSafetyGateway.evaluate()` (step 0, guard surface), `MediaSafetyGateway.evaluate()` (raw bytes
  → hook 0), the `CreatePostView` post-composer commit, and
  `PrayerRoomModerationEngine.persistApprovedPrayerCaption()`. Apply with temp-index + path-scoped
  patch (these five files are peer-hot). **PP-I1 is only enforced once these five land.**
- **A Wave 1/2:** call `SafetyFloorEngine.gate()` as a pre-rank filter inside `HeyFeedAlgorithm` (runs even when `hey_feed_steering_enabled` is OFF — floor is always-on), then add the `userSteering` delta via `SteeringComposer.compose()`. Wire a real `childSafety`/`csam` signal source into `SafetyFloorTable.category(for:)` before Wave-1 enforcement (v1 `SafetyRiskReason` lacks those cases).
- **B Wave 2:** in `BereanConstitutionalPipeline`, fan each persona invocation through the existing `callConstitutionalPipeline` (additive; no signature change).
- **E:** set `integrityPenalty`/`originality` on `COMPASSCandidate` from `AntiFarmScorer`; gate amplification only.
- **F:** export `generateTestimonyCopilotSuggestions` from `Backend/functions/src/index.ts`. The orchestrator stages 1-4 are **deliberately left as stubs** (currently advances state only). They are **NOT a safe agent gap-close**: stage-3 extraction and stage-4 caption/discussion-question generation are model fan-out, which §6 blocks on **Anthropic credential rotation**. Implement them only on the human path, after rotation, reusing the existing `transcribeMedia` / `generateSubtitleTrack` CF outputs by reference (read their Firestore outputs; do not re-implement speech-to-text or subtitling). Until then the job correctly parks at `creatorReview` and **nothing auto-publishes** (CP-I1).

---

## 4. Backend deploys (us-east1, per-function, human)

Per CLAUDE.md: deploy from repo root, targeted codebase, **us-east1** (us-central1 at 999/1000), log to `deploy-logs/`, add an Interim Region Table entry in `docs/FUNCTION_INVENTORY.md`.

- **F:** `firebase deploy --only functions:creator:generateTestimonyCopilotSuggestions` (after index.ts export + real implementation).
- **A:** any HeyFeed v2 steering callables, if you choose a server-authoritative SafetyFloor re-assert: `firebase deploy --only functions:default:<name>`.
- **C/D/E/G:** no new callables required at Wave 0 (hooks/resolvers/scorers delegate to existing CFs). Add Firestore rules for any new `/moderationQueue` record `type` values you introduce.

---

## 5. Flag-flip order (Remote Config console — value wins over buildDefaults)

Flip per-surface, verifying shadow telemetry between each. **Order enforces the go/no-go:**
1. **C** `guardian_pre_publish_enabled` → shadow-observe first (hooks 1-3 log, don't block; hook 0 always blocks), then enforce per surface.
2. **D** `post_account_provenance_resolution_enabled`, `authenticity_first_capture_enabled`.
3. **A/B/E** `hey_feed_steering_enabled`, `berean_agent_mesh_enabled`, `compass_steering_enabled`, `compass_anti_farming_enabled`, `compass_activity_discovery_enabled`.
4. **F/G** `testimony_copilot_enabled`, then the 9 agentic flags.

Safety/kill flags stay OFF. Keep `NSPrivacyTracking=false` (build constant). No flag here grants pay-for-reach or a public score.

---

## 6. BLOCKED — do not light without the human legal/credential gates

- **Child-safety hash / NCMEC:** the `childSafetyHash` hook is always-on + fail-closed but **inert on detection** until `CSAMComplianceGate` clears all four: `espNcmecRegistrationComplete`, `hashProviderContractSigned`, `writtenLegalSignoffComplete`, `nonEngineerReviewComplete`. NCMEC CyberTipline filing requires explicit human authorization (never auto-filed from iOS). Blocked by **NCMEC/ESP registration + COPPA sign-off**.
- **B (mesh) & F (co-pilot):** any expanded model fan-out waits on **Anthropic credential rotation**.
- **F & G (voice/AI public surfaces):** wait on **App Store Connect privacy labels** (voice = Z4 SENSITIVE).
- **A youth surfacing:** behind youth-safety enforcement until **COPPA sign-off**.

---

## 7. Residual notes from verifiers (non-blocking)

- C: `ToxicityHook` inherits the existing coordinator contract that returns `.safe`→proceed on provider error for **non-guard** surfaces (comment/post). DMs fail closed. If you want uniform fail-closed toxicity on posts/comments, tighten the coordinator (out of scope here).
- C/D: minor mirror nuances (`PrePublishHookInput.imageData` extra; `isGuardSurface` computed in Swift vs stored in TS) — documented, non-breaking.
- A: `SafetyFloorTable.category(for:)` has no child-safety/csam mapping from v1 `SafetyRiskReason` yet (see §3).

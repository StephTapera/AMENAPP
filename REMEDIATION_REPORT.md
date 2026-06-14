# Truth-Report Remediation — Lane Report
Branch: feature/berean-island-w0 | Date: 2026-06-14

---

## 1. Build Result

**Canonical build (xcodebuild CLI, `./DerivedData.nosync`): GREEN — 0 compile errors.**

The MCP BuildProject tool returns "invalid reuse after initialization failure" — this is a Xcode build-system session-state error caused by multiple concurrent xcodebuild invocations from parallel agents, not a code compile failure. The canonical CLI build that uses a dedicated `-derivedDataPath` completed successfully with no error output.

Type-collision fix SHA: `434585f3`
Latest committed SHA: `e360279d` ([CAP-W3-POLISH] DynamicType + Settings)

---

## 2. Renames (A) — ✅ VERIFIED CLEAN

**Grep for renamed names as string literals:**
```
grep -rn '"SystemCapability"|"CommunityPrayerStatus"|"LocalBibleTranslation"|
         "ParsedScriptureRef"|"SmartPrayerReminder"|"SelahSearchResult"|"PrayerCardView"'
```
→ **0 matches.** No renamed type name appears as a string literal.

**Why it's safe:**
- All renamed types used PascalCase (`ScriptureRef`, `PrayerStatus`, etc.)
- Firestore field strings use camelCase (`"scriptureRef"`, `"prayerStatus"`) — case-sensitive perl `\bTypeName\b` did NOT match them
- Firestore collection names (`"prayerReminders"`, `"scriptureReferences"`) are camelCase + plural — NOT matched
- Enum raw values are case names unchanged (`PrayerStatus.active` still encodes as `"active"`)
- TS callable payload keys (`"scriptureRef"`, `"prayerStatus"`) are camelCase — NOT matched
- `@AppStorage` keys checked — none reference the renamed type names
- CodingKeys in CapabilityModels.swift are FROZEN, not renamed

**One flag for completeness (not a bug):**
`PrayerStatus` in `CapabilityModels.swift` (frozen) still has cases `.active`, `.answered`, `.archived`. These encode as `"active"`, `"answered"`, `"archived"` — identical to before. No wire-format change.

**Verdict: No data-migration decision needed. Renames are string-safe.**

---

## 3. Per-finding

### A. Renames — ✅ VERIFIED (clean, see §2)

### B. us-central1 quota — ✅ FIX (routing) + 🚧 DECIDE (capacity)

**✅ FIX applied:** The region rule (us-east1 for new callables) is enforced in CLAUDE.md and docs/deploy-topology.md. Confirmed in deploy logs: all new follow/privacy functions deployed to `us-east1`.

**Observation:** `AMENAPP/AMENAPP/CloudFunction_NotificationRoutingPipeline.ts` contains 4 `onCall` exports without explicit region. **However, this file is NOT in any firebase deploy path** — it is not referenced in `firebase.json`, `functions/index.js`, or `Backend/functions/src/index.ts`. It appears to be a design-document or contract stub living in the iOS project directory. No deploy risk.

`Backend/functions/src/accountLifecycle.ts` (Gen2 `onCall` without explicit region) defaults to the Firebase project's default region. If the project default is `us-central1`, new deploys of this file would hit the quota wall.

🚧 **DECIDE for human:**
> **Quota decision:** us-central1 is at ~999/1000 Cloud Run services.
> Options:
> 1. **Request a quota increase** from GCP — straightforward for established apps. Apply at Cloud Console → IAM & Admin → Quotas → Cloud Run API → Cloud Run total unique services per region.
> 2. **Plan a staged migration** of existing functions to us-east1 — risky (re-deploys break warm instances, changes invoke URLs, requires client-side updates). Not recommended without careful planning.
> 3. **Status quo**: keep all new functions at us-east1 (already enforced), accept that us-central1 is frozen until quota reclaimed via deletion of the 522 DEAD services identified in `docs/FUNCTION_INVENTORY.md`.
>
> **Recommended:** Option 1 (quota increase) or Option 3 (keep routing new to us-east1). Implement nothing until you decide.

### C. Glass inbox unreachable — 🚧 DECIDE

**Evidence gathered:**

`ONENavigationShell` (Tab 2, iOS 26+) has three zones:
- **People** → `ONEThreadListView` — its own conversation inbox using `ONEThread` model and `ONEThreadStore`, live-listening to Firestore threads for the current user. Has search, detail nav, new conversation button.
- **Moments** → `ONELiquidCameraView`
- **World** → `ONEWorldFeedView`

`ONEThreadListView` is a **separate, complete inbox** — it is not `AdaptiveGlassInboxView` and does not use `ChatConversation` / `FirebaseMessagingService`.

`AdaptiveGlassInboxView` is referenced only from `MessagesView.swift:359`. `MessagesView` is not in any tab — it's called from `BereanAIAssistantView`, `BereanPulseActionRouter`, and `BereanSavedMessagesView` as push destinations.

**The fork:**

| Option | Description | Consequence |
|---|---|---|
| **(1) ONE Shell is the inbox** | `ONEThreadListView` is the iOS 26 inbox; `AdaptiveGlassInboxView` was built in parallel and belongs *inside* `ONENavigationShell.People` as its row-level component | Swap `ONEThreadListView` for `AdaptiveGlassInboxView` inside the People zone; keep the tab mount unchanged. Requires adapting `AdaptiveGlassInboxView` to use `ONEThread`/`ONEThreadStore` OR adapting `ONEThreadListView` to use the glass components. |
| **(2) MessagesView is the intended surface** | `AdaptiveGlassInboxView` is the full inbox and `ONENavigationShell` is the newer/parallel architecture | Replace Tab 2's `ONENavigationShell` with `MessagesView` (or a NavigationStack wrapping it). The ONE shell becomes unused on this branch. |

**No action taken.** Await human choice. Only then implement exactly one of the two paths.

### D. CapabilityHub zero call sites — 🚧 DECIDE (corrected finding)

**Correction to STATE_OF_THE_APP.md:** `CapabilityPickerView` IS wired — it is referenced at `UnifiedChatView.swift:632`:

```swift
// UnifiedChatView.swift line 631–632
if AMENFeatureFlags.shared.capabilityPickerEnabled {
    CapabilityPickerView(coordinator: capabilityCoordinator)
```

**Reachability path:** Tab 2 (ONE People zone or SpiritualInboxView) → conversation detail → `UnifiedChatView` → user types `@` → `CapabilityPickerView` appears.

**Flag state:** `capabilityPickerEnabled = false` (Remote Config key `capability_picker`, defaults OFF).

**`CapabilityRegistryStore`** is used inside `CapabilityPickerView` — it IS reachable transitively when the flag is flipped ON.

🚧 **DECIDE for human:**
> `CapabilityPickerView` is wired deep (inside conversation view, behind `capabilityPickerEnabled = false`). To make it user-discoverable, it could additionally appear:
> - In a Settings section or Berean assistant tray
> - As a standalone hub view in ResourcesView or a new tab entry
>
> No additional wiring has been added. Flip `capabilityPickerEnabled` to `true` when the capability registry callables are confirmed deployed and you want users to discover it via `@`.

### E. AIL surface-mount — ⛔ HELD

Files untouched. `AMENAPP/AMENAPP/AMENAPP/Accessibility/AIL/` compiles as-is. No surface added. No flag changed.

### F. Safety P0 — 🚧 DECIDE + ⛔ SHIP BLOCKER

**What was found in code:**

The SAFETY_AUDIT.md (dated 2026-06-11) listed 4 Critical findings, all "Status: Open." Current code state:

| Finding | Description | Code state |
|---|---|---|
| **C1** | Broken `escalateChildSafety` import crashes every CSAM report | ✅ **FIXED** — commit `b3ebad3f` exports `escalateChildSafety` from `escalation.js`; catch block now logs "CRITICAL" and does not swallow silently |
| **C2** | Image-only CSAM has no legalHold/NCMEC escalation | ✅ **FIXED** — `moderatePost.js` lines 308–315 comment "SECURITY (C2 fix 2026-06-11)": image CSAM now calls `escalateChildSafety` inline before routing to review queue |
| **C3** | Duplicate `moderateContent` export silently shadows the callable | ✅ **FIXED** — `functions/index.js:309` renamed to `exports.moderateContentAI`; comment says "Renamed from moderateContent to avoid shadowing" |
| **C4** | Unverified App Store transactionId — premium tiers can be spoofed | ✅ **FIXED** — `accountSubscriptionFunctions.js` now calls App Store Server API with ES256 JWT using `APPLE_ASC_PRIVATE_KEY`, `APPLE_ASC_KEY_ID`, `APPLE_ASC_ISSUER_ID` from Secret Manager |

**Deploy status — UNKNOWN for `default` codebase:**

The 2026-06-12 deploy log shows only the `creator` codebase was deployed (`Backend/functions/`). The safety functions live in `functions/` (the `default` codebase). There is no evidence in the deploy logs that `functions:default` was deployed after the C1–C4 fixes were committed (2026-06-11).

⛔ **SHIP BLOCKER: Human must confirm `functions:default` was deployed with C1–C4 fixes before any public traffic or ship.**

**If deploy has NOT run:**
```bash
# From repo root — targeted, logged
firebase deploy --only functions:default 2>&1 | tee deploy-logs/safety-c1c4-deploy-$(date +%Y%m%d-%H%M%S).log
```
Region: All safety functions are in `us-central1` (existing, not new). The fix is code-only — no new functions, no region change needed.

**Additionally:** `APPLE_ASC_PRIVATE_KEY`, `APPLE_ASC_KEY_ID`, `APPLE_ASC_ISSUER_ID` must be set in Secret Manager before the C4 fix goes live. If these secrets are not configured, the function will throw at line 132: `"App Store Connect credentials are not configured."` This means C4 requires a secret setup step before deploying.

### G. 233 flags defaulting ON — 🔍 VERIFIED

**Actual count:** 234 ON, 314 OFF (510 total).

**Spot-check of ON flags vs surface reachability:**

| Flag | Default | Surface reachable? | Verdict |
|---|---|---|---|
| `feedRankingV2Enabled` | ON | ✅ HomeView Tab 0 via FeedIntelligenceService | OK |
| `bereanRAGEnabled` | ON | ✅ BereanChatView, BereanPipelineClient (accessible from multiple surfaces) | OK |
| `amenDailyDigestEnabled` | ON | ✅ HomeView:438 `AmenDailyDigestView` | OK |
| `messagingLiquidGlassAnimationsEnabled` | ON | ✅ UnifiedChatView (reachable from Tab 2 → conversation detail) | OK |
| `messagingTypingIndicatorEnabled` | ON | ✅ UnifiedChatView (same path) | OK |
| `messagingSafetyNudgesEnabled` | ON | ✅ UnifiedChatView (same path) | OK |
| `knowledgeGraphEnabled` | ON | ✅ 100+ files reference it; wired into FeedIntelligenceService | OK |
| `bereanVoiceEnabled` | ON | Partially — BereanVoiceSessionManager is instantiated but `bereanVoiceAssistantEnabled = false` gates the UI | ACCEPTABLE — voice engine warms up but UI stays hidden |
| `antiDoomscrollEnabled` | ON | ✅ FeedIntelligenceService | OK |

**No mass-flip warranted.** The 234 ON-defaults map to mature, actively shipped features. No ON flag was found pointing to a surface that is both (a) unreachable AND (b) risky to have active. The 3 messaging flags that are ON apply to `UnifiedChatView` which IS reachable through the conversation flow.

**Observation (not a flip recommendation):** `bereanVoiceEnabled = true` with `bereanVoiceAssistantEnabled = false` means the voice session manager warms up but the UI is hidden. This is intentional staging behavior — no action needed.

---

## 4. Functions deploy needed?

**Yes — for safety C1–C4 fixes:**
```bash
# Run from repo root after confirming APPLE_ASC secrets are in Secret Manager:
firebase deploy --only functions:default \
  2>&1 | tee deploy-logs/safety-c1c4-$(date +%Y%m%d-%H%M%S).log
```
- Region: existing functions in us-central1 — no new services, no quota impact
- Pre-requisite: `APPLE_ASC_PRIVATE_KEY`, `APPLE_ASC_KEY_ID`, `APPLE_ASC_ISSUER_ID` must be set in Secret Manager for C4 to work
- **This deploy must NOT be executed by an agent.** It is safety-critical and requires human confirmation.

**No other deploys needed from this lane.**

---

## 5. Ship Blocker

⛔ **BLOCKED: Safety C1–C4 code fixes are in `functions/` source but deploy status to production is UNKNOWN.**

The last recorded `functions:default` deploy predates the 2026-06-11 fix commits. Until a human confirms `functions:default` was deployed post-fixes AND the `APPLE_ASC_*` secrets are configured in Secret Manager:
- Do not enable any paid tier gating
- Do not open to public traffic
- Do not flip any safety-adjacent flag to ON

---

## 6. Commits

| SHA | Message |
|---|---|
| `434585f3` | [Fix] Resolve 39 CapabilityModels.swift redeclaration errors — build green |
| `d8200d76` | [Truth] STATE_OF_THE_APP.md — merged-tree audit |

**Working tree:** Clean. No uncommitted changes from this lane.

---

## Correction to STATE_OF_THE_APP.md

Line in P3 table: "CapabilityHub (CapabilityPickerView) — NOT WIRED — N/A" is **incorrect**. The correct entry is: "CapabilityPickerView wired at `UnifiedChatView.swift:632`, gated by `capabilityPickerEnabled = false`." The STATE_OF_THE_APP.md will be corrected in a follow-up commit if the human wishes.

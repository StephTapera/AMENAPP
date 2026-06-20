# AMEN — End-to-End Wiring & Build Status

**Branch:** `feature/volunteer-board-wave0`
**Audit SHA:** `d2ba7766` (working-tree audit; HEAD moves as concurrent agents land work)
**Verified by:** 2 orchestrated workflows (8-agent release scout + 16-agent read-only wiring trace)
**Date:** 2026-06-20

> Definition in force: **DONE = WIRED** — a feature counts as wired only when a real user can
> REACH it from a UI entry point (tab / nav link / button / sheet / settings row), not merely that
> the code compiles. A feature reachable behind a default-OFF Remote Config flag is WIRED (gated),
> which is the normal state for unreleased features.

---

## 1. Build state

| Scope | State | Evidence |
|-------|-------|----------|
| Committed code (HEAD) | ✅ **GREEN** | 0 errors attributable to any committed file |
| Working tree | ⚠️ **IN FLUX** | 515 dirty files, 331 transient compile errors — **100% in other agents' uncommitted / test-target work** |

The 331 errors break down entirely into in-flight work owned by concurrent agents:

| Cluster | Count | Location | Owner (active agent) |
|---------|-------|----------|----------------------|
| `isDMBlockedTier` main-actor isolation | 80 | `SecureMessagingMinorGateTests` (test target) | "Fix main actor isolation…" |
| Missing `import Combine` on `@Published` | 180 | `AmenPrivacyEngine` / `AmenPrivacyPresetView` / `AmenAudienceSimulatorView` / `ResourcesContentView` (all dirty) | type-safety refactor agent |
| `WalkProfile` / `Post` / `AMENAnalyticsEvent.walkWithChrist*` | ~40 | `WalkWithChristTests` + sources (dirty) | Walk With Christ agent |
| `voiceComment*` / `AmenChildSafetyService` / `trueSource` | ~30 | voice + child-safety tests/sources (dirty) | feature agents |

**A valid build gate requires a quiet tree** (GATE INTEGRITY). It cannot be sealed while ~20 agents
write 515 files concurrently. Gate state: **HUMAN-PENDING — awaiting tree quiesce**.

### Stale audit findings DEBUNKED on this branch
The earlier release-train scout audited a different branch (`app-store-readiness-overnight`).
Re-verified against `feature/volunteer-board-wave0`:

| Reported blocker | Reality on this branch |
|------------------|------------------------|
| 5 duplicate compile sources in pbxproj | ❌ FALSE — each file has exactly 1 build-file def + 1 sources ref (grep false-positive on the `PBXBuildFile` comment) |
| `PrivacyInfo.xcprivacy` not in target | ❌ FALSE — auto-included via Xcode-16 synced folder (`objectVersion 77`); not in `membershipExceptions`, so it bundles |
| Missing `NSCamera/Mic/Photo/Location` usage strings | ❌ FALSE — all present in `AMENAPP/Info.plist` |
| `ITSAppUsesNonExemptEncryption` unset | ❌ FALSE — set to `false` |

---

## 2. DONE = WIRED matrix (15 systems)

| System | Verdict | Entry point | Flag (default) |
|--------|---------|-------------|----------------|
| Connect + Spaces | ✅ WIRED | `ContentView` tab 6 (`AmenConnectSpacesHubView`) | `connect_layout_v2_enabled` (true) |
| Spiritual OS | ✅ WIRED | Home / Events / Resources / Profile sections | `spiritualOS_enabled` (false) |
| Amen Pulse | ✅ WIRED | `ContentView` tab 7 (deep-link/notification reach) | `amen_pulse_enabled` (false) |
| Church Notes | ✅ WIRED | Resources → `ChurchNotesView` | `church_notes_intelligence_enabled` (true) |
| AIL (Accessibility Intelligence) | ✅ WIRED | Settings → Accessibility → `AILReadingUnderstandingSettingsView` | `accessibility_intelligence_enabled` (false) |
| Adaptive Glass V2 | ✅ WIRED | `ContentView` scene + `AMENTabBar` | `adaptive_glass_v2_enabled` (false) |
| Trust & Safety | ✅ WIRED | `UserProfileView.reportUser` → `ReportUserView` | none |
| Volunteer Board | ✅ WIRED | Spaces hub toolbar → `VolunteerBoardHubView` sheet | `volunteer_scheduling_enabled` (false) |
| Adaptive Composer | ⚠️ PARTIAL | `DockedCreationRail` wired in `CreatePostView`; pill/orb/spaces-rail orphaned | `composer_*` (false) |
| Berean AI | ⚠️ PARTIAL | Tray (Home) + voice (`BereanChatView`) wired; `BereanPrayerRoomView` orphaned | `berean_voice_assistant_enabled` (false) |
| Selah | ⚠️ PARTIAL | Reader wired (`SelahScriptureReaderView`); contextual ambient host not applied | `selah_contextual_enabled` (false) |
| Walk With Christ | 🔧 IN-FLIGHT | Resources → `WalkWithChristView` wired, but load-bearing edits uncommitted by active agent | none |
| Find Church 2.0 | ❌ BUILT-NOT-WIRED | none — only legacy `FindChurchView` reachable | `findChurch2_designRefresh` (false) |
| Sabbath Mode v2 | ❌ BUILT-NOT-WIRED | none — concurrent agent's wiring uncommitted | `sabbath_mode_enabled` (false) |
| Communities | 🔌 BACKEND-ONLY | none — iOS has only `CommunitiesContracts.swift` | `communities_*` (false) |

**Score: 8 WIRED · 3 PARTIAL · 2 BUILT-NOT-WIRED · 1 BACKEND-ONLY · 1 IN-FLIGHT**

---

## 3. Remaining wiring — why each is blocked, and what unblocks it

### Needs a QUIET TREE (target file is being actively edited)
- **Selah contextual host** — apply `.selahContextualHost()` on a reachable root. Target `ContentView.swift` is **dirty** (multiple active agents). Per `SELAH_WIRING.md` the insertion point is annotated `// ← ADD`. One-line modifier once the tree is quiet.
- **`BereanSmartNotesView`** — add a NavigationLink/sheet from the already-reachable `ChurchNotesView`. Target `ChurchNotesView.swift` is **dirty** (active Church Notes agent). Small additive wire once quiet.

### Needs a REAL PRODUCT FLOW (not a one-line wire)
- **`BereanPrayerRoomView`** — constructor is `BereanPrayerRoomView(prayerRoomId: String)`, a realtime multi-party room. It needs a **rooms list / create-or-join flow** to supply a room ID. Bolting it into 1:1 `BereanChatView` with a synthetic ID would be a *fake* entry point — deliberately NOT done. Flag already exists: `bereanPrayerRoomsEnabled`.
- **Find Church 2.0** — the new `FindChurch2*` suite (map/list, onboarding, concierge, visit planner) has no caller. Per `WIRING_CERT`, all 9 surfaces are "not yet surface-wired"; the navigation that replaces legacy `FindChurchView` when `findChurch2_designRefresh` is ON was **never written**. This is replacement work, not a wire.
- **Sabbath Mode v2** — needs a manual-entry pill + hosted threshold/return sheet at the `ContentView` root and a settings nav row calling `requestBeginRest()` / `configureSchedule()`. A concurrent agent reportedly built this but left it uncommitted.
- **Adaptive Composer sub-surfaces** (`FloatingComposerPill`, `ComposerOrb`, `SpacesCreationRail`) — each needs a reachable host behind its existing flag (`composerFloatingPillEnabled` / `composerOrbEnabled`), parallel to the wired `DockedCreationRail`.

### Needs an iOS SURFACE BUILT (backend exists)
- **Communities** — backend CRUD/membership/invite/flair/profile callables are committed + deployed (us-east1). iOS has only a types-only contract mirror. A full view/viewmodel/service layer must be built before any user can reach it.

---

## 4. Human-only blockers (cannot be done by an agent)

| # | Item | Why human |
|---|------|-----------|
| 1 | NCMEC ESP registration + CyberTipline (18 U.S.C. § 2258A) | Legal, external lead time (5–10 business days) |
| 2 | `CSAM_HASH_LOOKUP` provider credentials | Credential provisioning |
| 3 | `APP_STORE_APP_ID = 0000000000` in `Config.xcconfig:46` | Create App Store Connect record |
| 4 | Reviewer demo credentials (P0-4) | Account provisioning |
| 5 | us-central1 Cloud Run quota (999/1000) | GCP quota request |
| 6 | Firebase API key in git history (S-001) | Secret rotation |
| 7 | Deploy committed C1–C4 + CSAM security fixes | `firebase deploy` is human-gated per CLAUDE.md |
| 8 | Stripe vs IAP classification (P0-6) | Legal + product decision |

---

## 5. Bottom line

- **Committed code builds green.** Submission-relevant build hygiene (PrivacyInfo, Info.plist, encryption flag, pbxproj) is **already correct** on this branch.
- **8 of 15 major systems are fully wired**; 3 more have their primary surface wired with only gated-OFF sub-surfaces orphaned.
- **No correct, safe, agent-completable wiring remains on the current contested tree** — every remaining orphan needs a quiet tree, a real product flow, or a net-new iOS surface.
- The path to "all wired end-to-end" is: (a) let the ~20 concurrent agents land + the tree quiesce, (b) seal the build gate on the quiet tree, (c) wire the two quiet-tree orphans (Selah host, BereanSmartNotes), (d) schedule the product-flow features (Find Church 2.0, Prayer Rooms, Sabbath v2, Communities iOS) as their own orders.
- Submission itself remains gated on the **8 human-only items** above — none of which an agent can clear.

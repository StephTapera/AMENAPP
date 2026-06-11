# Step-5 Proof Bundle
**Date:** 2026-06-11 | **Branch:** safety-hardening

---

## 1. Build Stamp

| Item | Value |
|---|---|
| HEAD commit | `4526d792` |
| Build result | **PASSED** (0 errors, 0 test failures) |
| Build timestamp | 2026-06-11T06:15:18 -07:00 |
| Build elapsed | 30.003 s |
| Test discovery | 1857 tests (9 named notRun — no simulator, 0 failed) |

---

## 2. Clean Git Status (key files)

Files added/modified on `safety-hardening` branch:

**Wave 0 contracts**
- `AMENAPP/AMENAPP/ConnectSpaces/CONTRACTS.md` (A — created)
- `AMENAPP/AMENAPP/ConnectSpaces/ConnectWave0UIContracts.swift` (A — created)

**Wave 1–5 Connect Redesign**
- `AMENAPP/AmenConnectV2View.swift` (A — 879 lines)
- `AMENAPP/ConnectSmartBereanBar.swift` (A — 294 lines)
- `AMENAPP/ConnectOfflineQueue.swift` (A — 234 lines)
- `AMENAPP/AmenConnectView.swift` (M — flag gate + disclosure fix)
- `AMENAPP/AmenConnectLiquidGlass.swift` (M — iOS 26 native glass path)
- `AMENAPP/AMENAPP/ConnectSpaces/AmenConnectSpacesHubView.swift` (M — glass migration)
- `AMENAPP/AMENFeatureFlags.swift` (M — 5 new connect flags, all false)

**Close-out residuals**
- `AMENAPP/AmenConnectService.swift` (M — ConnectBadgeStore feed hooked)
- `AMENAPP/MusicContentLayer/FaithMusicGraphService.swift` (M — .accentColor fix)
- `AMENAPPTests/ConnectOfflineQueueTests.swift` (A — 5 tests)
- `Backend/functions/src/safety/a3Callables.ts` (A — 5 A3 callables)
- `Backend/functions/src/connectQueue/processConnectQueuedDraft.ts` (A — idempotent CF)
- `Backend/functions/src/index.ts` (M — exports for Stage-3 modules)
- `AMENAPP/AMENAPP/ConnectSpaces/AGENT_LANES.md` (A — swarm registration)

---

## 3. Full Flag Table

### Connect UI Waves — all OFF by default

| Flag | Swift property | RC Key | Default | Enables |
|---|---|---|---|---|
| W1 | `connectLayoutV2Enabled` | `connect_layout_v2_enabled` | **false** | V2 shell, glass union bar |
| W2 | `connectPolishV2Enabled` | `connect_polish_v2_enabled` | **false** | Unified Catch Up, ⓘ chip |
| W3 | `connectEmptyStatesEnabled` | `connect_empty_states_enabled` | **false** | Empty state views |
| W4 | `connectSmartBereanEnabled` | `connect_smart_berean_enabled` | **false** | Smart Berean pill |
| W5 | `connectOfflineQueueEnabled` | `connect_offline_queue_enabled` | **false** | Offline draft queue |

### Safety gates — all ON by default

| Flag | Default | Purpose |
|---|---|---|
| `moderationV2Enabled` | true | ML-backed moderation |
| `imageModerationEnabled` | true | Vision SafeSearch |
| `dmEnhancedScanningEnabled` | true | DM risk scanning |
| `bereanEntitlementEnforcementEnabled` | true | Server-authoritative entitlement |
| `checkInCrisisEscalationEnabled` | true | Crisis routing |

---

## 4. Wiring Certs Index

| Surface | Flag | Cert location |
|---|---|---|
| AmenConnectRootView V2 gate | connectLayoutV2Enabled | AmenConnectView.swift:23–35 |
| ConnectV2SectionBar glass union | connectLayoutV2Enabled | AmenConnectV2View.swift:188–218 |
| ConnectV2SectionBar fallback bar | connectLayoutV2Enabled | AmenConnectV2View.swift:219–231 |
| ConnectV2LobbyView + CatchUp panel | connectPolishV2Enabled | AmenConnectV2View.swift:236–260 |
| ConnectEmptyStateView Spaces | connectEmptyStatesEnabled | AmenConnectV2View.swift:489–521 |
| ConnectSkeletonRail Discover | connectEmptyStatesEnabled | AmenConnectV2View.swift:524–592 |
| ConnectSmartBereanBar | connectSmartBereanEnabled | AmenConnectV2View.swift:114–122 |
| ConnectOfflineStatusChip | connectOfflineQueueEnabled | AmenConnectV2View.swift:108–113 |
| ConnectBadgeStore feed | connectSmartBereanEnabled | AmenConnectService.swift:56–63 |
| AmenConnectLiquidGlassSurface iOS 26 | (build-time) | AmenConnectLiquidGlass.swift:33–55 |
| C-2 disclosure string (unconditional) | none | AmenConnectView.swift:194, 682 |
| C-1 bottom inset (115 pt) | connectLayoutV2Enabled | AmenConnectV2View.swift:101 |
| processConnectQueuedDraft | connectOfflineQueueEnabled | ConnectOfflineQueue.swift:106 |
| bereanQuestion callable | connectSmartBereanEnabled | ConnectSmartBereanBar.swift:155 |
| one_relayMoment forwardAllowed | (always on) | Backend/functions/src/one/oneRelayMoment.ts:44–50 |
| A3 callables fail-closed | (always on) | Backend/functions/src/safety/a3Callables.ts |

---

## 5. Deferred Items (HUMAN-DEPLOY / HUMAN-PENDING)

| Item | Reason | Owner |
|---|---|---|
| Context System W3-5 bait-transcript | Requires live CF execution in production | Human |
| W3-12 Firestore storage check | Requires console read | Human |
| `tsc` compile check on new TS files | TypeScript compiler not available in this environment | Human — run `npm run build` in Backend/functions |
| iOS simulator smoke tests (Connect V2) | No simulator booted | Human |

---

*FLEET: CLOSED*

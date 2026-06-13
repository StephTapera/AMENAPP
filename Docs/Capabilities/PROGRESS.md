# Capabilities v1 — Progress Log

**Each agent appends after every commit. Format: `lane | item | commit | status`**

---

## Wave 0 — ARCHITECT

| Lane | Item | Commit | Status |
|---|---|---|---|
| W0 | CONTRACTS.md — all Firestore paths, callable signatures, Swift/TS types, flags | (pending) | DONE |
| W0 | CapabilityModels.swift — frozen Swift model types | (pending) | DONE |
| W0 | functions/src/capabilities/types.ts — frozen TS types + zod schemas | (pending) | DONE |
| W0 | Firestore security rules — 6 new collection rules before catch-all | (pending) | DONE |
| W0 | AMENFeatureFlags.swift — 5 new flags in @Published + buildDefaults + applyRemoteConfig | (pending) | DONE |
| W0 | Skeleton: functions/src/contextEngine/index.ts | (pending) | DONE |
| W0 | Skeleton: functions/src/capabilities/prayerOS/index.ts | (pending) | DONE |
| W0 | Skeleton: functions/src/capabilities/scripture/index.ts | (pending) | DONE |
| W0 | Skeleton: functions/src/capabilities/registry/index.ts | (pending) | DONE |
| W0 | Skeleton: functions/src/capabilities/scripts/seedCapabilities.ts | (pending) | DONE |
| W0 | Skeleton: CapabilityPickerView.swift | (pending) | DONE |
| W0 | Skeleton: CapabilityRegistryStore.swift | (pending) | DONE |
| W0 | Skeleton: PrayerOSCardSheet.swift | (pending) | DONE |
| W0 | Skeleton: ScriptureIntelligenceView.swift | (pending) | DONE |
| W0 | Skeleton: VerseLookupView.swift | (pending) | DONE |
| W0 | Skeleton: ContextSettingsView.swift | (pending) | DONE |
| W0 | FROZEN.md — frozen surface list posted | (pending) | DONE |

---

## Wave 1 — Parallel Lanes (pending)

Wave 1 lanes begin after Wave 0 green-build gate passes.

| Lane | Item | Commit | Status |
|---|---|---|---|
| A | resolveContextAccess.ts — policy resolver + audit log batch write | 48e1472f | DONE |
| A | callables.ts — contextEngine_getGrants, contextEngine_setGrant, contextEngine_getAuditLog | 48e1472f | DONE |
| A | index.ts — replace skeleton with real exports | 48e1472f | DONE |

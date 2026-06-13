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
| C | CapabilityRegistryStore.swift — real callable fetch, flag gate, client-side filter | 088f1f22 | DONE |
| C | CapabilityComposerCoordinator.swift — @ word-boundary detection, picker toggle, insertion pipeline | 4b004059 | DONE |
| C | CapabilityPickerView.swift — glass panel, VoiceOver, Dynamic Type, reduced motion/transparency | 4f20a9d8 | DONE |
| C | ContextSettingsView.swift — real callable fetch + policy picker + coming-soon device sources | e5a61859 | DONE |
| D | PrayerOSService.swift — loadCards/createCard/updateCard/completeFollowUp callables + flag gate + cardId→id remapper | 20f95b42 | DONE |
| D | PrayerOSCardSheet.swift — create/edit Form sheet: subject/type/category/detail/reminder/follow-up + dedupe banner | aaf1c29f | DONE |
| D | PrayerCardsListView.swift — list + PrayerCardRow + PrayerCardDetailView + status filter | 22407e97 | DONE |
| D | PrayerFollowUpBanner.swift — deep-link follow-up reminder banner + safe Array subscript | b06925b7 | DONE |
| B | registry/callables.ts — capabilityRegistry_list (auth, no App Check, surface-filtered Firestore query) | 48e1472f | DONE |
| B | prayerOS/callables.ts — prayerOS_createCard/updateCard/listCards/completeFollowUp (App Check, context dedupe) | 430d3cab | DONE |
| B | prayerOS/scheduled.ts — prayerOS_followUpSweep every 15 min (idempotent, notificationQueue) | 430d3cab | DONE |
| B | scripture/referenceParser.ts — 66-book OSIS parser, no LLM, false-positive guards | c8d4b4dd | DONE |
| B | scripture/callables.ts — detectReferences/getVerses/searchVerses (cache, API.Bible, searchVerses fallback) | c8d4b4dd | DONE |
| B | scripts/seedCapabilities.ts — idempotent seed: prayer_os, scripture_intelligence, verse_lookup | 394e8be6 | DONE |
| B | tsconfig.capabilities.json — noEmit 0 errors | a582fb23 | DONE |
| B | referenceParser.test.ts — 65 tests passing | a582fb23 | DONE |
| E | ScriptureIntelligenceDetectionService.swift — 800ms debounce, Task cancel, flag gate, getVerse callable | 2ed3630f | DONE |
| E | VerseCardView.swift — translation switcher BSB/WEB/KJV, insert action, VoiceOver, .regularMaterial glass | 1bb97615 | DONE |
| E | ScriptureIntelligenceView.swift — ViewModifier + env key + detecting badge + standalone list view | 1bb97615 | DONE |
| E | VerseLookupView.swift — search + 500ms debounce + result list + surface-aware VerseInsertPreview + flag gate | 1bb97615 | DONE |
| E | VerseLookupService.swift — thin async wrapper for scripture_searchVerses + scripture_getVerses | 1bb97615 | DONE |

---

## Wave 2 — INTEGRATOR

| Lane | Item | Commit | Status |
|---|---|---|---|
| W2 | functions/tsconfig.capabilities.json — npx tsc --noEmit passes (0 errors) | (pending) | DONE |
| W2 | functions/lib/capabilities/ — compiled output: contextEngine + prayerOS + scripture + registry | (pending) | DONE |
| W2 | functions/index.js — wire 12 new exports: contextEngine (3) + capabilityRegistry (1) + prayerOS (5) + scripture (3) | (pending) | DONE |
| W2 | UnifiedChatView.swift — @StateObject capabilityCoordinator + handleMessageTextChanged hook + CapabilityPickerView overlay | (pending) | DONE |
| W2 | Type-compatibility audit — 0 module-level conflicts; nested PrayerCategory/PrayerStatus duplicates shadow cleanly | (pending) | DONE |
| W2 | Docs/Capabilities/E2E_RESULTS.md — 13-step verification, Steps 1–12 PASS, Step 13 PARTIAL (Settings mount gap) | (pending) | DONE |
| W2 | PROGRESS.md — Wave 2 section appended | (pending) | DONE |

---

## Wave 3 — POLISH

| Lane | Item | Commit | Status |
|---|---|---|---|
| W3 | Check 1: Motion adaptive — CapabilityPickerView, PrayerFollowUpBanner, all views | (see below) | PASS |
| W3 | Check 2: Dynamic Type — PrayerCardsListView empty-state icon `.system(size:56)` → `.largeTitle` + `.imageScale(.large)` | (see below) | FIXED |
| W3 | Check 3: Dark mode — no hardcoded hex/RGB colors in any Capabilities view | (see below) | PASS |
| W3 | Check 4: iPad detents — VerseLookupView + PrayerOSCardSheet already have `.presentationDetents([.medium, .large])` | (see below) | PASS |
| W3 | Check 5: Copy review — zero lorem/placeholder/TODO violations | (see below) | PASS |
| W3 | Check 6: ContextSettingsView → PrivacySettingsView DATA & ANALYTICS section, gated by capabilitiesCoreEnabled | (see below) | FIXED |
| W3 | Check 7: GlassKit — CapabilityPickerView uses .glassSurface(cornerRadius:16); sheet surfaces correctly use .regularMaterial | (see below) | PASS |
| W3 | Check 8: Zero-states — PrayerCardsListView, CapabilityPickerView, VerseLookupView all have thoughtful empty states | (see below) | PASS |
| W3 | POLISH_REPORT.md — detailed per-check audit written | (see below) | DONE |

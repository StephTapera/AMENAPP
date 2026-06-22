# Context Intelligence OS — Frozen Contracts

STATUS: FROZEN  
Frozen: 2026-06-15  
Version: v1  

## Changelog
- 2026-06-15: Initial freeze — all 4 Swift files + 1 TypeScript mirror complete

## FROZEN RULE
No agent may modify these files after Wave 0 freeze.  
Changes require: unfreeze → amend → refreeze with changelog entry, restart all dependents.

---

## Contracts Summary

### AnyCodableValue.swift
Recursive Codable enum (string/int/double/bool/array/dictionary/null).  
Used as payload value type in ContextSignal.

### ContextSignal.swift
Core event spine. Every capability emits a `ContextSignal`.

| Field | Type | Notes |
|---|---|---|
| id | UUID | Unique per emission |
| type | SignalType | 21 cases (see enum) |
| tierCeiling | TierCeiling | s/c/p |
| subjectRefs | [GraphRef] | Nodes this signal touches |
| payload | [String: AnyCodableValue] | Small, typed, no raw content |
| occurredAt | Date | Preserved through offline queue |
| decayHalfLifeDays | Double | Consumed by Decay Engine |
| consentEdgeRequired | ConsentEdge? | nil = always allowed (device-only) |

**Tier-S invariant**: `crisisSurfaceOpened` carries tierCeiling `.s`. It MUST NEVER reach the network layer. The ContextBus actor enforces this before any forward attempt.

### ConsentEdge.swift
10 consent graph edges. All default OFF except `activityToRhythm` (on-device, default ON).

### Entitlement.swift
Single source of monetization truth.

**NOTE**: The enum is named `SystemCapability` (not `Capability` as in some spec documents). All downstream agents MUST use `SystemCapability`.

| Tier | Capabilities |
|---|---|
| free | signalBus, permissionsCenter, crisisDampening, gentleCheckIns, rhythmEngine, offlineCapture, basicContinuity, noteToGiveBridge, messagePrayerExtraction, visitVerification, givingReceipts, constellationModel, basicMatchFeedback, groupSuggestionsJoin |
| premium | bereanContextInjection, verseResonance, cohortResonance, givingPortfolio, continuityCrossDevice, seasonsInsights, matchFeedbackExplained |
| church | volunteerNeedsPosting, groupFormationAnalytics, communityHealth |
| creator | teachingAnalytics |

**Crisis supremacy**: While `CrisisDampening.isActive`, ALL upsellable capabilities return `.crisisSuppressed`. Enforced at `EntitlementGate.canAccess`, not in views.

### contracts/contextSignal.ts (TypeScript mirror)
Field-for-field mirror of Swift types. `assertServerEmittable()` throws if `tierCeiling === "s"` — defense in depth on top of client-side enforcement.

---

## Key Invariants for All Downstream Agents

1. Import contracts via `Shared/Contracts/` — never re-declare these types
2. Use `SystemCapability` (not `Capability`)  
3. Tier-S signals: device-only, never forwarded
4. All ctx_ feature flags default OFF
5. GateDecision.crisisSuppressed on all upsellable capabilities during dampening
6. Deny-by-default Firestore rules ship with every new collection

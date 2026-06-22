# Berean Intelligence Layer Contracts

Frozen: 2026-06-11  
Version: `bil-wave0-v1`  
Firebase project: `amen-5e359`  
Region: `us-central1`

Wave 0 is contract-only. No implementation, callables, tests, rules, demos, or SwiftUI surfaces are shipped by this contract set.

## Contract Files

| File | Purpose |
| --- | --- |
| [DataSchemas.md](DataSchemas.md) | Firestore/local schemas for CompactionEpisode, LedgerEntry, ConversationBranch, SourceCard, ContextPackage, CommitmentSuggestion, BriefingDigest, AuditReport, WidgetSchema, ModeProfile, and RouteDecision. |
| [TierResolutionMemo.md](TierResolutionMemo.md) | Binding Tier S/C/P behavior, including Tier P local-only compaction and no server/vector plaintext. |
| [FeatureFlags.md](FeatureFlags.md) | Complete `bil_*` Remote Config manifest, all default OFF. |
| [ExtensionPoints.md](ExtensionPoints.md) | Only approved integration points into Berean chat/realtime, memory, Hey Feed, commitments, Aegis, EventKit, notifications, and Remote Config. |
| [WidgetSchemaSpec.md](WidgetSchemaSpec.md) | BI-13 declarative widget schema v1, validation rules, and SwiftUI component mapping table. |
| [ScratchpadSanitization.md](ScratchpadSanitization.md) | BI-12 sanitized progress-event policy and forbidden content list. |
| [AuditRubric.md](AuditRubric.md) | BI-11 stake-classification rubric and reserved C59 capability registration. |
| [Wave0Decisions.md](Wave0Decisions.md) | Recorded decisions and remaining human checkpoints. |

## Wave 0 Exit Criteria

| Criterion | Status | Evidence |
| --- | --- | --- |
| Every schema has a written contract | Complete | `DataSchemas.md` |
| Tier S/C/P behavior is resolved | Complete | `TierResolutionMemo.md` |
| Every `bil_*` flag is listed and default OFF | Complete | `FeatureFlags.md` |
| Existing extension points are mapped | Complete | `ExtensionPoints.md` |
| Widget schema v1 is specified | Complete | `WidgetSchemaSpec.md` |
| Scratchpad sanitization is specified | Complete | `ScratchpadSanitization.md` |
| Audit rubric and GUARDIAN/C59 registration are specified | Complete | `AuditRubric.md` |
| Open questions are recorded as decisions | Complete | `Wave0Decisions.md` |

## Implementation Guardrails for Waves 1-5

- Wave 1 must create static HTML demos under `Demos/BIL/` before SwiftUI work starts.
- Wave 2 engines may not write user-visible UI and must remain behind `bil_*` flags.
- Wave 3 SwiftUI must use approved demos, GlassKit/native glass rules, no glass-on-glass, and `Motion.adaptive`.
- Wave 4 must include tier-leak tests proving Tier P plaintext never reaches server functions, logs, summaries, vectors, audits, telemetry, or source cards.
- Wave 5 may recommend flag order but must not flip flags.

## Suggested Flag Enablement Order

Do not flip flags in Wave 0. The planned Wave 5 recommendation remains:

1. `bil_progressive_streaming`
2. `bil_stop_and_steer`
3. `bil_compactor`
4. `bil_ledger`
5. `bil_scripture_crosscheck`
6. `bil_action_extraction`
7. Remaining features after QA go/no-go sheets

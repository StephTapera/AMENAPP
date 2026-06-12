# BIL Feature Flag Manifest

Frozen: 2026-06-11  
Version: `bil-wave0-v1`  
Remote Config owner: `AMENFeatureFlags` / Firebase Remote Config.  
Rule: every key defaults `false` in app defaults and Remote Config templates until a human flips it after Wave 5.

## Master Flags

| Key | Default | Owns | Notes |
| --- | --- | --- | --- |
| `bil_enabled` | `false` | All | Master kill switch. All BIL code must also check its feature-level flag. |
| `bil_demos_approved` | `false` | UI | Administrative marker only. Does not expose user-facing features. |

## Pillar A - Context and Memory

| Feature | Key | Default | Notes |
| --- | --- | --- | --- |
| BI-01 | `bil_compactor` | `false` | Enables automatic and manual compaction only after tier guards exist. |
| BI-01 | `bil_compactor_approval_diff` | `false` | Enables user approval diff cards. If false, default mode is auto with visible undo. |
| BI-02 | `bil_ledger` | `false` | Enables Context Ledger surface and ledger injection. |
| BI-02 | `bil_ledger_conflict_resolution` | `false` | Enables conflict cards. Required before ledger writes can graduate beyond local prototypes. |
| BI-03 | `bil_branching` | `false` | Enables branch creation, picker, diff, and merge synthesis. |
| BI-04 | `bil_source_cards` | `false` | Enables Source Card creation and library surfaces. |
| BI-05 | `bil_context_packages` | `false` | Enables package launch/share/versioning. |

## Pillar B - Faith Intelligence

| Feature | Key | Default | Notes |
| --- | --- | --- | --- |
| BI-06 | `bil_scripture_crosscheck` | `false` | Enables five-layer epistemic response structure. |
| BI-07 | `bil_mode_switching` | `false` | Enables advisory mode classifier and override chip. |
| BI-07 | `bil_mode_package_hooks` | `false` | Enables mode-to-package binding. Requires BI-05. |

## Pillar C - Action and Proactivity

| Feature | Key | Default | Notes |
| --- | --- | --- | --- |
| BI-08 | `bil_action_extraction` | `false` | Enables extraction into `CommitmentSuggestion`. |
| BI-08 | `bil_commitment_review_tray` | `false` | Enables review tray UI. Requires accepted suggestions to convert to existing `AmenCommitmentObject`. |
| BI-09 | `bil_briefing_memory` | `false` | Enables daily/weekly BIL digest generation. |
| BI-09 | `bil_briefing_notifications` | `false` | Enables optional notifications after explicit opt-in. |
| BI-10 | `bil_conversation_timeline` | `false` | Enables timeline view generated from compaction episodes. |

## Pillar D - Trust and Quality

| Feature | Key | Default | Notes |
| --- | --- | --- | --- |
| BI-11 | `bil_answer_audit` | `false` | Enables stake-gated critic passes. |
| BI-11 | `bil_answer_audit_guardian_c59` | `false` | Enables GUARDIAN/Aegis registration path for C59. |
| BI-12 | `bil_scratchpad` | `false` | Enables sanitized progress scratchpad. |

## Pillar E - Runtime and UX

| Feature | Key | Default | Notes |
| --- | --- | --- | --- |
| BI-13 | `bil_widgets` | `false` | Enables declarative widget schema generation and validation. |
| BI-13 | `bil_artifact_workspace` | `false` | Enables persistent artifact pane/version history. |
| BI-14 | `bil_progressive_streaming` | `false` | Enables Markdown buffering/progressive rendering improvements. |
| BI-14 | `bil_stop_and_steer` | `false` | Enables mid-stream steering continuation. Requires `bil_progressive_streaming`. |
| BI-15 | `bil_query_routing` | `false` | Enables model route decision engine. |
| BI-15 | `bil_query_routing_override` | `false` | Enables per-message `Think harder`. |
| BI-15 | `bil_route_cost_dashboard` | `false` | Enables aggregate route/cost telemetry dashboard. |

## Flag Evaluation Rules

1. User-visible code must require `bil_enabled == true` and the feature flag.
2. Server callables must enforce the corresponding flag independently; client flags are UX gates only.
3. Tier P guards must run before flag-driven network calls.
4. Existing flags may remain prerequisites but do not replace BIL flags. Examples: `bereanConversationMemoryEnabled`, `bereanStreamingResponseEnabled`, `conversationMemorySearchEnabled`, `aegisPrePostReviewEnabled`, `amenDailyDigestEnabled`, `bereanPulseEnabled`, `contextCommitmentBridgeEnabled`, and `integration_calendar_enabled`.
5. Flag-off behavior must be invisible: no empty buttons, no unavailable upsells, no hidden background processing.

## AMENFeatureFlags Contract Delta

Wave 2 may add read-only `@Published private(set)` properties for these keys to `AMENFeatureFlags`. Defaults must be `false` in `buildDefaults`. No existing non-BIL flag may be repurposed as a BIL rollout flag.

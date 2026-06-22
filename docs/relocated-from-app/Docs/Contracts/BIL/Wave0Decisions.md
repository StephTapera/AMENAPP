# BIL Wave 0 Decisions

Frozen: 2026-06-11  
Version: `bil-wave0-v1`

## Binding Decisions

1. Tier P compaction is local-only. If no on-device summarizer is available, BI-01 does not generate L1/L2 for Tier P and the UI explains that private chats stay local.
2. BI-01 ships both auto-compaction with visible undo and approval-diff mode. Default is auto with visible undo, gated by `bil_compactor`; diff mode is gated by `bil_compactor_approval_diff`.
3. `LivingMemoryService` is not an active implementation surface. BIL L2 retrieval/offload uses the active RAG/conversation-memory surfaces: `ragSearch`, `searchConversationMemory`, `saveConversationMemory`, and `threads/{threadId}/memories` where tier policy permits.
4. BI-08 must convert accepted suggestions into the existing `AmenCommitmentObject`/Action Intelligence path. A new BIL task system is forbidden.
5. The prompt phrase `SSE streaming` maps to the current callable-plus-typewriter chat path in `BereanStreamingService.stream(prompt:onToken:)` and the realtime WebSocket path. BIL does not introduce a new streaming transport in Wave 0.
6. GUARDIAN registration uses reserved capability ID `C59_BEREAN_MULTI_AGENT_ANSWER_AUDIT`. Because no canonical all-caps GUARDIAN registry type was found, Wave 2 integrates through Aegis/content-safety adapters unless a canonical registry appears first.
7. HTML demos remain mandatory before SwiftUI for all novel UI surfaces. This contract set does not waive demo approval.
8. All `bil_*` flags default OFF and must be enforced on both client and server.
9. BI-09 uses Hey Feed preference signals as inputs, but digest rendering/persistence belongs to Daily Digest/Berean Pulse or a new BIL digest callable, not Hey Feed ranking collections.
10. BI-13 widgets are declarative JSON only. Raw HTML/JS/code execution is forbidden.
11. BI-15 cannot route Tier P plaintext to a server model, even when the user taps `Think harder`.
12. No BIL feature may modify GlassKit internals, encryption boundaries, Aegis internals, feed ranking behavior, or existing Berean streaming semantics without a contract amendment.

## Human Checkpoints Still Required After Wave 0

| Checkpoint | Required before |
| --- | --- |
| HTML demo approval for each UI surface in `Demos/BIL/` | Any SwiftUI BI surface work. |
| Server callable design review for Tier S/C summarization, audit, routing, and source processing | Wave 2 backend implementation. |
| Aegis/T&S review of C59 adapter | Enabling `bil_answer_audit_guardian_c59`. |
| Privacy review of Tier P local compaction implementation | Enabling local Tier P compaction. |
| Cost review of BI-11/BI-15 telemetry | Any staged rollout beyond internal testing. |

## Stop Conditions Carried Forward

Halt implementation and report if:

- A BIL feature requires sending Tier P plaintext to a server.
- Existing Aegis/content-safety hooks cannot support C59 without modifying internals.
- Existing commitment primitives cannot represent BI-08 accepted suggestions without a parallel task system.
- Query routing or audits exceed the budget assumptions in `AuditRubric.md`.
- Existing chat streaming must be rewritten rather than extended through metadata/buffering.

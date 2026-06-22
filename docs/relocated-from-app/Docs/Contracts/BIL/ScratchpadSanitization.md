# BIL Scratchpad Sanitization Policy

Frozen: 2026-06-11  
Version: `bil-wave0-v1`  
Feature: BI-12 Agentic Scratchpad Visibility

The scratchpad is a sanitized progress feed, not a chain-of-thought viewer. It may show what stage Berean is in, what approved tools ran, and which user-visible sources were consulted. It must never expose hidden reasoning, private prompts, raw model deliberation, credentials, other users' data, or Tier P plaintext.

## Allowed Event Shape

```json
{
  "id": "string",
  "threadId": "string",
  "turnId": "string",
  "stage": "routing|retrieval|source_read|tool_call|audit|streaming|compaction|widget_validation|commitment_extraction",
  "status": "queued|running|complete|skipped|warning|failed",
  "visibleLabel": "string",
  "visibleDetail": "string?",
  "sourceRefs": [{ "kind": "source_card|ledger_entry|episode|route_decision|audit_report", "id": "string", "label": "string" }],
  "createdAt": "Timestamp"
}
```

`visibleLabel` is short and user-facing, for example `Checking scripture grounding`, `Searching your approved sources`, or `Routing to standard model`.

## Allowed Content

| Category | Allowed examples |
| --- | --- |
| Retrieval | Source Card title, citation label, episode title, result count. |
| Tool calls | Approved tool/callable name category, not raw payload: `source search`, `calendar permission check`, `commitment draft`. |
| Audit | Critic name, pass/warn/fail/skipped, short verdict summary. |
| Routing | Route class, user-facing reason, latency/cost bucket. |
| Compaction | Episode count, approval state, undo availability. |
| Widget validation | Widget kind and validation result. |

## Forbidden Content

- Raw chain-of-thought or hidden reasoning steps.
- System prompts, developer prompts, private policy, route policy internals, or hidden safety classifier prompts.
- Raw user message content unless it is already visible in the current chat turn.
- Tier P plaintext, Tier P summaries, Tier P ledger beliefs, Tier P source titles, Tier P citations, or Tier P vector identifiers.
- Other users' messages, display names, emails, phone numbers, un-hashed UIDs, private Space data, or unauthorized source-card content.
- API keys, client secrets, provider session tokens, Firebase callable payloads containing content, or WebSocket frames.
- Exact medical/legal/crisis classifier keyword lists if those lists are safety-sensitive runtime config.

## Tier Rules

| Tier | Scratchpad behavior |
| --- | --- |
| `tier_s` | May show source titles, citation labels, audit summaries, routing summaries. |
| `tier_c` | May show authorized source titles and short metadata. Avoid raw snippets unless already visible in the response. |
| `tier_p` | Local stage labels only. Example: `Using private local context`. No content-bearing refs. Server scratchpad events are skipped. |

## Sanitization Pipeline

1. Build raw internal event in memory only.
2. Resolve tier and authorization before formatting.
3. Redact IDs and payload fields according to tier.
4. Replace raw snippets with labels or counts.
5. Validate against forbidden patterns and max length.
6. Persist/display only the sanitized event.

Max lengths: `visibleLabel` <= 80 characters; `visibleDetail` <= 240 characters; max 20 scratchpad events per response unless user expands debug details.

## UI Contract

- Default collapsed state: one-line status such as `Checked` or `Working`.
- Expanded state: chronological event list with clear labels.
- No spinner-only wait when `bil_scratchpad` is enabled and an operation exceeds 500 ms.
- Events must be accessible via VoiceOver and respect Reduce Motion through `Motion.adaptive`.
- Scratchpad cannot include visible text that teaches internal shortcuts or implementation details beyond user-relevant transparency.

## Logging Contract

Analytics may log counts by stage/status and latency buckets. Analytics may not log `visibleDetail` or source labels for Tier C/P. Tier P scratchpad analytics must be aggregate-only.

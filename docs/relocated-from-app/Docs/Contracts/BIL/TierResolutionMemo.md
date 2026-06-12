# BIL Tier Resolution Memo

Frozen: 2026-06-11  
Version: `bil-wave0-v1`  
Binding for: BI-01, BI-02, BI-04, BI-09, BI-11, BI-12, BI-13, BI-15.

## Decision

BIL keeps the existing AMEN privacy lanes and maps them as follows for this program:

| BIL tier | Existing naming seen in code | Meaning for BIL |
| --- | --- | --- |
| `tier_s` | public/community in `ActionIntelligencePrivacyTier.publicCommunity` | Shareable/community-safe content that may use server summarization, embedding, and retrieval when existing product permissions allow it. |
| `tier_c` | confidential in `ActionIntelligencePrivacyTier.confidential` | Authenticated confidential content. Server processing is allowed only through approved callables with App Check/Auth, no raw-content analytics, and source-scoped retention. |
| `tier_p` | sacred/private/E2EE in prompt; closest local-only behavior in code is `requiresLocalDetection` | Private/E2EE content. Plaintext never leaves the device, never enters Cloud Functions, server logs, vector stores, Remote Config telemetry, analytics, or Firestore plaintext fields. |

The prompt names Tier P as private/E2EE. Where existing code uses `tier_p` for public/community, BIL code must introduce explicit BIL tier names or adapter comments to avoid semantic confusion. Do not reuse `ActionIntelligencePrivacyTier.publicCommunity.rawValue` as BIL Tier P.

## BI-01 Compaction

| Tier | L0 working memory | L1 episode summaries | L2 semantic offload | UI behavior |
| --- | --- | --- | --- | --- |
| `tier_s` | Last 10-15 turns verbatim in normal thread store. | Server or client summarization allowed. | Living Memory/vector offload allowed after approval/auto-approval. | Shows `Compacted` affordance and reversible episode expansion. |
| `tier_c` | Last 10-15 turns in authenticated thread store. | Approved Cloud Function summarization allowed if raw content is not logged and retention follows thread policy. | Living Memory offload allowed with source-scoped ACL and no public index. | Shows `Compacted` affordance, approval diff if user setting requires it. |
| `tier_p` | Device-local E2EE only. | Client-side only if an on-device summarizer exists and stores output in the same encrypted local store. If no on-device summarizer is available, no L1 is generated. | Not allowed in server/vector layer. | UI says private chats are kept local; `Compacted` appears only for local compaction. Otherwise offer manual local notes, not server compaction. |

Tier P open decision resolved: ship no server-side compaction for Tier P. Local compaction is permitted only when plaintext stays inside the device trust boundary. If the local path is unavailable, BI-01 degrades gracefully with no L1/L2.

## BI-02 Ledger

| Tier | Storage | Injection | Provenance |
| --- | --- | --- | --- |
| `tier_s` | Firestore `users/{uid}/bereanLedger`. | May be injected into server prompts when relevant and authorized. | Turn/source references allowed. |
| `tier_c` | Firestore `users/{uid}/bereanLedger`, content ACL-scoped to owner. | May be injected into approved server prompts for that owner/session. | Raw text is allowed in user-visible ledger, not analytics. |
| `tier_p` | Device-local encrypted ledger only. | Injected only into local/on-device prompts. If a server model is used, inject a placeholder capability note only: `Private memory exists but is unavailable to server processing.` | Provenance stays local. No turn plaintext or belief text in Firestore. |

Pinned and locked Tier P ledger entries must survive local compaction. They must not be synced as plaintext.

## BI-04 Source Cards

| Tier | Summary layers | Citations | Embeddings |
| --- | --- | --- | --- |
| `tier_s` | Server summary layers allowed. | Inline citations allowed. | Living Memory/vector allowed. |
| `tier_c` | Server summary layers allowed through approved functions. | Inline citations allowed for authorized user/team. | Living Memory/vector allowed with ACL and deletion propagation. |
| `tier_p` | Client-only summary layers, or no summary if local summarizer unavailable. | Local citations only. | No server/vector embedding. |

Imported chats inherit the highest sensitivity of any included turn. A mixed-tier Source Card must either split into per-tier cards or be promoted to the most restrictive tier.

## BI-09 Briefing Digests

Briefings must never pull Tier P plaintext into scheduled Cloud Functions. For Tier P signals, the server may receive aggregate booleans or counts only when generated locally and explicitly synced without content, for example `hasPrivatePrayerReminder: true`. Tier P digest text must be built locally or omitted.

## BI-11 Audits

Audit critics may inspect Tier S and Tier C response candidates through approved server paths. For Tier P, server critics are prohibited. Tier P uses local deterministic checks only, or the audit affordance shows `Private mode: server audit skipped`.

## BI-12 Scratchpad

Scratchpad events are metadata-only. Tier P scratchpad may show local stage labels but never raw retrieved text, private ledger text, private source-card text, prompt fragments, or unredacted identifiers.

## BI-13 Widgets and Artifacts

Widgets generated from Tier P content are local artifacts. They may be exported only by explicit user action through existing export/share controls. Server-hosted artifact version history is disabled for Tier P.

## BI-15 Routing

Tier P route decision is `local_only` unless the user explicitly moves content out of private mode through an existing product action. `Think harder` may increase local effort; it must not route Tier P plaintext to a server model.

## Logging and Telemetry

Allowed for all tiers: feature flag state, route class, latency, error code, count metrics, and hashed opaque IDs where existing analytics allows them.

Forbidden for Tier P: raw content, summaries, extracted beliefs, citations, source titles if user-authored/private, prompt text, completion text, embedding input, vector IDs tied to plaintext, and audit evidence.

## Enforcement Requirements

1. Any BIL Cloud Function handling content must require `{ tier, sourceKind, sourceId }` and reject `tier_p` plaintext payloads.
2. Any BIL client call into server summarization, source processing, audit, or routing must guard Tier P before network I/O.
3. Tests must include forced Tier P payload attempts and assert no server function accepts or logs plaintext.
4. All user-facing degradation messages must be factual and calm: no upsell, no pressure to disable privacy.

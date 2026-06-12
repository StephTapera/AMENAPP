# BIL Data Schemas Contract

Frozen: 2026-06-11  
Version: `bil-wave0-v1`  
Scope: Firestore documents, local cache projections, callable payload names, and schema invariants for BI-01 through BI-15.

This is contract-only. Wave 0 does not implement models, services, rules, callables, indexes, UI, or demos.

## Shared Enums

```text
BILTier = "tier_s" | "tier_c" | "tier_p"
BILApprovalState = "auto_approved" | "pending_user_approval" | "approved" | "rejected" | "undone"
BILProvenanceKind = "turn" | "source_card" | "ledger_entry" | "compaction_episode" | "system" | "callable"
BILModeId = "prayer" | "study" | "church_notes" | "project_planning" | "coding" | "leadership" | "moderation" | "content_creation"
BILStakeClass = "trivial" | "normal" | "faith_theology" | "crisis_adjacent" | "medical_legal_adjacent" | "architecture" | "privacy_sensitive"
BILRouteClass = "fast" | "standard" | "frontier" | "local_only"
```

Timestamps are Firestore `Timestamp` server values unless explicitly marked as local-only `Date`.

## BI-01 CompactionEpisode

Firestore path:

```text
users/{uid}/bereanThreads/{threadId}/compactionEpisodes/{episodeId}
```

Local Tier P cache path is implementation-defined, but must be encrypted with the existing Tier P device-local store and must not mirror plaintext into Firestore.

```json
{
  "id": "string",
  "threadId": "string",
  "ownerUid": "string",
  "turnRange": { "startTurnId": "string", "endTurnId": "string", "startIndex": 0, "endIndex": 0 },
  "summaryStruct": {
    "decisions": [{ "id": "string", "text": "string", "confidence": 0.0, "provenanceTurnIds": ["string"] }],
    "facts": [{ "id": "string", "text": "string", "confidence": 0.0, "provenanceTurnIds": ["string"] }],
    "openQuestions": [{ "id": "string", "text": "string", "ownerUid": "string?", "provenanceTurnIds": ["string"] }],
    "actionItems": [{ "id": "string", "text": "string", "ownerUid": "string?", "dueAt": "Timestamp?", "provenanceTurnIds": ["string"] }],
    "preferences": [{ "id": "string", "text": "string", "provenanceTurnIds": ["string"] }],
    "links": [{ "id": "string", "url": "string", "label": "string?", "sourceTurnId": "string" }],
    "risks": [{ "id": "string", "text": "string", "severity": "low|medium|high", "provenanceTurnIds": ["string"] }]
  },
  "embeddingRef": { "provider": "living_memory", "collection": "string", "vectorId": "string" },
  "tier": "tier_s|tier_c|tier_p",
  "approvedBy": "uid|null",
  "approvalState": "auto_approved|pending_user_approval|approved|rejected|undone",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

L0 working memory is not represented by `CompactionEpisode`; it remains the last 10-15 turns in the thread payload. L1 episodes must include enough `provenanceTurnIds` to expand originals. L2 offload must store only the approved episode text and metadata permitted by the tier memo.

## BI-02 LedgerEntry

Firestore path:

```text
users/{uid}/bereanLedger/{entryId}
```

Thread-scoped projection path:

```text
users/{uid}/bereanThreads/{threadId}/ledgerRefs/{entryId}
```

```json
{
  "id": "string",
  "ownerUid": "string",
  "belief": "string",
  "provenance": {
    "kind": "turn|source_card|ledger_entry|compaction_episode|system|callable",
    "turnId": "string?",
    "threadId": "string?",
    "sourceCardId": "string?",
    "episodeId": "string?"
  },
  "state": "active|pinned|locked|corrected|deleted",
  "pinScope": "thread|package|global|null",
  "lockReason": "user_locked|system_safety|null",
  "history": [
    { "at": "Timestamp", "actorUid": "string", "action": "created|pinned|locked|corrected|deleted|restored", "previousBelief": "string?", "newBelief": "string?" }
  ],
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

Conflict handling is mandatory: a later inferred entry that contradicts an active, pinned, or locked entry creates a resolution card payload and may not silently overwrite the ledger.

## BI-03 ConversationBranch

Firestore path:

```text
users/{uid}/bereanThreads/{threadId}/branches/{branchId}
```

```json
{
  "id": "string",
  "ownerUid": "string",
  "parentThreadId": "string",
  "parentBranchId": "string?",
  "forkTurnId": "string",
  "name": "string",
  "divergenceSummary": "string",
  "mergeEpisodeId": "string?",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

Merging branches never rewrites either source branch. Merge creates a synthesis `CompactionEpisode` appended to the destination branch.

## BI-04 SourceCard

Firestore path:

```text
users/{uid}/sourceCards/{sourceCardId}
```

```json
{
  "id": "string",
  "ownerUid": "string",
  "sourceType": "document|sermon|note|pdf|link|imported_chat|thread_timeline",
  "title": "string",
  "layers": {
    "oneLine": "string",
    "paragraph": "string",
    "outline": [{ "heading": "string", "items": ["string"] }]
  },
  "citations": [{ "id": "string", "label": "string", "locator": "page|timestamp|url|block|turn", "value": "string", "quoteHash": "string?" }],
  "entities": [{ "id": "string", "name": "string", "type": "person|place|topic|organization|event|doctrine|other" }],
  "scriptureRefs": [{ "reference": "string", "normalizedReference": "string", "translation": "string?", "citationId": "string?" }],
  "tier": "tier_s|tier_c|tier_p",
  "embeddingRef": { "provider": "living_memory", "collection": "string", "vectorId": "string" },
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

Grounded answers must cite `citations[].id` inline. Raw source text may be stored only where existing tier policy allows it.

## BI-05 ContextPackage

Firestore path:

```text
users/{uid}/contextPackages/{packageId}/versions/{versionId}
```

Space share path:

```text
spaces/{spaceId}/contextPackages/{packageId}/versions/{versionId}
```

```json
{
  "id": "string",
  "version": 1,
  "ownerUid": "string",
  "name": "string",
  "instructions": "string",
  "pinnedLedgerIds": ["string"],
  "sourceCardIds": ["string"],
  "modeId": "prayer|study|church_notes|project_planning|coding|leadership|moderation|content_creation",
  "toolGrants": ["source_cards|commitments|eventkit|moderation_review|artifact_workspace|routing_override"],
  "spaceShareScope": { "spaceId": "string?", "visibility": "private|space_members|space_leaders" },
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

Edits create a new immutable version. Existing sessions keep their original version.

## BI-08 CommitmentSuggestion

Firestore review tray path:

```text
users/{uid}/bereanThreads/{threadId}/commitmentSuggestions/{suggestionId}
```

```json
{
  "id": "string",
  "threadId": "string",
  "ownerUid": "string",
  "sourceTurnId": "string",
  "extraction": {
    "kind": "owner|blocked_by|needs_reply|should_schedule|should_draft",
    "title": "string",
    "ownerUid": "string?",
    "blockedBy": "string?",
    "dueAt": "Timestamp?",
    "draftPrompt": "string?",
    "confidence": 0.0
  },
  "targetCommitment": {
    "primitive": "AmenCommitmentObject",
    "intentKind": "prayer_commitment|volunteer_offer|follow_up|event|open_question|initiative_idea",
    "objectClass": "moment|commitment|need|initiative",
    "privacyTier": "tier_s|tier_c|tier_p"
  },
  "reviewState": "pending|accepted|dismissed|converted",
  "commitmentObjectId": "string?",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

BIL must not create a parallel task primitive. Accepted suggestions convert through the existing `AmenCommitmentObject`/Action Intelligence path or an ARCH-approved adapter.

## BI-09 BriefingDigest

Firestore path:

```text
users/{uid}/briefingDigests/{digestId}
```

```json
{
  "id": "string",
  "ownerUid": "string",
  "cadence": "daily|weekly",
  "dateKey": "yyyy-MM-dd",
  "sections": [{ "id": "string", "title": "string", "items": [{ "title": "string", "sourceKind": "commitment|prayer|thread|space|study|build_progress", "sourceId": "string?", "priority": "low|normal|high" }] }],
  "preferenceSignals": [{ "kind": "hey_feed|explicit_setting|liturgical_season|recent_activity", "value": "string" }],
  "delivery": { "inApp": true, "notification": false, "silencedUntil": "Timestamp?" },
  "createdAt": "Timestamp"
}
```

Digests must include silence controls in every surface and must not include engagement-bait language.

## BI-11 AuditReport

Firestore path:

```text
users/{uid}/bereanThreads/{threadId}/auditReports/{auditId}
```

```json
{
  "id": "string",
  "threadId": "string",
  "responseTurnId": "string",
  "stakeClass": "trivial|normal|faith_theology|crisis_adjacent|medical_legal_adjacent|architecture|privacy_sensitive",
  "guardianCapabilityId": "C59_BEREAN_MULTI_AGENT_ANSWER_AUDIT",
  "criticVerdicts": [
    { "critic": "factual_accuracy|scripture_grounding|safety|privacy_tier|product_logic|implementation_risk", "verdict": "pass|warn|fail|skipped", "summary": "string", "evidenceRefs": ["string"] }
  ],
  "visibleSummary": "string",
  "createdAt": "Timestamp",
  "latencyMs": 0
}
```

Raw chain-of-thought is never stored. Critic summaries must be user-safe explanations.

## BI-13 WidgetSchema v1

Widget schema details are frozen in `WidgetSchemaSpec.md`. The persisted envelope is:

```json
{
  "schemaVersion": 1,
  "widgetId": "string",
  "kind": "comparison_table|fillable_form|checklist|scripture_card|chart",
  "title": "string",
  "data": {},
  "actions": [{ "id": "string", "label": "string", "intent": "copy|save_artifact|create_commitment|attach_source|none" }],
  "validationHash": "string"
}
```

## BI-07 ModeProfile

Firestore/config path:

```text
bilConfig/modeProfiles/profiles/{modeId}
```

```json
{
  "id": "prayer|study|church_notes|project_planning|coding|leadership|moderation|content_creation",
  "toneProfile": "string",
  "outputStructure": ["string"],
  "defaultTools": ["string"],
  "contextPackageHooks": ["string"],
  "aegisSensitivityProfile": "standard|elevated|crisis_sensitive|moderation_authorized",
  "userOverrideAllowed": true
}
```

Detection is advisory. User override wins for the active message/session.

## BI-15 RouteDecision

Telemetry path:

```text
users/{uid}/bereanThreads/{threadId}/routeDecisions/{decisionId}
```

```json
{
  "id": "string",
  "threadId": "string",
  "requestTurnId": "string",
  "routeClass": "fast|standard|frontier|local_only",
  "modelAlias": "string",
  "reasonCodes": ["trivial_chat|theology|long_context|code|privacy_tier|user_think_harder|budget_guard"],
  "visibleSummary": "string",
  "latencyMs": 0,
  "estimatedCostMicros": 0,
  "createdAt": "Timestamp"
}
```

The scratchpad may display `visibleSummary`, route class, and model alias. It must not reveal hidden policy, private prompts, or other users' data.

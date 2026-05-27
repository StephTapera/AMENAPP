# Creator Spaces Firestore Schema

Contract-first schema for Creator Spaces v1. Server callables own all provenance, moderation, entitlement, and ranking-sensitive fields.

## `mediaAssets/{assetId}`

```json
{
  "assetId": "string",
  "authorId": "string",
  "createdAt": "timestamp",
  "type": "presence | single | video | audio | creation",
  "frames": {
    "back": { "storagePath": "string", "width": 0, "height": 0 },
    "front": { "storagePath": "string", "width": 0, "height": 0 },
    "audio": { "storagePath": "string", "spatial": false },
    "layout": "pip | split | stacked"
  },
  "context": { "location": null, "emotionTags": [], "ambientSignals": {} },
  "provenance": { "ref": "provenanceLabels/{labelId}" },
  "moderation": { "status": "pending | approved | blocked", "guardianRef": null, "safetyFlags": [] },
  "feed": { "distribution": "daily_portion | profile_only | rooms_only", "scoreInputs": {} },
  "memoryGraph": { "nodeId": "memoryNodes/{nodeId}" }
}
```

## `provenanceLabels/{labelId}`

Phase 1 only stores fields the app can honestly compute. Phase 2 fields stay `null` until a real detector/scoring pipeline exists.

```json
{
  "labelId": "string",
  "assetId": "string",
  "authorId": "string",
  "capturedOnDevice": true,
  "sourceCamera": "string",
  "timestampChain": [{ "event": "upload_received", "ts": "timestamp" }],
  "editHistory": [{ "tool": "string", "ts": "timestamp", "aiInvolved": false }],
  "editedWithAI": false,
  "aiAssistedPercent": null,
  "syntheticElementsPresent": null,
  "authenticityConfidence": null,
  "signature": "server HMAC",
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

Display rule: show `Shot Real` only when `capturedOnDevice == true`, `editHistory` is empty, and `editedWithAI == false`.

## `memoryNodes/{nodeId}`

```json
{
  "nodeId": "string",
  "assetId": "string",
  "authorId": "string",
  "edges": { "people": [], "events": [], "spaces": [], "scriptures": [], "projects": [] },
  "embeddingRef": null,
  "createdAt": "timestamp"
}
```

## Callable contracts

- `processMediaUpload(assetDraft) -> { assetId, labelId }`
- `getDailyPortion(cursor?) -> { items, exhausted, nextCursor? }`
- `recordEditEvent(assetId, tool, aiInvolved) -> { ok }`
- `runSafetyCheck(assetDraft) -> { decision, reasons }`
- `queryMemoryGraph(naturalLanguage) -> { nodeIds }`

## Required server configuration

Set `creator_spaces.hmac_secret` or `CREATOR_SPACES_HMAC_SECRET`. Without it, `processMediaUpload` fails closed so the app never presents unsigned provenance as trusted.

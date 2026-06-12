# Sanctuary Firestore Schema

Frozen: 2026-06-12  
Version: `2026-06-12-wave0-v1`

## Collections

| Path | Reader | Writer | Purpose |
| --- | --- | --- | --- |
| `livingVideos/{videoId}` | Authorized viewers | Server, creator owner via callable | Canonical LivingVideo record, transcript status, C2PA provenance, content type. |
| `livingVideos/{videoId}/transcriptChunks/{chunkId}` | Authorized viewers | Server only | Word-level timestamp chunks and embedding refs. |
| `livingVideos/{videoId}/anchors/{anchorId}` | Authorized viewers | Server; creator override callable | ScriptureAnchor docs, OSIS verse refs, confidence, source. |
| `livingVideos/{videoId}/layers/{layerId}` | Visibility scoped | Server; creator/group callables | VideoLayer docs and ordered blocks. |
| `livingVideos/{videoId}/reactions/{reactionId}` | Server only | Callable only | Raw SacredReaction writes. Client cannot read raw reaction docs. |
| `livingVideos/{videoId}/reactionFields/current` | Authorized viewers | Server only | Bucketed warmth density field, normalized `0...1`, never counts. |
| `watchRooms/{roomId}` | Room members | Callable only | WatchRoom host, member orbs, playhead, state, server timestamps. |
| `watchRooms/{roomId}/events/{eventId}` | Room members | Callable only | Short-lived sync ops for drift correction and presence ripples. |
| `journeyNodes/{userId}/nodes/{nodeId}` | User owner | Server and callable only | JourneyNode records for watch-complete, highlight, question, note, prayer. |

## Living Video Document

```json
{
  "id": "video_123",
  "mediaURL": "https://...",
  "transcriptStatus": "pending | processing | ready | failed",
  "scriptureAnchors": [],
  "layerRefs": [{ "id": "layer_1", "type": "scripture" }],
  "provenance": {
    "manifestURL": "https://...",
    "assertionHash": "sha256:...",
    "signer": "creator-or-device",
    "verified": true,
    "capturedAt": "server timestamp"
  },
  "contentType": "sermon | podcast | worship | testimony | study | event",
  "ownerUid": "uid",
  "visibility": "private | community | public",
  "createdAt": "server timestamp",
  "updatedAt": "server timestamp"
}
```

## Security Rules Sketch

```rules
match /livingVideos/{videoId} {
  allow read: if isAuthorizedVideoViewer(videoId);
  allow create, update: if false; // use callables so provenance and moderation hooks run
  allow delete: if false;

  match /anchors/{anchorId} {
    allow read: if isAuthorizedVideoViewer(videoId);
    allow write: if false;
  }

  match /layers/{layerId} {
    allow read: if canReadSanctuaryLayer(videoId, layerId);
    allow write: if false;
  }

  match /reactions/{reactionId} {
    allow read: if false;
    allow write: if false;
  }

  match /reactionFields/current {
    allow read: if isAuthorizedVideoViewer(videoId);
    allow write: if false;
  }
}

match /watchRooms/{roomId} {
  allow read: if isWatchRoomMember(roomId);
  allow write: if false;

  match /events/{eventId} {
    allow read: if isWatchRoomMember(roomId);
    allow write: if false;
  }
}

match /journeyNodes/{userId}/nodes/{nodeId} {
  allow read: if request.auth.uid == userId;
  allow write: if false;
}
```

## Mandatory Enforcement

1. App Check and Auth are required for every callable and HTTP endpoint.
2. Raw reaction documents are write-only through `sanctuaryReact`; clients read only `reactionFields/current`.
3. Creator analytics use scheduled weekly aggregation only. No public live counters are stored for client rendering.
4. Group-private layers reuse existing NoteShare-style visibility rules and server-resolved membership edges.
5. C2PA provenance fields travel with every video ingest and derived media record.

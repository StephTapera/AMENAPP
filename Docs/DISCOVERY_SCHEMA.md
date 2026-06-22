# DISCOVERY_SCHEMA.md
# AMEN Connect Discovery Engine — Firestore Collections, Indexes, and Security Rules

Wave 0 FROZEN: 2026-06-14

---

## Collections Used

| Collection         | Key Fields                                          | Notes |
|--------------------|-----------------------------------------------------|-------|
| `spaces`           | `visibility`, `nameLower`, `memberCount`, `growth7d`, `interests[]`, `createdAt` | Public communities; `nameLower` for text search |
| `rooms`            | `status` (live/open/closed), `roomType` (prayer/audio), `liveCount`, `speakerIds[]`, `lastActiveAt`, `startedAt` | Live rooms and prayer rooms |
| `churches`         | `verified`, `nameLower`, `geohash4`, `geohash6`, `latitude`, `longitude`, `serviceTimes[]`, `denomination` | `geohash4` for ~40km proximity queries |
| `events`           | `startsAt`, `createdAt`, `speakerIds[]`, `rsvpCount`, `nameLower` | Future events; `startsAt` for time-window query |
| `discussions`      | `visibility`, `titleLower`, `topicTags[]`, `replyCount`, `lastActivityAt`, `createdAt` | Public threads; `titleLower` for text search |
| `safetyCache`      | Subcollection `safetyCache/{type}/{id}` — `clearedBy`, `registryVersion`, `clearedAt` | Safety stamp cache per content item |
| `userInterests`    | `uid`, `interests[]`, `updatedAt` | Per-user interest graph (read by assembleDiscoveryFeed) |
| `presence`         | `uid`, `roomId`, `joinedAt`, `lastHeartbeatAt` | Real-time presence for live counts |

---

## Composite Indexes Required

### `rooms` — Live Now shelf
```
Collection: rooms
Fields: status ASC, lastActiveAt DESC
```

### `rooms` — Prayer rooms
```
Collection: rooms
Fields: roomType ASC, status ASC, lastActiveAt DESC
```

### `discussions` — Interest-filtered
```
Collection: discussions
Fields: topicTags ARRAY, visibility ASC, lastActivityAt DESC
```

### `discussions` — Text search prefix
```
Collection: discussions
Fields: titleLower ASC, visibility ASC
```

### `spaces` — Interest-filtered
```
Collection: spaces
Fields: interests ARRAY, visibility ASC, memberCount DESC
```

### `spaces` — Trending
```
Collection: spaces
Fields: visibility ASC, growth7d DESC
```

### `spaces` — Text search prefix
```
Collection: spaces
Fields: nameLower ASC, visibility ASC
```

### `events` — This week
```
Collection: events
Fields: startsAt ASC
```

### `churches` — Geohash nearby (range)
```
Collection: churches
Fields: geohash4 ASC, verified ASC
```

### `churches` — Text search prefix
```
Collection: churches
Fields: nameLower ASC, verified ASC
```

---

## Security Rule Intents

| Collection    | Read                                     | Write |
|---------------|------------------------------------------|-------|
| `spaces`      | Any authenticated user (public spaces)   | Owner + admin only |
| `rooms`       | Any authenticated user                   | Room host + server CF only (no client liveCount writes) |
| `churches`    | Any authenticated user                   | CF `verifyChurch` only |
| `events`      | Any authenticated user                   | Event creator + admin only |
| `discussions` | Any authenticated user (public discussions) | Thread owner + CF only |
| `safetyCache` | CF only (no client read)                 | CF only |
| `userInterests` | Owner only (uid match)                 | Owner + CF only |
| `presence`    | Any authenticated user (for live counts) | CF heartbeat only (no direct client writes) |

---

## Ranking Fields (server-authoritative, no client writes)

These fields are written by CFs only and must be protected by Firestore rules:

- `spaces.growth7d` — 7-day member growth (CF-written, never client)
- `rooms.liveCount` — live participant count (CF-written via presence)
- `rooms.speakerIds` — current speakers (CF-written)
- `discussions.replyCount` — reply count (CF-written, not client-incremented)

---

## CalmCap Contract

| Field                  | v1 Value | Notes |
|------------------------|----------|-------|
| `maxShelves`           | 8        | Hard stop — no 9th shelf ever rendered |
| `maxItemsPerShelf`     | 12       | Hard stop per horizontal shelf |
| `infiniteScroll`       | false    | ALWAYS false; client asserts this |
| `sessionSoftLimitSeconds` | 900   | 15-min gentle "you're caught up" nudge |

---

## `safetyCache` Subcollection Path

```
safetyCache/{contentType}/{contentId}
  clearedBy: "GUARDIAN" | "AEGIS"
  registryVersion: string
  clearedAt: ISO8601 timestamp
```

TTL: 24h (enforced by CF — content that hasn't been cleared in 24h is re-evaluated).

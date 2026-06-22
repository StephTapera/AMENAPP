# Moment Firestore Schema

This file documents the v1 Firestore data layer for the Moment system. The source of truth for the TypeScript contract remains `Contracts/moment/momentContracts.ts`.

## Paths

```text
moments/{momentId}
users/{ownerId}/momentSaves/{saveId}
```

## `moments/{momentId}`

Moment documents are finite records keyed by Moment id.

Required contract fields:

- `schemaVersion: 1`
- `id: string`
- `type: MomentType`
- `temporalState: TemporalState`
- `refId: string`
- `ownerId: string`
- `createdAt: number`
- `updatedAt: number`

Rules:

- Owner read only: authenticated `request.auth.uid` must equal `ownerId`.
- Client create, update, and delete are denied. Moment document lifecycle is server-owned.
- No Gather live rooms, feeds, or participant paths are opened in v1.

## `users/{ownerId}/momentSaves/{saveId}`

Saved Deepen outputs live under the owning user.

Required fields:

- `schemaVersion: 1`
- `momentId: string`
- `ownerId: string`
- `target: "prayerJournal" | "studyJournal" | "churchNotes" | "sermonCollection" | "savedTeachings"`
- `deepenAction: "summarize" | "crossReference" | "generatePrayer" | "generateStudyGuide" | "generateDiscussion" | "generateDevotional" | "saveTo"`
- `content: string`
- `citations: string[]`
- `guardian: { passed: true, policyVersion: string, reason?: string }`
- `createdAt: number`

Rules:

- Owner read/list only.
- Owner create only when `ownerId` matches the path owner, action is Deepen-only, target is a v1 save target, `citations` is a list, and GUARDIAN is marked passed.
- Updates are denied; saved outputs are immutable after creation.
- Owner delete is allowed so users can remove private saves.

## Indexes

No composite index is added for Wave 1 A2. The v1 contract does not define a compound query for `momentSaves`; per-owner subcollection access and default single-field indexes are sufficient until integration code defines a concrete query shape.

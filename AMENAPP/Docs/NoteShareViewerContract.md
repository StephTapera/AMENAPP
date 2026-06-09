# NOTE_SHARE_VIEWER Wave 0 Contract

Frozen: 2026-06-09  
Version: `2026-06-09-wave0-v1`  
Swift contract: `AMENAPP/AMENAPP/Shared/Contracts/NoteShare.swift`  
Feature flag: `feature_note_share_viewer` default `false`

This is contract-only. Wave 0 does not implement callable functions, Firestore rules, routing handlers, analytics emitters, HTML demos, or UI.

## Existing Surfaces Inspected

- Church Notes documents live at `churchNotes/{noteId}`. Existing media-processing services call Church Notes functions and read/write processing subcollections.
- Existing Church Notes comments live under `churchNotes/{noteId}/comments`, but this feature uses `noteShares/{shareId}/reflections` so public note-share discussion does not expose source-note collaboration comments.
- Existing Firestore rules already include Church Notes ownership/collaborator helpers and post visibility rules that reference `followers` plus follower-edge checks.
- Existing share backend patterns live in `Backend/functions/src/share/smartShare.ts`, including share permission enforcement, deep link generation, delivery, and privacy-safe share event tracking.
- Existing deep links use `amen://...` app links and `https://amenapp.com/...` fallbacks.
- Existing Liquid Glass code lives in `AIIntelligence/LiquidGlass/CommunicationOSGlassKit.swift` plus broader Liquid Glass helpers. There is no standalone `GlassKit.swift` in the project navigator today.

## Firestore Schema

```text
noteShares/{shareId}
  noteId: string
  authorUid: string
  createdAt: Timestamp
  updatedAt: Timestamp
  status: "active" | "revoked"
  shareConfig: {
    visibility: "public" | "church" | "followers" | "link" | "space"
    spaceId: string?
    churchId: string?
    allowAmens: bool
    allowComments: "everyone" | "church" | "off"
    allowReshare: bool
    showCounts: bool
    authorPrivateAmenList: bool
    attribution: "full" | "firstName" | "anonymous"
    watermarkOnExport: bool
  }
  renderMode: "selah" | "postcard"
  linkToken: string?

noteShares/{shareId}/amens/{uid}
  createdAt: Timestamp

noteShares/{shareId}/reflections/{commentId}
  authorUid: string
  body: string
  createdAt: Timestamp
  parentId: string?
  status: "published" | "pending" | "removed"
  guardianVerdict: map
```

No aggregate amen counter document is allowed. Counts, if ever author-enabled, are computed server-side on demand through a callable. The public feed/viewer payload never includes amen counts, view counts, reaction counts, or amen lists.

## API Contracts

All callables are Auth + App Check gated. All permission-sensitive writes happen server-side. Client controls are UX only.

| Callable | Request | Response | Notes |
| --- | --- | --- | --- |
| `noteShareCreate` | `{ noteId, shareConfig, renderMode }` | `{ shareId, linkToken? }` | Caller must own or have share permission on the Church Note. Server resolves `churchId` for church visibility and issues `linkToken` only for link visibility. |
| `noteShareUpdateConfig` | `{ shareId, partialConfig }` | `{ shareId, shareConfig }` | Author only. Writes audit fields. Turning comments off hides reflections from non-authors but does not delete them. |
| `noteShareRevoke` | `{ shareId }` | `{ shareId, status: "revoked" }` | Author only. Voids/rotates link token and triggers fan-out to mark referencing pills unavailable. |
| `noteShareToggleAmen` | `{ shareId }` | `{ amened: bool }` | Enforces visibility and `allowAmens`. Idempotent toggle. Rate limit: 30/min/user. |
| `noteShareGetViewerPayload` | `{ shareId? , linkToken? }` | `NoteShareViewerPayload` | Single hydration call. Public projection never includes counts or amen lists. Author receives `authorPanel` only when authorized. |
| `noteShareListReflections` | `{ shareId, cursor? }` | `NoteShareReflectionPage` | Enforces visibility and comment visibility. Removed comments hidden from non-author/moderator. |
| `noteShareAddReflection` | `{ shareId, body, parentId? }` | `{ reflection }` | Enforces visibility, comment scope, one-level threading, GUARDIAN pre-publish, and rate limit: 10/min/user. |

Request/response type names are frozen in `Shared/Contracts/NoteShare.swift`.

## Firestore Rules Delta

Rules are deny-by-default. Add these in Wave 1 after callables exist:

```text
match /noteShares/{shareId} {
  allow get: if signed in, status active, and visibility scope is satisfied;
  allow list: if false;
  allow create, update, delete: if false; // callables only

  match /amens/{uid} {
    allow get: if request.auth.uid == uid;
    allow list: if false;
    allow create, delete: if request.auth.uid == uid
      && parent share is active
      && parent shareConfig.allowAmens == true
      && requester satisfies visibility scope;
    allow update: if false;
  }

  match /reflections/{commentId} {
    allow get: if parent share is active
      && requester satisfies visibility scope
      && (status == "published" || requester is author/moderator || authorUid == request.auth.uid);
    allow list: if callable-backed query scope is enforced;
    allow create, update, delete: if false; // callable moderation path only
  }
}
```

Link-only shares are not directly readable by rules. `linkToken` hydrates exclusively through `noteShareGetViewerPayload` so tokens never grant raw query access.

Reserved indexes:

| Collection | Fields | Purpose |
| --- | --- | --- |
| `noteShares` | `authorUid ASC`, `createdAt DESC` | Author share management. |
| `noteShares` | `noteId ASC`, `status ASC`, `createdAt DESC` | Per-note active share list and revocation fan-out. |
| `noteShares/{shareId}/reflections` | `status ASC`, `createdAt ASC` | Published reflection pagination. |

## Design Tokens

Add tokens to the active AMEN Liquid Glass design layer in Wave 1/2:

| Token | Purpose |
| --- | --- |
| `note.canvas.cream` | Warm editorial viewer canvas, light mode. |
| `note.serif.display` | Large New York/system serif display title style. |
| `note.eyebrow.caps` | Status dot + uppercase metadata line. |
| `note.row.capsule` | Quiet gray index/reflection row capsule. |
| `note.pill.glyph` | Note glyph used inside the post-card pill. |

## GlassKit Component Contract

Implement in the active AMEN Liquid Glass kit, currently `AIIntelligence/LiquidGlass/CommunicationOSGlassKit.swift` unless Wave 1 introduces a canonical `GlassKit.swift`:

```swift
NotePill(title:context:state:onTap:)
```

States: `available`, `unavailable`, `loading`. The component participates in the caller's `GlassEffectContainer`. It must use the existing no-glass-on-glass rule: when embedded on an already-glass post card, render as a solid material-elevated capsule rather than nested blur.

## Routing Contract

Canonical app route:

```text
amen://note-share/{shareId}
```

Canonical universal link:

```text
https://amenapp.com/n/{linkToken}
```

| State | Behavior |
| --- | --- |
| Flag off | Do not open the viewer; route to neutral unavailable/fallback state. |
| Authorized active share | Open Shared Note Viewer. |
| Unauthorized | Show quiet private/permission state and emit privacy-safe denied analytics. |
| Revoked/deleted | Show quiet unavailable state. |
| Network failure with cached preview | Render cached pill/preview and offer retry. |

## Analytics Contract

Allowed events:

| Event | Notes |
| --- | --- |
| `note_share_created` | Aggregate-only, no raw content. |
| `note_viewer_opened` | Include result only: opened, denied, unavailable, offline_cached. |
| `amen_toggled` | Include result only: amened or unamened. |

Do not log raw note text, reflection text, target UID, view counts, public like counts, amen list, comment counts, display names, emails, phone numbers, or un-hashed IDs.

## Human Decision Checkpoints

1. Followers visibility: existing rules reference follower visibility and follower checks, but Wave 1 must confirm the production follower edge path and whether this means one-way or mutual followers.
2. Signed-out link access: unresolved. Current frozen default is signed-in only for v1, matching Auth + App Check callable posture.
3. Church audience predicate: unresolved. Church OS must name the authoritative membership/role collection for `visibility == church`.

# Church Discovery Phase 2

## Scope

Phase 2 extends the existing AMEN Find Church flow without replacing it.

- Search, list, map, and navigation remain in `AMENAPP/FindChurchView.swift`.
- Tapped church detail still routes into `ChurchDetailExperience.swift`.
- The new work adds Apple Maps-style discovery-sheet behavior, richer Firestore-backed church intelligence, and backend callable stubs.

## Firestore Schema

### `churches/{churchId}`

- `id`
- `name`
- `type`
- `address`
- `city`
- `state`
- `latitude`
- `longitude`
- `phone`
- `websiteUrl`
- `heroImageUrl`
- `logoUrl`
- `about`
- `denomination`
- `verified`
- `accessibility`
- `serviceTimes`
- `livestreamUrl`
- `createdAt`
- `updatedAt`

### `churches/{churchId}/media/{mediaId}`

- `id`
- `imageUrl`
- `type`: `hero | interior | worship | exterior | community`
- `source`: `church | user | admin`
- `approved`
- `createdAt`
- `updatedAt`

### `churches/{churchId}/live_state/current`

- `state`: `live | upcoming | closed | quiet | unknown`
- `title`
- `description`
- `startsAt`
- `endsAt`
- `livestreamUrl`
- `attendanceSignal`
- `atmosphereTags`
- `confidence`
- `updatedAt`

### `churches/{churchId}/experience_summary/current`

- `parking`
- `bestArrivalTime`
- `entrance`
- `serviceLength`
- `worshipStyle`
- `kidsMinistry`
- `accessibility`
- `translation`
- `quietSpace`
- `firstTimeFlow`
- `confidence`
- `updatedAt`

### `users/{uid}/church_fit/{churchId}`

- `score`
- `confidence`
- `reasons`
- `disclaimers`
- `updatedAt`

### `users/{uid}/church_smart_actions/{churchId}`

- `primaryAction`
- `secondaryActions`
- `reason`
- `updatedAt`

### `users/{uid}/church_discovery_state/main`

- `recentSearches`
- `recentChurchIds`
- `savedIntents`
- `preferredChips`
- `updatedAt`

## Cloud Functions

Phase 2 callable stubs live in `Backend/functions/src/churchDiscoveryPhase2.ts`.

- `refreshChurchLiveState`
- `generateChurchExperienceSummary`
- `calculateChurchFitScore`
- `resolveChurchSmartAction`
- `generateBereanChurchSuggestions`

Current behavior:

- App Check is enforced in production callable flows.
- Church lookups validate `churchId`.
- No function fabricates a live service.
- Fit score language is preference alignment only.
- Missing data falls back to `"Not enough data yet"` or `"Not confirmed yet"`.
- Emulator mode skips App Check enforcement for local testing.

## Security Rule Recommendations

Recommended Firestore access policy:

- Public read: approved church profile fields in `churches/{churchId}`.
- Public read: approved church media in `churches/{churchId}/media/{mediaId}` where `approved == true`.
- Public read: `churches/{churchId}/live_state/current`.
- Public read: `churches/{churchId}/experience_summary/current`.
- User-only read/write: `users/{uid}/church_fit/{churchId}`.
- User-only read/write: `users/{uid}/church_smart_actions/{churchId}`.
- User-only read/write: `users/{uid}/church_discovery_state/main`.
- Admin-only write: canonical church metadata and approved media.
- Admin or Cloud Functions write: generated intelligence documents for live state and experience summary.

Illustrative rule shape:

```text
match /churches/{churchId} {
  allow read: if true;
  allow write: if isAdmin();

  match /media/{mediaId} {
    allow read: if resource.data.approved == true;
    allow write: if isAdmin();
  }

  match /live_state/{docId} {
    allow read: if true;
    allow write: if isAdmin() || isServer();
  }

  match /experience_summary/{docId} {
    allow read: if true;
    allow write: if isAdmin() || isServer();
  }
}

match /users/{uid} {
  allow read, write: if request.auth.uid == uid;

  match /church_fit/{churchId} {
    allow read, write: if request.auth.uid == uid;
  }

  match /church_smart_actions/{churchId} {
    allow read, write: if request.auth.uid == uid;
  }

  match /church_discovery_state/{docId} {
    allow read, write: if request.auth.uid == uid;
  }
}
```

## Integration Notes

- `FindChurchView.swift` now owns:
  - bottom-sheet state
  - search focus expansion
  - smart discovery chips
  - recents and Berean suggestions
- `ChurchDataService.swift` owns:
  - live state listener
  - experience summary listener
  - media listener
  - fit score listener
  - smart action listener
  - discovery state persistence
  - Berean suggestion loading
- `ChurchDetailExperience.swift` consumes the richer Phase 2 streams and degrades safely when documents are absent.

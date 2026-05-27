# Selah Firestore Schema

Contract version: `2026-05-25-v1`

## `reflections/{reflectionId}`

Owner-authored journal entries. Private by default.

Fields:
- `id: string`
- `ownerUid: string`
- `verseId?: string`
- `translation?: "KJV" | "ESV"`
- `body: string` max 8000 chars
- `safetyTheme: SelahSafetyTheme`
- `shareScope: "justMe" | "accountabilityPartner" | "namedGroup"`
- `sharedWithUid?: string` required only for `accountabilityPartner`
- `sharedWithGroupId?: string` required only for `namedGroup`
- `isShareEligible: boolean` false for `selfHarm`, `abuse`, `trafficking`, `coercion`
- `relationalSignals.prayedByGroupCount: number`
- `relationalSignals.lastPrayerAt?: timestamp`
- `createdAt: timestamp`
- `updatedAt: timestamp`

Ownership: `ownerUid` is immutable after create. Clients may create/update their own reflections only. Scoped shares are explicit fields; there is no public scope.

Indexes:
- `ownerUid ASC, updatedAt DESC`
- `sharedWithUid ASC, updatedAt DESC`
- `sharedWithGroupId ASC, updatedAt DESC`
- `ownerUid ASC, verseId ASC, updatedAt DESC`

## `studySheetCache/{cacheKey}`

Server-owned cache for `bereanStudySheet` responses.

Cache key: `{translation}_{verseId}_{promptVersion}` with non-alphanumeric verse characters normalized to `_`.

Fields:
- `id: string`
- `verseId: string`
- `translation: "KJV" | "ESV"`
- `response: BereanStudySheetResponse`
- `promptVersion: string`
- `createdAt: timestamp`
- `expiresAt: timestamp`

Ownership: Cloud Functions only. Clients may read authenticated cache documents but cannot write them.

TTL: enable Firestore TTL on `expiresAt`. Recommended retention is 30 days for normal sheets and shorter when prompt versions are under active evaluation.

Indexes:
- `verseId ASC, translation ASC, promptVersion ASC`
- `expiresAt ASC`

## `guidedSessions/{sessionId}`

Resumable guided Selah flow state.

Fields:
- `id: string`
- `ownerUid: string`
- `verseId: string`
- `translation: "KJV" | "ESV"`
- `currentStep: "read" | "listen" | "understand" | "reflect" | "pray" | "apply" | "complete"`
- `completedSteps: string[]`
- `reflectionId?: string`
- `cachedStudySheetKey?: string`
- `recentThemes: SelahSafetyTheme[]`
- `startedAt: timestamp`
- `updatedAt: timestamp`
- `completedAt?: timestamp`

Ownership: `ownerUid` is immutable after create. Client may update progress for own sessions; AI/cache fields should be written by function-mediated flows when generated.

Indexes:
- `ownerUid ASC, updatedAt DESC`
- `ownerUid ASC, currentStep ASC, updatedAt DESC`
- `ownerUid ASC, verseId ASC, updatedAt DESC`

## `verseThemeTags/{tagId}`

Classifier cache for Selah Lens action ordering.

Tag ID: `{translation}_{verseId}_{promptVersion}`.

Fields:
- `id: string`
- `verseId: string`
- `translation: "KJV" | "ESV"`
- `theme: SelahSafetyTheme`
- `confidence: number` 0...1
- `promptVersion: string`
- `updatedAt: timestamp`

Ownership: Cloud Functions only. Authenticated clients may read.

Indexes:
- `verseId ASC, translation ASC, promptVersion ASC`
- `theme ASC, confidence DESC`

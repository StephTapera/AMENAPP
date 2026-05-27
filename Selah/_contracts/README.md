# Selah Contracts

Contract version: `2026-05-25-v1`

These files are the locked dependency surface for the Selah Bible Engine. UI and backend feature work should import these contracts instead of redefining model shapes.

## Files

- `SelahContracts.swift` — Swift `Codable` models for the iOS app.
- `selahContracts.ts` — TypeScript request/response and Firestore document types for Cloud Functions.
- `firestore.schema.md` — collection fields, ownership, indexes, and TTL notes.
- `firestore.rules` — Selah-specific Firestore rules snippet to merge into `AMENAPP/AMENAPP/firestore.deploy.rules` before deployment.
- `firestore.rules.test.ts` — emulator tests for private reflections, scoped sharing, and server-owned caches.
- `ButtonInventory.md` — required ledger for every new interactive Selah control.

## Swift Types Other Agents Import

- `SelahSafetyTheme`
- `SelahTranslation`
- `SelahVerseReference`
- `BereanStudySheetRequest`
- `BereanStudySheetResponse`
- `BereanStudySheetLayers`
- `BereanStudySheetTextLayer`
- `BereanKeyTerm`
- `BereanStudySheetContextLayer`
- `BereanStudySheetInterpretationLayer`
- `BereanInterpretiveOption`
- `BereanStudySheetApplicationLayer`
- `BereanStudySheetProvenance`
- `ClassifyVerseThemeRequest`
- `ClassifyVerseThemeResponse`
- `SelahLensActionKind`
- `ClassifySafetyRequest`
- `ClassifySafetyResponse`
- `SelahSupportPayload`
- `SelahResourceLink`
- `SelahReflectionShareScope`
- `SelahReflectionDocument`
- `SelahRelationalSignals`
- `GuidedSelahStep`
- `GuidedSelahSessionDocument`
- `SelahVerseThemeTagDocument`
- `SelahStudySheetCacheDocument`

## TypeScript Types Other Agents Import

Import from `Selah/_contracts/selahContracts.ts`:

- `SelahSafetyTheme`
- `SelahTranslation`
- `SelahLensActionKind`
- `BereanStudySheetRequest`
- `BereanStudySheetResponse`
- `ClassifyVerseThemeRequest`
- `ClassifyVerseThemeResponse`
- `ClassifySafetyRequest`
- `ClassifySafetyResponse`
- `SelahReflectionDocument`
- `GuidedSelahSessionDocument`
- `SelahVerseThemeTagDocument`
- `SelahStudySheetCacheDocument`
- `safetyThemeBlocksGeneration(theme)`
- `assertNoScriptureTextInStudySheet(response)`

## Non-Negotiable Scripture Rule

`bereanStudySheet` receives `verseText` as input, but `BereanStudySheetResponse` has no field that can carry scripture text. Cross references are `verseId` strings only. Client surfaces must resolve all scripture text from the trusted Firestore scripture store.

## Safety Rule

`selfHarm`, `abuse`, `trafficking`, and `coercion` route to grounding, trusted-human prompts, and resources. They are not eligible for AI devotional generation or sharing.

# AI Backend Ownership Map (Phase P1-1 / P1-8)

This is the canonical map of which backend codebase owns each AI feature
in the Amen app. It exists because two Firebase Functions codebases ship
to the same project:

| Codebase | Source path             | `firebase.json` codebase |
|----------|-------------------------|--------------------------|
| Modern   | `Backend/functions/src` | `creator`                |
| Legacy   | `functions/`            | `default`                |

Both deploy alongside each other today. When two callables share a name
across codebases, the Firebase Functions runtime picks one and the other
becomes a silent no-op — historically a source of deployment ambiguity.

All AI callables in **both** codebases now enforce App Check (closed in
the prior session's Phase 1). Phase P1-1 / P1-8 closes the
*ownership* ambiguity by naming exactly one canonical owner per feature
and marking the other as `@deprecated`.

## Canonical map

| AI feature                | Canonical owner                                      | iOS caller                                  | Legacy duplicate (deprecated)                          | Sunset plan |
|---------------------------|------------------------------------------------------|---------------------------------------------|--------------------------------------------------------|-------------|
| Berean chat (non-stream)  | `Backend/functions/src/bereanChatProxy.ts`           | `ClaudeService.swift` (non-stream path)     | —                                                      | n/a          |
| Berean chat (SSE stream)  | `Backend/functions/src/bereanChatProxyStream.ts`     | `ClaudeService.swift` (stream path)         | —                                                      | n/a          |
| Berean Pulse              | `Backend/functions/src/bereanPulse.ts`               | `BereanPulseService.swift`                  | —                                                      | n/a          |
| Berean structured response| `Backend/functions/src/berean/controllers/generateStructuredResponse.ts` | `BereanAPIClient.swift` | — | n/a |
| Daily verse               | `Backend/functions/src/generateDailyVerse.ts`        | `DailyVerseGenkitService.swift`             | —                                                      | n/a          |
| Hey Feed NL preferences   | `Backend/functions/src/feedIntelligence/*`           | `HeyFeedNLPreferencesService.swift`         | `functions/heyfeedFunctions.js` (×4) + `functions/src/heyFeed/callable.ts` (×4) | retire after deploy cycle |
| Whisper / transcribe      | `Backend/functions/src/whisperProxy.ts`              | `WhisperVoiceService.swift` (and the new `BereanVoiceInputSheet`) | `functions/openAIFunctions.js:30` (`whisperProxy`), `:62` (`transcribeAudio`) | retire after deploy cycle |
| OpenAI generic proxy      | `Backend/functions/src/openAIProxy.ts`               | (legacy iOS — being replaced)               | `functions/openAIFunctions.js:9` (`openAIProxy`)       | retire after deploy cycle |
| Smart suggestions         | `Backend/functions/src/openAIProxy.ts` (covers same model surface) | (legacy iOS)                  | `functions/openAIFunctions.js:117` (`smartSuggestionsProxy`) | retire after deploy cycle |
| Voice prayer comments     | `Backend/functions/src/voicePrayerComments.ts`       | `VoicePrayerCommentsSection.swift`          | —                                                      | n/a          |
| Selah media               | `Backend/functions/src/selahMedia.ts`                | `SelahService.swift`                        | —                                                      | n/a          |
| Walk With Christ          | `Backend/functions/src/spiritualOS.ts`               | `WalkWithChristViewModel.swift`             | —                                                      | n/a          |
| Church Notes audio        | `Backend/functions/src/churchNotes/churchNotesAudioProcessing.ts` | `ChurchNotesMediaProcessingService.swift` | `functions/aiChurchNotes.js` (untyped variants) | retire after deploy cycle |
| Church Notes OCR          | `Backend/functions/src/churchNotes/churchNotesImageOCR.ts` | `ChurchNotesMediaProcessingService.swift` | — | n/a |
| Church Notes content gen  | `Backend/functions/src/churchNotes/churchNotesContentGeneration.ts` | `ChurchNotesMediaProcessingService.swift` | — | n/a |
| Think-First validator     | `Backend/functions/src/thinkFirst/validateThinkFirstCheck.ts` | `ThinkFirstServerValidator.swift` | — | n/a |
| Sermon week plan          | (none — Berean utility flow) | `SermonWeekTransformationService.swift` | `functions/bereanFunctions.js:851` (`bereanSermonWeekPlan`) | retire after deploy cycle |
| Spiritual graph analysis  | (none — Berean utility flow) | `PersonalSpiritualGraphService.swift`       | `functions/bereanFunctions.js:923` (`bereanSpiritualGraphAnalysis`) | retire after deploy cycle |
| Seasonal prompt           | (none — Berean utility flow) | `SeasonalPromptService.swift`               | `functions/bereanFunctions.js:976` (`bereanSeasonalPrompt`) | retire after deploy cycle |
| AI prompt features ×5     | (none — Berean utility flow) | (various)                                   | `functions/aiPromptFeatures.js` (`vibeMatch`, `digestBrain`, `spiritGraph`, `testimonyResonanceScore`, `livingWordEngine`) | retire after deploy cycle |
| Prayer recap              | (none — Berean utility flow) | `BereanFeatureService.swift`                | `functions/bereanFeaturesFunctions.js:280` (`generatePrayerRecap`) | retire after deploy cycle |
| Trust intelligence        | `Backend/functions/src/trustIntelligence.ts`         | `TrustScoreService.swift`                   | —                                                      | n/a          |
| Media moderation pipeline | `Backend/functions/src/mediaModerationPipeline.ts`   | (server-triggered)                          | —                                                      | n/a          |

## Deprecation contract

Every legacy callable above that is marked **"retire after deploy cycle"**
has, as of this Phase, a JSDoc `@deprecated` annotation pointing at its
canonical owner. The annotation:

1. Is loud enough that a future developer reading the file knows not to
   add new code to it.
2. Is picked up by ESLint / TypeScript / IDE tooling, which surfaces
   warnings at the call site if any iOS or backend code reaches into a
   deprecated callable through a typed wrapper.
3. Does **not** remove the callable. Removal is a separate deployment
   action that requires:
   - confirming no iOS build references the deprecated callable name,
   - deploying with `firebase deploy --only functions:<canonical>` to
     ensure the canonical takes precedence,
   - then removing the legacy export and redeploying.

## Static test contract

`Backend/functions/src/__tests__/aiBackendOwnership.static.test.ts`
locks the structure of this map in place. The test fails if:

- a legacy file removes its `@deprecated` annotation without removing
  the file itself;
- a canonical owner file disappears or is renamed (so iOS callers
  silently fall back to the legacy implementation);
- a new legacy AI callable is added to `functions/` without a
  corresponding `@deprecated` annotation pointing at a canonical owner.

## Retirement runbook (post-launch)

When a deploy window opens, execute in this order per callable:

1. Grep the iOS source for the legacy callable name. If any reference
   exists in active code paths (not test fixtures), STOP — first
   migrate the iOS caller to the canonical name.
2. Remove the `exports.<name> = onCall(...)` block from the legacy
   `functions/*.js` file.
3. Update `aiBackendOwnership.static.test.ts` to remove the row for
   that callable.
4. Run `npm run build && npm test` in both `Backend/functions` and
   `functions` to confirm nothing depends on the removed callable.
5. Deploy: `firebase deploy --only functions:default,functions:creator`.
6. Smoke-test the canonical owner end-to-end from iOS.

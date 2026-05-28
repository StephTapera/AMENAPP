# Amen Smart Message Intelligence Post-GO Hardening Audit

## Verdict

GO

The post-GO hardening pass found client-side production risks around render-time detection cost, feature-flag shutdown behavior, EventKit denial handling, and Unicode entity range correctness. These were fixed without adding new features, redesigning UI, weakening rules, or removing Smart Message functionality.

## Files Reviewed

- `AMENAPP/SmartMessageIntelligence/SmartMessageHostIntegration.swift`
- `AMENAPP/SmartMessageIntelligence/SmartMessageEntityHighlighter.swift`
- `AMENAPP/SmartMessageIntelligence/SmartMessageActionMenu.swift`
- `AMENAPP/SmartMessageIntelligence/AmenSmartMessageIntelligenceService.swift`
- `AMENAPP/SmartMessageIntelligence/AmenSpaceSemanticSearchView.swift`
- `AMENAPP/SmartMessageIntelligence/PrayerRequestFromMessageView.swift`
- `AMENAPP/SmartMessageIntelligence/SmartPrayerActionSheet.swift`
- `AMENAPP/SmartMessageIntelligence/SmartDiscussionSummaryCard.swift`
- `AMENAPPTests/SmartMessageHostIntegrationTests.swift`
- `Backend/functions/src/smartMessageIntelligence/semanticSearch.ts`
- `Backend/functions/src/smartMessageIntelligence/smartMessageRouter.ts`
- `Backend/functions/src/smartMessageIntelligence/security.static.test.ts`
- `Docs/AmenSmartMessageVectorSearchSetup.md`
- Wired host surfaces listed in `Docs/AmenSmartMessageIntelligenceFinalReport.md`

## Issues Found By Severity

### High

- Feature flag kill switch was incomplete in host rendering: actions were hidden, but smart highlighter detection/rendering could still run. Fixed by rendering plain selectable `Text` when `smartMessageIntelligenceEnabled` is off.
- Unicode scripture/reference ranges used regex UTF-16 offsets as character offsets, which could mis-highlight text after emoji or non-ASCII characters. Fixed by converting regex matches through Swift `String.Index` character distances.

### Medium

- Local entity detection could run repeatedly during SwiftUI re-rendering on long threads. Fixed with an in-memory bounded detection cache.
- Very long messages could incur unnecessary regex work. Fixed with an 8,000-character local detection cap.
- Duplicate callable invocations could occur when the same action request is triggered concurrently. Fixed with in-flight callable coalescing in `AmenSmartMessageIntelligenceService`.
- Calendar/reminder permission denial could be treated like success because EventKit boolean results were ignored. Fixed by checking granted/denied explicitly and surfacing denial guidance.

### Low

- Empty entity overlays could still attach a transparent menu layer. Fixed by only rendering the tap layer when entities exist.
- Smart action menus could grow from repeated entities in dense messages. Fixed by de-duplicating and capping host action rows.

## Fixes Applied

- Added bounded local detection cache and long-message cap.
- Made Smart Message host rendering fully respect the global kill switch.
- Made local detection respect per-system flags for scripture, event, prayer, and topic extraction.
- Converted local regex ranges to Unicode-safe character offsets.
- Added duplicate callable coalescing for concurrent identical service requests.
- Added explicit EventKit denial states for calendar and reminder actions.
- Avoided transparent entity tap overlays for messages with no detected entities.
- Added focused tests for Unicode ranges and detection cache stability.

## Audit Results

- Performance on long threads: improved; render-time detection is cached, capped, and local.
- Entity detection latency and caching: improved with bounded in-memory cache.
- Duplicate backend calls from scrolling/re-rendering: no render-time backend calls found; action-driven duplicate calls are coalesced.
- Rate-limit behavior under rapid message activity: backend rate limits remain intact; client coalescing reduces duplicate pressure.
- App Check/auth failures: service maps provider failures into structured user-facing errors without content logging.
- Prayer/privacy leakage: no auto-save; prayer confirmation flow remains explicit; analytics does not log prayer text.
- Calendar/reminder denial: fixed with explicit denial messages.
- Voice transcription failure states: provider output is required; invalid/empty output throws instead of inventing text.
- Keyword fallback labeling: present in Space search and local fallback surfaces.
- Accessibility: selectable text, native Menu/ConfirmationDialog/Sheet patterns, labels and hints remain in place.
- Feature flags: global and per-system flags now suppress local host intelligence work.
- Analytics: reviewed; no sensitive message/prayer/transcript payloads are logged.
- Offline/poor network: core reading remains local; callable failures surface through structured errors.
- Long scripture/reference edge cases: Unicode offset bug fixed; long-message scan capped.
- Message layout regression risk: reduced by falling back to plain `Text` when disabled and avoiding empty overlays.

## Tests Run

- Xcode build: passed.
- Focused iOS tests: 8 passed, 0 failed.
  - `scriptureDetectionCreatesScriptureActions`
  - `dateDetectionCreatesCalendarAndReminderActions`
  - `prayerDetectionRequiresConfirmationAction`
  - `topicDetectionCreatesSearchStudyGraphActions`
  - `unicodeScriptureRangesUseCharacterOffsets`
  - `detectedScriptureReferencesParseForSelahReader`
  - `smartSearchRankingModeLabelsVectorAndFallbackHonestly`
  - `repeatedDetectionUsesStableCachedEntities`
- Backend focused Smart Message tests: 16 passed, 0 failed.
- Backend validation: `npm run typecheck`, `npm run build`, and `npm run lint -- --quiet` passed.
- Firebase Functions deploy: `backfillSmartMessageVectorIndex`, `getSmartMessageVectorIndexStatus`, and `scheduledSmartMessageVectorBackfill` verified in the live function list.
- Firebase Functions artifact cleanup: `gcf-artifacts` cleanup policy updated to delete old Cloud Run function images after 1 day.
- Smart Message dead/demo scan: no `TODO`, `FIXME`, `placeholder`, `mock`, `demo`, `no-op`, `print(`, or inert smart action branches found.

## Remaining Risks

- No unaddressed production-hardening issues remain from this pass.
- Local detection cache is process-memory only by design to avoid persisting sensitive message/prayer text outside existing message storage.
- Calendar/reminder flows intentionally stage detected text for user review and never auto-create items.
- Vector search is now production-wired through a Firebase-native path: Vertex AI embeddings plus Firestore vector fields and nearest-neighbor search. Existing content has manual and scheduled backfill coverage. Keyword fallback remains explicitly labeled for empty indexes or transient provider/index failures.
- Rollout monitoring records safe operational metrics only; raw message, prayer, transcript, body, and summary fields are filtered before analytics writes.

## Production Rollout Recommendation

Smart Message Intelligence is on by default. Keep the existing remote-config keys available for emergency rollback and monitor callable error rates, rate-limit events, action tap/confirm ratios, transcription failure rate, and client performance metrics on long Amen Space threads. `smart_message_intelligence_enabled` remains the top-level rollback switch.

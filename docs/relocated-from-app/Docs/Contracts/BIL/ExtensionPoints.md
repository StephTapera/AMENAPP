# BIL Extension-Point Map

Frozen: 2026-06-11  
Version: `bil-wave0-v1`

These are the only approved touchpoints for Wave 2+ implementation. Cross-lane changes outside this map require an ARCH contract amendment.

## Berean Chat Streaming and Realtime

Approved touchpoints:

| Surface | Existing path/name | Allowed BIL use |
| --- | --- | --- |
| Chat callable/typewriter | `UnifiedChatView.swift` `BereanStreamingService.stream(prompt:onToken:)`; callable `bereanChatProxy` | BI-12 scratchpad metadata, BI-14 progressive Markdown buffering, BI-14 stop-and-steer continuation envelope. Do not rewrite the callable/typewriter pipeline. |
| Realtime sessions | `BereanRealtimeSessionManager.createSession`, `listen`, `endCurrentSession`; callable `createRealtimeSession` | Attach BIL mode/session metadata only through new optional payload fields. |
| Realtime WebSocket | `BereanRealtimeWebSocketTransport.connect`, `sendJSON`, `appendInputAudio`, `commitInputAudio`, `requestResponse`, `persistTranscriptChunk` | BI-12 sanitized progress labels and BI-11 safety audit result attachment. No raw Tier P logging. |
| Realtime services | `BereanLiveTranscriptService.start`, `BereanTranslationCoordinator.translate`, `BereanScriptureResolutionEngine.resolve`, `BereanRealtimeModerationService.validateTranscript`, `persistApprovedChunk` | Source-card extraction and scripture references after existing moderation paths approve chunks. |

Finding: no active first-party SSE/EventSource client is present. The contract phrase `SSE streaming` maps to the current callable-plus-typewriter chat path and the WebSocket realtime path.

## Memory, Retrieval, and Vector Search

Approved touchpoints:

| Surface | Existing path/name | Allowed BIL use |
| --- | --- | --- |
| RAG/vector search | `AmenAIFeaturesService.ragSearch(query:scope:)`; callable `ragSearch`; `RAGSearchScope` | BI-01 L2 recall and BI-04 source lookup for Tier S/C only. |
| Conversation memory search | `ConversationMemorySearchViewModel.search()`; callable `searchConversationMemory` | BI-01 targeted recall and BI-02 provenance lookup. |
| Conversation memory save | `BereanCommunicationHubView.saveMemoryFromText`, `loadRecentMemories`; callable `saveConversationMemory`; Firestore `threads/{threadId}/memories` | BI-01 episode save/offload and BI-02 ledger provenance references, only if tier permits. |
| Ministry memory | `AmenConnectSpacesPhase0BindingService.searchMinistryMemory(spaceId:query:limit:)`; callable `searchMinistryMemory` | BI-05 Space-shared Context Package recall where Space permissions allow it. |

Finding: `LivingMemoryService.swift` says LivingMemory was removed/discontinued. BIL contracts must use the active RAG/conversation-memory surfaces above, not a nonexistent `LivingMemoryService` type.

## Hey Feed, Preferences, and Digest Inputs

Approved touchpoints:

| Surface | Existing path/name | Allowed BIL use |
| --- | --- | --- |
| Natural-language preferences | `HeyFeedNLPreferencesService.applyIntent`, `rankingDelta`, `pruneExpired`; Firestore `users/{uid}/feedNLPreferences` | BI-09 preference signals. Do not write BIL digest state into this collection. |
| Explicit feed prefs | `HeyFeedPreferencesService.setMode`, `toggleTopicPin`, `blockTopic`, `setDebateLevel`, `setSensitivityFilter`, `setRefreshPacing`, `recordMoreLikeThis`, `recordLessLikeThis`, `muteAuthor` | BI-09 signal read only. |
| Feed ranking | `HeyFeedAlgorithm.score`, `rank`, `shouldShowPost` | BI-09 can consume high-level topic/mode signals; it must not change feed ranking. |
| Daily digest | `DailyDigestService.fetchBrief(forceRefresh:)`; callable `callModelDailyBrief` | BI-09 can extend through a new callable or envelope, gated by `bil_briefing_memory`. |
| Berean Pulse | `BereanPulseService.loadToday`, `observeToday`, `updatePreferences`, `triggerOnDemandRefresh`, `track`; `BereanPulsePreference` | BI-09 may present digest cards through Pulse only behind flags. |

## Commitment Objects and Action Execution

Approved touchpoints:

| Surface | Existing path/name | Allowed BIL use |
| --- | --- | --- |
| Primitive models | `ActionIntelligenceSystem.swift` `AmenCommitmentObject`, `CommitmentObjectClass`, `AmenIntentKind`, `AmenActionSuggestion`, `AmenActionVerb` | BI-08 maps `CommitmentSuggestion` into existing primitive fields. |
| Local analyzer | `ActionIntelligenceEngine.analyze(source:)` | BI-08 deterministic/local extraction pass and sensitivity reuse. |
| Server action execution | `ActionIntelligenceService.execute(action:analysis:source:)`; callable `executeAmenAction` | BI-08 accepted suggestion conversion. |
| Context bridge | `CommitmentBridge.isBridgeable`, `makeCommitment(from:goalText:)`; flags `contextSystemEnabled`, `contextCommitmentBridgeEnabled` | Optional BI-08 bridge for Context System goals. |
| Action reminders | `ActionThreadModels.ActionReminder` and Action Thread services | Reminder scheduling only after conversion, not as a separate task system. |

## Aegis, GUARDIAN, and Safety

Approved touchpoints:

| Surface | Existing path/name | Allowed BIL use |
| --- | --- | --- |
| Aegis input/output gates | `AmenConnectSpacesPhase0BindingService.runAegisInputGate`, `runAegisOutputGate`; `AmenConnectSpacesAegisGateRequest`, `AmenConnectSpacesAegisGateDecision` | BI-11 safety critic and BI-07 mode sensitivity profile. |
| Content safety | `AmenContentSafetyService.quickCheck`, `checkContent`, `checkBeforePost`; callable `checkContentSafety` | BI-11 safety pass and BI-12 safe scratchpad suppression. |
| Berean context guardrails | `BereanContextCoordinator.addMedicalGuardrail`, `sanitizeCommunityContent`; `BereanOSBridgeObserver` notifications `amenOS.crisisDetected`, `amenOS.supportStateChanged` | BI-06/BI-11 high-stakes response handling. |
| Crisis precheck | `BereanStudyService.hasCrisisSignal` via public study methods; `CrisisDetectionService.shared.hasLocalCrisisSignal` | BI-06/BI-07 prayer and study mode escalation. |

GUARDIAN registration decision: no all-caps `GUARDIAN` type was found. BIL reserves capability ID `C59_BEREAN_MULTI_AGENT_ANSWER_AUDIT` and registers through the Aegis/content-safety extension points above unless a canonical GUARDIAN registry is introduced before Wave 2.

## EventKit

Approved touchpoints:

| Surface | Existing path/name | Allowed BIL use |
| --- | --- | --- |
| Calendar integration | `AmenCalendarService.requestAccess`, `addEvent`, `fetchEvents`, `removeEvent`; Remote Config `integration_calendar_enabled` | BI-08 schedule action after user confirmation. |
| Pulse permissions | `BereanPulsePermissionManager` | BI-09 calendar-related permission copy and status display only. |

BIL may not add new EventKit permissions or entitlements in Wave 0. Any Info.plist/privacy changes require explicit implementation wave review.

## Notification Trigger System

Approved touchpoints:

| Surface | Existing path/name | Allowed BIL use |
| --- | --- | --- |
| Post action reminders | `AmenPostActionTransformService.transformPost`, `scheduleLocalNotification`, `ensureNotificationPermission`, `cancelNotification` | BI-08 follow-up/schedule reminders after conversion. |
| Communication reminders | `BereanCommunicationHubView.scheduleLocalReminder`, `scheduleLocalReminderAt` | BI-08 thread reminders if the action remains inside Communication OS. |
| Daily digest notification | Existing app notification permission surfaces plus `DailyDigestService`/Berean Pulse | BI-09 optional notification after explicit digest opt-in. |

Finding: no single global notification trigger abstraction exists. BIL must use feature-local scheduling adapters until a canonical notification service exists.

## Remote Config and Feature Flags

Approved touchpoint: `AMENFeatureFlags` (`fetchRemoteConfig`, `buildDefaults`, `applyRemoteConfig`). Wave 2 may add `bil_*` properties only as listed in `FeatureFlags.md`. Server callables must enforce the same flags server-side.

## Forbidden Touches Without Contract Amendment

- GlassKit internals beyond adding approved BIL components after HTML demo approval.
- Tier S/C/P encryption boundaries.
- Existing Aegis safety decisions or moderation internals.
- Existing chat callable semantics except optional metadata envelopes for BI-12/14/15.
- Existing feed ranking behavior.
- Any server-side summarization/vector path for Tier P plaintext.

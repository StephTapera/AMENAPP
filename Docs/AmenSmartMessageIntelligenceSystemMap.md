# Amen Smart Message Intelligence System Map

## Existing Reusable Systems

- Messaging models and UI: `AppMessage`, `AmenMessagingIntelligenceCoordinator`, `AmenMessagingFeatureAvailability`, `MessageActionCluster`, `SmartThreadContextBar`, `ConversationMemorySearchView`, and CommunicationOS components under `AMENAPP/AMENAPP/AMENAPP/CommunicationOS`.
- Berean contextual actions: `BereanContextPayload`, `BereanContextAction`, `BereanContextActionEngine`, `BereanContextMenuManager`, `BereanFloatingActionTray`, and backend callable `routeBereanContextualAction`.
- Church Notes intelligence: Church Notes media processing models/services/views, semantic editor, AI draft review, and backend `Backend/functions/src/churchNotes`.
- Voice/audio: `VoicePrayer` client views, `AmenVoiceModules`, `BereanVoiceSessionManager`, `whisperProxy`, media transcription callables, and creator transcription utilities.
- Firebase security: root `firestore.rules`, `storage.rules`, App Check enforced callables, shared `rateLimit.ts`, server-owned generated data patterns.
- Analytics: `AMENAnalyticsService`, `AmenMessagingAnalytics`, CommunicationOS analytics events, Church Notes analytics extension.
- Feature flags: `AMENFeatureFlags` with Remote Config defaults and existing messaging, Berean, Church Notes, media, semantic, and knowledge graph flags.
- Search/indexing: Algolia sync, `AmenSemanticIntelligenceService`, `semanticIntelligence.ts`, `searchConversationMemory`, and Conversation Memory UI.

## New Client Files

- `AMENAPP/SmartMessageIntelligence/AmenSmartMessageModels.swift`
- `AMENAPP/SmartMessageIntelligence/AmenSmartMessageIntelligenceService.swift`
- `AMENAPP/SmartMessageIntelligence/SmartMessageEntityHighlighter.swift`
- `AMENAPP/SmartMessageIntelligence/SmartMessageActionMenu.swift`
- `AMENAPP/SmartMessageIntelligence/SmartMessageActionTray.swift`
- `AMENAPP/SmartMessageIntelligence/SmartDiscussionSummaryCard.swift`
- `AMENAPP/SmartMessageIntelligence/SmartDiscussionInsightSheet.swift`
- `AMENAPP/SmartMessageIntelligence/SmartPrayerActionSheet.swift`
- `AMENAPP/SmartMessageIntelligence/PrayerRequestFromMessageView.swift`
- `AMENAPP/SmartMessageIntelligence/SmartStudyModeView.swift`
- `AMENAPP/SmartMessageIntelligence/SmartStudySessionViewModel.swift`
- `AMENAPP/SmartMessageIntelligence/AmenSpaceSemanticSearchView.swift`
- `AMENAPP/SmartMessageIntelligence/AmenKnowledgeGraphView.swift`
- `AMENAPP/SmartMessageIntelligence/AmenKnowledgeGraphService.swift`

## New Backend Module

- `Backend/functions/src/smartMessageIntelligence/types.ts`
- `Backend/functions/src/smartMessageIntelligence/validators.ts`
- `Backend/functions/src/smartMessageIntelligence/scriptureDetection.ts`
- `Backend/functions/src/smartMessageIntelligence/dateEventDetection.ts`
- `Backend/functions/src/smartMessageIntelligence/prayerDetection.ts`
- `Backend/functions/src/smartMessageIntelligence/topicExtraction.ts`
- `Backend/functions/src/smartMessageIntelligence/discussionSummary.ts`
- `Backend/functions/src/smartMessageIntelligence/contextualBereanActions.ts`
- `Backend/functions/src/smartMessageIntelligence/semanticSearch.ts`
- `Backend/functions/src/smartMessageIntelligence/studyMode.ts`
- `Backend/functions/src/smartMessageIntelligence/voiceIntelligence.ts`
- `Backend/functions/src/smartMessageIntelligence/knowledgeGraph.ts`
- `Backend/functions/src/smartMessageIntelligence/smartMessageRouter.ts`
- `Backend/functions/src/smartMessageIntelligence/index.ts`

## Firestore Paths

- `users/{uid}/smartMessageMemory/{nodeId}`
- `users/{uid}/smartMessageActions/{actionId}`
- `spaces/{spaceId}/members/{uid}`
- `spaces/{spaceId}/smartThreads/{threadId}/messages/{messageId}`
- `spaces/{spaceId}/smartThreads/{threadId}/insights/{insightId}`
- `spaces/{spaceId}/smartThreads/{threadId}/entities/{entityId}`
- `spaces/{spaceId}/smartThreads/{threadId}/studySessions/{sessionId}`
- `spaces/{spaceId}/knowledgeGraph/nodes/{nodeId}`
- `spaces/{spaceId}/knowledgeGraph/edges/{edgeId}`
- `spaces/{spaceId}/prayerRequests/{requestId}`
- `spaces/{spaceId}/semanticIndex/items/{itemId}`

## Callable Names

- `analyzeSmartMessage`
- `detectScriptureReferences`
- `detectSmartDateEvents`
- `detectPrayerRequest`
- `summarizeDiscussion`
- `getContextualBereanActions`
- `extractDiscussionTopics`
- `semanticSearchAmenSpace`
- `startSmartStudyMode`
- `transcribeVoiceMessage`
- `buildKnowledgeGraphMemory`

## Feature Flags

- `smartMessageIntelligenceEnabled`
- `scriptureDetectionEnabled`
- `smartEventDetectionEnabled`
- `prayerIntelligenceEnabled`
- `discussionSummariesEnabled`
- `contextualBereanActionsEnabled`
- `topicExtractionEnabled`
- `semanticSearchEnabled`
- `studyModeEnabled`
- `voiceIntelligenceEnabled`
- `knowledgeGraphMemoryEnabled`

Remote Config keys use snake case equivalents.

## Privacy Assumptions

- AI-generated insights, entities, semantic index rows, and generated graph nodes are server-owned.
- User memory is owner-only.
- Space intelligence is member-readable only.
- Prayer requests require explicit user confirmation and visibility choice.
- Voice transcription requires user action or a future explicit space setting; auto-transcription remains off by default.
- Semantic search uses keyword/token fallback unless vector infrastructure is explicitly integrated.

## Remaining Risks

- The project has multiple historical backend roots. This implementation targets canonical `Backend/functions` and root `firestore.rules`.
- Existing Space membership schema was not clearly present in root rules; this adds `spaces/{spaceId}/members/{uid}` and also tolerates `memberIds` on the space document server-side.
- No provider-backed discussion summarizer is added here; summaries are conservative extractive summaries until an approved AI provider is connected.

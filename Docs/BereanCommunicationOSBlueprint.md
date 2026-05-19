# Berean Communication OS Blueprint

## Product North Star

AMEN should not become a corporate workspace or social feed. The communication layer should feel like a spiritually intelligent operating system: quiet, spatial, emotionally safe, retrieval-first, and deeply respectful of context.

The system architecture below extends the existing `BereanPulse`, `ActionThread`, `Covenant`, `ChurchNotes`, and Firebase layers already present in the codebase.

## 1. Full UX Architecture

### Primary surfaces

| Surface | Purpose | Existing AMEN anchor |
| --- | --- | --- |
| Home Communion Surface | Unified daily communication overview: priority threads, prayer follow-ups, digest, presence | `AmenCovenantHomeView`, `BereanPulseView` |
| Study Rooms | Scripture-first collaboration rooms with deep threads and saved branches | `CovenantRoomDetailView`, `BereanPulseCardDetailView` |
| Prayer Threads | Sensitive support conversations with escalation and follow-up | `ActionThread*`, `AmenPrayerFollowUpCard` |
| Reflection Threads | Slow conversations around testimonies, church notes, or spiritual stories | `ChurchNotes`, `Covenant` |
| Memory & Retrieval | Global semantic search, recall, recap, saved moments | new OS layer |
| Command Layer | Universal jump/search/action surface | new OS layer |
| Digest Layer | AI catch-up, unresolved needs, daily/weekly summaries | extends `BereanPulse` |

### Information architecture

- Left mental model on iPhone: `Home`, `Rooms`, `Prayer`, `Memory`, `You`.
- Center mental model inside each surface: active thread/feed.
- Context layer: bottom composer, top scope bar, pull-up memory/search sheet, transient right-side detail on iPad.
- Sacred pacing: interaction hierarchy favors reflection, not volume.

## 2. Navigation System

### Navigation model

- `NavigationStack` for linear depth.
- Context overlays for thread details, scripture previews, participant state, saved references.
- Floating composer anchored as a bottom accessory surface.
- Universal quick switcher available from search field, keyboard shortcut, and long-press gesture.

### Spatial states

- `Resting`: content-first.
- `Focused`: single thread or study branch expanded.
- `Overlay`: command palette, search, scripture sheet, prayer escalation sheet.
- `Continuity`: resume banner for handoff sessions or drafts.

### Back behavior

- Back returns to prior context scope, not just previous screen.
- If entered from search, back returns to results with preserved filters.
- If entered from a digest card, back restores scroll position and highlighted thread.

## 3. Data Model Schemas

### Core entities

```swift
struct CommunicationThread {
    let id: String
    let kind: ThreadKind
    let rootContext: RootContext
    let title: String
    let summary: String?
    let participants: [ParticipantSnapshot]
    let presenceSummary: PresenceSummary
    let memoryState: MemoryState
    let moderationState: ModerationState
    let lastActivityAt: Date
    let unreadCount: Int
    let priorityScore: Double
}

enum ThreadKind: String, Codable {
    case prayer
    case scriptureStudy
    case reflection
    case carePlan
    case groupRoom
    case directMessage
}

struct CommunicationMessage {
    let id: String
    let threadId: String
    let authorId: String
    let body: String
    let kind: MessageKind
    let quotedMessageId: String?
    let parentMessageId: String?
    let rootMessageId: String
    let scriptureRefs: [String]
    let attachmentRefs: [String]
    let reactions: [ReactionAggregate]
    let aiAssist: MessageAssist?
    let sentAt: Date
    let editedAt: Date?
}
```

### Supporting entities

- `PresenceSignal`
- `DigestSnapshot`
- `ThreadMemoryDocument`
- `SemanticChunk`
- `NotificationDecision`
- `ContinuationSession`
- `ModerationAssessment`
- `ScheduledMessage`
- `PinnedArtifact`
- `PrayerEscalationState`

## 4. Firestore Structure

### Top-level collections

```text
users/{userId}
users/{userId}/presence/{presenceId}
users/{userId}/notificationPreferences/{prefId}
users/{userId}/continuations/{sessionId}
users/{userId}/drafts/{draftId}
users/{userId}/memoryIndex/{memoryId}

threads/{threadId}
threads/{threadId}/messages/{messageId}
threads/{threadId}/branches/{branchId}
threads/{threadId}/participants/{userId}
threads/{threadId}/pins/{pinId}
threads/{threadId}/artifacts/{artifactId}
threads/{threadId}/digests/{digestId}
threads/{threadId}/moderation/{assessmentId}

searchQueries/{queryId}
presenceSessions/{sessionId}
notificationDecisions/{decisionId}
semanticEmbeddings/{embeddingId}
continuitySessions/{sessionId}
```

### Denormalized indexes

- `users/{userId}/threadMemberships/{threadId}`
- `users/{userId}/priorityFeed/{itemId}`
- `users/{userId}/pendingPrayerNeeds/{needId}`
- `users/{userId}/digestQueue/{digestId}`

### Notes

- Keep existing `posts/{postId}/actionThreads/{threadId}` for current support workflows.
- Add a bridging field from `ActionThread` to `threads/{threadId}` when a care workflow becomes a full communication thread.
- All thread writes should be server-authoritative for membership, moderation, and escalation state.

## 5. AI Orchestration Architecture

### Services

- `ThreadOrchestrator`
- `DigestOrchestrator`
- `MemoryRetrievalOrchestrator`
- `ModerationOrchestrator`
- `PresenceInferenceOrchestrator`
- `NotificationDecisionEngine`

### Cloud Functions layout

```text
functions/src/threads/
functions/src/digests/
functions/src/memory/
functions/src/moderation/
functions/src/notifications/
functions/src/continuity/
```

### Request flow

1. Client submits event to Firestore or callable function.
2. Cloud Function validates App Check, auth, membership, rate limits.
3. Event is normalized into orchestration queue.
4. AI policy layer selects model/tooling.
5. Output is scored for confidence and sensitivity.
6. Server writes structured result plus human-readable surface copy.

### Principles

- AI suggests, never silently impersonates.
- Sensitive categories require higher thresholds.
- Summaries and recall always include confidence and timestamp context.

## 6. Liquid Glass Rendering System

### Updated Apple-aligned rule

Use Liquid Glass primarily for:

- command bars
- bottom composers
- navigation chrome
- floating tool clusters
- transient overlays

Use standard materials for:

- main content cards
- message bodies
- study summaries
- prayer thread surfaces

### Material hierarchy

- `Glass / clear`: only over visually rich media or hero states.
- `Glass / regular`: command palette, floating composer, palette actions.
- `Material / ultraThin-thin-regular`: content grouping.
- Edge diffusion: subtle stroke, low-opacity highlight, not neon.

## 7. SwiftUI Component Architecture

### New component families

- `BereanCommunicationHubView`
- `CommunicationScopeBar`
- `PresenceHaloView`
- `SacredCommandPaletteView`
- `ThreadSummaryCard`
- `PrayerEscalationCard`
- `ScriptureReferenceCluster`
- `MemoryRecallSheet`
- `DigestCatchUpCard`
- `ContinuityBannerView`
- `SpatialComposerBar`

### View model families

- `CommunicationHubViewModel`
- `ThreadViewModel`
- `MemorySearchViewModel`
- `PresenceStatusViewModel`
- `NotificationInboxViewModel`

### Service families

- `CommunicationThreadService`
- `CommunicationSearchService`
- `PresenceInferenceService`
- `ContinuationService`
- `DigestService`

## 8. Interaction Behavior Specifications

### Thread behavior

- Tap thread: open focused thread state.
- Swipe right on message: quote reply.
- Long press: react, pin, save to prayer, turn into journal, ask Berean deeper.
- Pull thread header: reveal summary, participants, unresolved requests.
- Tap scripture chip: expand inline scripture preview, then full study sheet.

### Healthy engagement rules

- No public like counts as primary emphasis.
- Reactions stay compact and non-competitive.
- Threads collapse low-value chatter by default.
- Prayer chains expose needs, not social score.

## 9. Animation Specifications

### Motion language

- Response: `0.28 - 0.36` spring range.
- Damping: `0.78 - 0.86`.
- Long surfaces use fade + lift, not bounce.
- Presence pulse cadence: under 1.2s and only on meaningful change.

### Spatial transitions

- Command palette materializes from top or center.
- Composer morphs from dormant capsule to expanded input dock.
- Thread branches expand with depth fade and slight z-offset simulation.
- Reduced motion swaps springs for opacity and scale under `0.02`.

## 10. Accessibility Behaviors

- VoiceOver labels include thread type, urgency, unresolved items, unread count.
- Prayer urgency must never rely on color alone.
- Dynamic Type support for all primary surfaces.
- Reduce Transparency switches glass surfaces to higher-opacity materials.
- Reduced Motion disables morphing and velocity-reactive responses.
- Haptics are soft and optional, not required for state comprehension.

## 11. Notification Orchestration System

### Priority tiers

- Tier 1: direct prayer escalation, moderator intervention, urgent follow-up.
- Tier 2: direct mention, coordinator request, scheduled prayer reminder.
- Tier 3: digest-worthy updates, passive reactions, non-urgent room activity.

### Decision model

`priorityScore = urgency + relationshipWeight + emotionalWeight + recencyWeight - interruptionCost`

### Delivery modes

- Real time
- Bundled digest
- Quiet delivery
- Escalation routing

### Safeguards

- Rate limit by person, thread, and emotional category.
- Collapse repeated updates into one thread summary.
- Respect inferred prayer/study/focus modes.

## 12. Presence System Architecture

### Presence states

- `Praying`
- `Studying`
- `Reflecting`
- `Quiet`
- `In church`
- `Available for prayer`
- `Deep study`

### Inputs

- active surface
- dwell time
- thread type
- calendar hint
- optional coarse location
- optional motion state

### Privacy model

- Inference happens on-device when possible.
- Shared presence is coarse and user-editable.
- Sensitive context never exposes raw location or calendar details.

## 13. Search/Retrieval Architecture

### Retrieval targets

- messages
- prayers
- scripture references
- journals
- study rooms
- attachments
- digests

### Query modes

- keyword
- semantic
- person-filtered
- time-bounded
- thread-scoped

### Ranking

`rank = semanticSimilarity + relationshipWeight + recencyCurve + sacredImportanceBoost + confidenceScore`

## 14. Moderation Architecture

### Layers

- pre-send guidance
- send-time policy evaluation
- post-send anomaly detection
- crisis risk routing

### Behaviors

- toxicity prevention suggestions
- emotionally heated wording softeners
- vulnerable prayer handling
- auto-throttling for repeated conflict
- human moderation queue for high-risk cases

## 15. AI Memory Architecture

### Memory pipeline

1. Message or note is chunked.
2. Chunk is classified by type and sensitivity.
3. Embedding is generated server-side.
4. Metadata is stored with relational anchors.
5. Important moments are promoted to memory graph.

### Memory types

- explicit saves
- inferred milestones
- unresolved prayer needs
- scripture anchors
- recurring themes

## 16. Cross-Device Continuity System

### Persisted continuity

- active thread
- last read message
- draft state
- active branch
- open scripture preview
- command palette context

### Behavior

- iPhone to iPad resumes exact thread depth.
- Handoff banner offers resume, not force-open.
- Drafts sync with conflict-safe timestamp merging.

## 17. Spatial Interaction Model

- Surfaces are layered by importance, not stacked arbitrarily.
- Thread expansion feels like stepping deeper into one sacred space.
- Overlays dim context lightly, never blackout unless crisis sheet is active.
- Tool clusters float; content rests.

## 18. Production Rollout Strategy

### Phase 1

- Ship new command palette.
- Ship unified communication home.
- Add reactions, quoted replies, pins, scheduled send.

### Phase 2

- Introduce semantic memory and global retrieval.
- Add digest engine and continuity sessions.
- Add notification intelligence.

### Phase 3

- Add advanced presence inference.
- Add full prayer escalation and moderation intelligence.
- Add spatial thread branches and study rooms.

## 19. Performance Optimization Strategy

- Use snapshot listeners only for active thread scope.
- Paginate old messages and lazy-load branches.
- Precompute digest summaries server-side.
- Keep embedding generation off main interaction path.
- Use standard materials for content to limit expensive effects.
- Constrain glass containers to local tool clusters, not full-screen spans.

## 20. Go/No-Go Audit Checklist

- Does the system preserve AMEN’s calm spiritual tone?
- Is Liquid Glass limited to functional chrome and overlays?
- Can users find a prayer, message, or scripture naturally?
- Are unresolved prayer needs visible without becoming performative?
- Do notifications reduce anxiety instead of increasing it?
- Does reduced motion and reduced transparency remain fully usable?
- Are presence signals privacy-safe and user-editable?
- Are moderation and crisis pathways server-authoritative?
- Do drafts, read positions, and thread states continue across devices?
- Is every AI-generated summary attributable, timestamped, and confidence-scored?

## Implementation Priorities For This Codebase

1. Reuse `ActionThread` as the care-workflow backbone rather than replacing it.
2. Expand `BereanPulse` into the digest and proactive intelligence layer.
3. Evolve `AmenCovenantHomeView` into a calmer unified communication home.
4. Add a standalone communication OS surface first, then progressively route existing rooms and prayer flows into it.
5. Keep Firebase security rules strict around presence, memory, prayer escalation, and moderation data.

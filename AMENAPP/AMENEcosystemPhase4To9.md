# AMEN Ecosystem Phase 4-9

This phase extends the current AMEN architecture into a calm spiritual operating layer. It preserves the existing white Liquid Glass church discovery system and keeps all intelligence grounded, quiet, and trust-first.

## 1. Updated Firestore Architecture

### Spiritual graph
- `spiritual_graph/users/{uid}`
- `spiritual_graph/churches/{churchId}`
- `spiritual_graph/edges/{edgeId}` or batched storage under `spiritual_graph/edges/items/{edgeId}`

### Spiritual memory
- `users/{uid}/spiritual_memory/{memoryId}`

Fields:
- `type`
- `source`
- `tags`
- `createdAt`
- `confidence`
- `visibility`
- `derivedInsights`

### Affinity state
- `users/{uid}/spiritual_graph_state/affinity`

### Presence
- `users/{uid}/presence_preferences/main`
- `users/{uid}/presence_signals/{signalId}`

### Trust and councils
- `verified_ministries/{ministryId}`
- `verified_pastors/{pastorId}`
- `trusted_organizations/{orgId}`
- `moderation_councils/{councilId}`
- `moderation_queue/{itemId}/appeals/{appealId}`

### Berean operating layer
- `users/{uid}/berean_operating_context/current`
- `churches/{churchId}/quality/current`
- `churches/{churchId}/approved_transcripts/{transcriptId}`
- `events/{eventId}/verified_context/current`

## 2. Spiritual Graph Schema

Nodes:
- user
- church
- ministry
- event
- studyInterest
- worshipStyle
- servicePattern
- volunteerActivity
- savedContent
- prayerInterest

Edges:
- attends
- saved
- visited
- interested
- studies
- volunteers
- watches
- participates
- serves
- connectedTo

Rules:
- no public spiritual scoring
- no popularity boards
- no vanity metrics
- graph is personalization-only

Graph outputs:
- church affinity
- worship similarity
- community overlap
- ministry relevance
- local spiritual ecosystem clustering

## 3. Berean Operating-Layer Architecture

Swift:
- [BereanOperatingLayer.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanOperatingLayer.swift)
- [BereanChurchGroundingService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanChurchGroundingService.swift)
- [SpiritualGraphService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SpiritualGraphService.swift)
- [SpiritualGraphModels.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SpiritualGraphModels.swift)

Backend:
- [bereanOperatingLayer.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Backend/functions/src/berean/bereanOperatingLayer.ts)

Pipeline:
1. Assemble user-approved memory, church context, event context, media context, and study context.
2. Restrict grounding to verified church metadata, approved media, official websites, approved transcripts, service schedules, livestream metadata, and user-approved memory.
3. Score confidence and attach source attribution.
4. Return a calm answer with `Not confirmed yet` fallback when grounding is weak.

## 4. Spatial / VisionOS Preparation Layer

Swift:
- [SpiritualGraphModels.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SpiritualGraphModels.swift)
- [AmenAdvancedLiquidGlassSystem.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AmenAdvancedLiquidGlassSystem.swift)

Prepared surfaces:
- floating church cards
- immersive worship previews
- spatial prayer maps
- ambient overlays
- contextual Berean surfaces

Design constraints:
- minimal layering
- reverent motion
- no gimmick transitions
- calm, white, low-noise material behavior

## 5. Presence Intelligence Architecture

Swift:
- [AmbientPresenceIntelligence.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AmbientPresenceIntelligence.swift)

Backend:
- [presenceIntelligence.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Backend/functions/src/presence/presenceIntelligence.ts)

Inputs:
- schedule windows
- proximity
- quiet mode
- worship-aware suppression
- travel-aware suppression
- signal-specific confidence

Outputs:
- calm presence signals
- infrequent notification requests
- confidence-gated notification candidates

## 6. Notification Intelligence System

Use the existing notification stack as the delivery layer and add:
- presence-driven signal generation
- confidence thresholds by sensitivity mode
- suppression during travel and quiet windows
- emotionally safe defaults
- capped fan-out

Notification policy:
- optimize for usefulness and clarity
- do not optimize for session time
- prefer fewer, stronger notifications

## 7. Trust and Moderation Architecture

Continue the Phase 3 trust foundation and add:
- verified ministries
- verified pastors
- trusted organizations
- moderation councils
- appeals subflows
- church impersonation prevention
- AI transparency audit trail

Swift:
- [TrustInfrastructureService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/TrustInfrastructureService.swift)

## 8. Ethical AI Safeguards

Principles:
- no manipulation loops
- no engagement addiction goals
- no spiritual superiority framing
- no private-memory use without user-approved visibility
- no fabricated church claims
- transparent AI disclosure
- confidence explanations

Safety checks:
- low-confidence answer fallback
- source-only claims
- quiet-mode notification suppression
- memory export and delete support
- audit logging for moderation and verification actions

## 9. Scalability Recommendations

- keep graph edge writes append-friendly and batch compaction offline
- maintain denormalized affinity snapshots for client reads
- use single-document current-state reads for quality, presence prefs, and Berean context
- scope listeners to active surfaces only
- batch moderation review and graph recomputation
- support offline cache for saved churches, memory, and low-frequency presence preferences
- keep provider sync and event ingestion asynchronous and queue-backed
- plan region-aware replication for church/media/notification pipelines

## 10. Updated Admin Systems

Admins should now support:
- church admin content review
- ministry verification
- pastor verification
- moderation appeals
- council escalation
- organization management
- audit exports

## 11. QA and Safety Validation

- verify spiritual graph data never surfaces as public score
- verify spiritual memory stays private by default
- verify delete/export support works for memory records
- verify low-confidence Berean answers render safe fallback language
- verify quiet mode suppresses presence notifications
- verify travel-aware suppression works
- verify worship-aware suppression works during church-service windows
- verify trusted ministry and pastor flows preserve audit history
- verify no regressions to current Find Church, church detail, or Liquid Glass behavior

## 12. Documentation Updates

This document is the Phase 4-9 reference.

Phase 3 reference remains:
- [ChurchDiscoveryPhase3.md](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchDiscoveryPhase3.md)

## 13. Final System Diagrams

### Diagram A — Spiritual graph
```text
User
  -> attends / visits / saves -> Church
  -> studies -> StudyInterest
  -> volunteers / serves -> Ministry
  -> participates -> Event
  -> saves -> Content
  -> connectedTo -> PrayerInterest
```

### Diagram B — Berean operating layer
```text
Approved Memory
Verified Church Metadata
Approved Media
Official Website
Service Schedule
Livestream Metadata
        |
        v
Berean Context Assembly
        |
        v
Grounding + Confidence + Attribution
        |
        v
Calm Response / Not Confirmed Yet Fallback
```

### Diagram C — Presence intelligence
```text
Schedule + Proximity + Quiet Mode + Travel State + Confidence
        |
        v
Presence Signal Filter
        |
        v
Calm Notification Candidate
        |
        v
User-facing Surface or Suppression
```

### Diagram D — Trust infrastructure
```text
Verification Queues + Moderation Queue + Appeals + Audit Logs
        |
        v
Council / Admin Review
        |
        v
Reversible Decision + Transparency Record
```

## 14. Summary of New Files, Components, Services, and Functions

Swift:
- [SpiritualGraphModels.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SpiritualGraphModels.swift)
- [SpiritualGraphService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SpiritualGraphService.swift)
- [AmbientPresenceIntelligence.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AmbientPresenceIntelligence.swift)
- [BereanOperatingLayer.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanOperatingLayer.swift)
- [AmenAdvancedLiquidGlassSystem.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AmenAdvancedLiquidGlassSystem.swift)
- [TrustInfrastructureService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/TrustInfrastructureService.swift)

Backend:
- [spiritualGraph.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Backend/functions/src/spiritualGraph/models/spiritualGraph.ts)
- [SpiritualGraphService.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Backend/functions/src/spiritualGraph/services/SpiritualGraphService.ts)
- [presenceIntelligence.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Backend/functions/src/presence/presenceIntelligence.ts)
- [bereanOperatingLayer.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Backend/functions/src/berean/bereanOperatingLayer.ts)
- [amenPhase4To9.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Backend/functions/src/amenPhase4To9.ts)

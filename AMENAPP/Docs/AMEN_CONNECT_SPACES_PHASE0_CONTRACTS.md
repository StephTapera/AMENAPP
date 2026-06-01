# AMEN Connect + AMEN Spaces — Phase 0 Frozen Contracts

Status: FROZEN  
Version: 2026-06-01-v1  
Owner: Lead Orchestrator  
Swift contract: `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/ConnectSpacesPhase0Contracts.swift`

Any contract change requires a Lead Orchestrator edit in this document and the Swift contract, then rebroadcast to every active agent. Agents may consume these contracts but must not edit them.

## 1. Design Tokens

Frozen token names:

| Token | Value | Purpose |
| --- | --- | --- |
| `amenGold` | `#D9A441` | Primary warm accent and candlelight highlight |
| `amenPurple` | `#6E4BB5` | Royal and liturgical accent |
| `amenBlue` | `#245B8F` | Depth, trust, and calm system state |
| `amenBlack` | `#070607` | Matte ground for scripture, messages, and media |

Rules:

- Scripture, message bodies, and primary video content are matte, never glass.
- Backgrounds are deep black or clean white.
- Liquid Glass belongs only on controls and chrome: floating navigation, switchers, drawers, summary panels, media controls, command bars, search bars, and preview overlays.
- SwiftUI implementations use native iOS 26 `.glassEffect`, `GlassEffectContainer`, and system glass button styles where appropriate.
- Limit concurrent glass effects for performance.
- All animation routes through `Motion.adaptive` or the local equivalent with reduce-motion handling.

## 2. Firestore Data Contracts

Project stack: `amen-5e359` using Firestore, Cloud Functions v6 callable proxies, App Check + Auth gates, Pinecone with per-user and per-space namespace isolation, Algolia, Anthropic Claude and OpenAI through server-side proxy only. No client-side model keys.

### `spaces/{spaceId}`

| Field | Type | Owner |
| --- | --- | --- |
| `name` | string | callable |
| `type` | enum `smallGroup|prayer|worship|missions|staff|cohort|accountability` | callable |
| `memberIds` | string[] | callable/server |
| `careSensitivity` | bool | callable/server |
| `createdBy` | string | server |
| `createdAt` | timestamp | server |
| `updatedAt` | timestamp | server |

### `spaces/{spaceId}/messages/{msgId}`

| Field | Type | Owner |
| --- | --- | --- |
| `body` | string | callable |
| `authorId` | string | server |
| `detectedIntents` | enum[] | server |
| `convictionCheck` | object | server |
| `careRouted` | bool | server |
| `createdAt` | timestamp | server |
| `updatedAt` | timestamp | server |

`detectedIntents`: `prayerRequest`, `struggling`, `leadSunday`, `volunteerNeed`, `testimony`, `confession`, `grief`, `decision`, `task`, `risk`, `question`, `careFollowUp`.

`convictionCheck`: `enabled`, `suggestedPause`, `warningKinds`, `checkedAt`. Warning kinds: `gossip`, `slander`, `divisiveness`, `pii`, `phi`, `financial`.

### `spaces/{spaceId}/items/{itemId}`

Derived object types: `decision`, `task`, `risk`, `prayer`, `careFollowUp`, `serveSlot`.

Fields: `kind`, `title`, `owner`, `due`, `status`, `sourceMsgId`, `createdAt`, `updatedAt`.

### `presence/{userId}`

Fields: `spiritualState`, `urgentReachable`, `sabbathUntil`, `updatedAt`.

`spiritualState`: `inTheWord`, `inPrayer`, `fasting`, `sabbathRest`, `grieving`, `discerning`, `availableForUrgentPrayer`.

### `connectVideos/{videoId}`

Fields: `provenance`, `teacherId`, `transcriptRef`, `claims`, `scriptureRefs`, `sponsored`, `createdAt`, `updatedAt`.

`provenance`: `humanRecorded`, `aiEdited`, `aiGenerated`, `synthVoice`, `synthFace`, `deepfakeRisk`, `verifiedOriginal`.

`claims`: `id`, `text`, `timestampSeconds`, `sourceTranscriptRange`, `opposingFaithfulViews`.

`scriptureRefs`: every item must be provenance-verified through four layers: `canonicalReference`, `translationSource`, `contextWindow`, `bereanStudySheet`.

### `connectVideos/{videoId}/comments/{commentId}`

Fields: `type`, `body`, `authorId`, `edificationScore`, `createdAt`.

`type`: `question`, `correction`, `experience`, `citation`, `encouragement`, `respectfulDisagree`.

`edificationScore` is private and never displayed as a public vanity metric.

### `knowledgeGraph/{userId}`

Fields: `studied`, `understood`, `wrestlingWith`, `saved`, `nextUp`, `updatedAt`.

This is a formation graph, not watch history.

### `aegisFlags/{flagId}`

Fields: `capabilityRef`, `surface`, `severity`, `action`, `subjectRef`, `createdAt`.

`capabilityRef` must reference the frozen Aegis registry C1-C58.

## 3. Callable Proxy Contracts

All client model calls go through Cloud Functions v6 callable proxies with Auth and App Check.

Frozen callable names:

- `createMinistrySpace`
- `postMinistryMessage`
- `detectMessageIntents`
- `routeCareSignal`
- `updateSpiritualPresence`
- `runConvictionCheck`
- `runBeforeShareCheck`
- `fetchConnectVideoContext`
- `verifyScriptureProvenance`
- `recordKnowledgeGraphEvent`
- `scoreEdifyingComment`
- `runAegisInputGate`
- `runAegisOutputGate`
- `scanUploadForFamilySafety`
- `searchMinistryMemory`

## 4. Aegis Safety Contract

Every AI input and output on Spaces and Connect passes through Aegis C1-C58.

Hard rules:

- No scripture without four-layer provenance.
- Synthetic-media labels are non-removable.
- Care and crisis signals route to the Care queue and human resources; never AI-only handling.
- Child and family safety scan blocks before publish when C1-C13 risks are present.
- Conviction check is opt-in and never moralizing.
- Before-you-share warnings cover gossip, slander, divisiveness, PII, PHI, and financial data.
- Public vanity metrics are not shown.
- Infinite feed and addiction-loop mechanics are not allowed.

## 5. Orchestration Guardrails

Frozen guardrails:

- No `git reset --hard`.
- No broad `firebase deploy`; deploy only named functions or targets.
- One-finding -> one-fix -> one-verified-build loop.
- HTML prototype must pass human review before SwiftUI translation.
- Agents read frozen contracts; agents never edit frozen contracts.

## 6. Liquid Intelligence Seam

Teaching video becomes searchable ministry memory inside Spaces.

`searchMinistryMemory` must return:

- `videoId`
- `timestampSeconds`
- `transcriptExcerpt`
- `owner`
- `actionItemId`
- `confidence`

A valid integration test must prove a natural-language query returns an exact timestamp, transcript excerpt, owner, and action item from a real test video before Gate 4 is complete.

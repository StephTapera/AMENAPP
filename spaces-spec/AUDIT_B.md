# AUDIT_B.md — Agent B Gap Report

**Date:** 2026-05-28  
**Agent:** B — Chat Core

---

## 1. Berean Streaming Audit

**File:** `AMENAPP/AIIntelligence/BereanRealtimeWebSocketTransport.swift`

**Verdict: NOT reusable for Space chat streaming. Implement Firestore-based AsyncStream.**

Reasons:
- It is a **true WebSocket transport** (not SSE). It opens `URLSessionWebSocketTask` to `wss://api.openai.com/v1/realtime?model=...`.
- Tightly coupled to OpenAI Realtime API: sends `input_audio_buffer.append`, `response.create`, expects OpenAI token-stream event shapes.
- Manages audio backpressure (`maxBufferedAudioBytes = 384_000`), token-refresh logic, and retries — all AI-session-specific.
- There is **no reusable streaming primitive** to extract without deep modification.

**Decision:** Implement `FirestoreMessageStream` inside `SpacesChatViewModel` using `Firestore.addSnapshotListener` bridged to `@MainActor @Published` properties via `Task { @MainActor in … }`. Matches the pattern already in `SpacesService.swift` and `SpacesChatService.swift`. No second SSE/WebSocket implementation needed.

---

## 2. Existing Chat Layer Audit

**Directory:** `AMENAPP/Spaces/Chat/`

Four files already exist from a prior build pass:

| File | Status |
|---|---|
| `SpacesChatModels.swift` | Complete — `SpaceMessage`, `ThreadSummary`, `ThreadFilter`, `TypingIndicator`, `ReadState`, `MessageAttachment` |
| `SpacesChatService.swift` | Complete — `@MainActor`, Firestore listeners, reactions, typing RTDB, soft-delete, Berean invoke |
| `FilterTabData.swift` | Complete — `SpaceFilterTabData` + `makeAll` factory |
| `ThreadDetailView.swift` | Complete — full chat render surface with Liquid Glass tokens |
| `ThreadListView.swift` | Complete — thread list with filter tabs |

These files are **under `AMENAPP/Spaces/Chat/`** (not `AMENAPP/AMENAPP/Spaces/ChatCore/`). The spec targets `AMENAPP/AMENAPP/Spaces/ChatCore/`. Both paths are under the same workspace target.

**The ChatCore files are additive** — they expose the `SpaceFilterSignals` struct and `SpacesChatViewModel` against Agent A's `SpacesService.shared`, while the `Chat/` directory files serve the existing Spaces shell (Agent C).

---

## 3. CommunicationOS Model Conflicts

**File:** `AMENAPP/AMENAPP/AMENAPP/CommunicationOS/CommunicationOSModels.swift`

Contains: `ThreadDecision`, `ThreadQuestion`, `ThreadAction`, `GroupPulseData`, `SmartPresenceStatus` — AI intelligence overlay types, **not chat message models**. No name conflicts with `SpaceMessage`, `SpaceThread`, or `SpaceFilterSignals`.

**File:** `AMENAPP/AMENAPP/AMENAPP/ConversationOS/AmenConversationOSModels.swift`

Contains: `ConversationSummary`, `ConversationTopicCluster`, `ConversationPrioritySignal` — Conversation OS AI analysis types, **not transport models**. No conflicts.

**Verdict:** No conflicts. CommunicationOS and ConversationOS models operate at the AI analysis layer; ChatCore models operate at the transport/render layer.

---

## 4. RTDB Presence Paths

**File:** `AMENAPP/database.rules.json`

Existing presence path: `presence/{userId}` — does NOT exist.  
Existing typing path: `conversations/{conversationId}/typing/{userId}` — exists for legacy DMs.  
Existing online status: `online_status/{userId}` — exists.

**Decision:** Extend with a new top-level `typing` path:  
`typing/{spaceId}/{threadId}/{userId}: { userId, timestamp }`

This matches the path already implemented in `SpacesChatService.swift` (`rtdb.child("typing").child(spaceId).child(threadId).child(userId)`) and does NOT collide with the legacy `conversations/{id}/typing/{userId}` path.

No change to `database.rules.json` is required for v1 development (RTDB security rules for the `typing/` path will follow the same pattern as `conversations/{id}/typing`).

---

## 5. DM Strategy

**Decision: DMs = a Space with `type: .chat`, `accessPolicy: .free`, `members: [userA, userB]`**

The existing `ConversationOS/` directory contains an AI intelligence overlay (summaries, topic clusters, priority signals) that operates over an abstract `spaceId` + `threadId` pair — it does NOT contain a parallel DM storage schema.

The legacy RTDB `conversations/{conversationId}` path contains production DM data from the original AMEN messaging feature. Per `AGENT_B_chat_core.md §5`: if existing ConversationOS DM model has significant production data, do NOT migrate — bridge instead. A `DMBridgeService` can translate legacy `conversations/{id}` to the Space model at the view layer.

For **new DMs created via Spaces v2**: they are a `Space(type: .chat, accessPolicy: .free, members: [A, B])`. Same chat core renders both group channels and DMs. No parallel data model.

---

## 6. Design Token Audit

**File:** `AMENAPP/AMENAPP/AmenTheme.swift`

Defines all tokens: `AmenTheme.Colors.amenGold`, `amenPurple`, `amenBlue`, `amenBlack`, `surfaceCard`, `glassFill`, `glassStroke`, `shadowCard`, etc.

Also defines view modifiers: `.amenGlassCard()`, `.amenGlassInputBar()`, `.amenCard()`.

**Verdict:** `SpacesChatView.swift` must import from `AmenTheme` only. No local token literals.

---

## 7. Items Already Present — Not Rebuilt

| Item | Location | Action |
|---|---|---|
| `SpaceMessage` model | `AMENAPP/Spaces/Chat/SpacesChatModels.swift` | Reused by reference — not re-declared in ChatCore |
| `SpaceThread` model | `AMENAPP/AMENAPP/Spaces/SpacesModels.swift` | Already exists — not re-declared |
| `SpacesChatService` | `AMENAPP/Spaces/Chat/SpacesChatService.swift` | Reused — `SpacesChatViewModel` delegates to it |
| `ThreadFilter` | `AMENAPP/Spaces/Chat/SpacesChatModels.swift` | Reused — not re-declared |
| `SpaceFilterTabData` | `AMENAPP/Spaces/Chat/FilterTabData.swift` | Reused — `SpaceFilterSignals` is additive |
| Design tokens | `AMENAPP/AMENAPP/AmenTheme.swift` | Imported, not re-declared |
| RTDB typing write/read | `AMENAPP/Spaces/Chat/SpacesChatService.swift` | `SpacesTypingService` delegates to same RTDB paths |

---

## 8. Files to Implement

| File | Notes |
|---|---|
| `ChatCore/SpacesChatModels.swift` | `SpaceFilterSignals` struct only — `SpaceMessage`/`SpaceThread` already exist |
| `ChatCore/SpacesChatViewModel.swift` | `@MainActor ObservableObject` — delegates to `SpacesChatService.shared` |
| `ChatCore/SpacesChatView.swift` | Chat render surface Agent C embeds |
| `ChatCore/SpacesTypingService.swift` | Thin wrapper over RTDB typing path |
| `ChatCore/SpacesFilterService.swift` | Computes `SpaceFilterSignals` per-space |

---

AUDIT_B_COMPLETE

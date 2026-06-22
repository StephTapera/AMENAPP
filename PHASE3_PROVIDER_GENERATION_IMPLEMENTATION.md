# Phase 3: Provider-Backed Media Metadata Generation

## Overview

Phase 3 adds server-side AI generation of video captions and key moments for every video post
published on AMEN. It runs entirely in the background — users never wait for it.

```
User publishes video post
        │
        ▼
posts/{postId} created in Firestore
        │
        ▼ (gen2 Firestore trigger)
onPostCreatedGenerateMediaMetadata
        │
        ├─► Download video bytes from Firebase Storage
        │
        ├─► Whisper (OpenAI) → timed caption cues
        │         └─► Write captionTracks/generated-{mediaId}
        │
        ├─► Heuristic key-moment inference
        │         └─► Claude (optional) label refinement
        │         └─► Write keyMoments/{momentId}
        │
        └─► Update mediaMeta/{mediaId} states → "ready"
                  │
                  ▼ (Firestore listener in iOS app)
        MediaGenerationService.startPolling()
                  │
                  ▼
        onSuggestionsReady callback
                  │
                  ▼
        draft.applyGeneratedVideoSuggestions()
```

---

## Files

| File | Role |
|------|------|
| `Backend/functions/src/mediaGeneration/mediaMetadataPipeline.ts` | Pipeline trigger + callable |
| `Backend/functions/src/mediaGeneration/transcriptionProvider.ts` | OpenAI Whisper adapter |
| `Backend/functions/src/mediaGeneration/keyMomentInference.ts` | Heuristic + Claude inference |
| `AMENAPP/AMENAPP/MediaGenerationService.swift` | iOS Firestore polling + callback |
| `AMENAPP/AMENAPP/MediaMetadataDraftModels.swift` | Client draft models + merge-safe apply |

---

## Providers

### Transcription — OpenAI Whisper

- **Model**: `whisper-1`
- **Response format**: `verbose_json` with `timestamp_granularities[]: segment`
- **Domain prompt**: Faith-context prompt (<224 tokens) to improve scripture/church vocabulary recognition
- **Output**: Timed `TranscriptionCue[]` persisted as `captionTracks/generated-{mediaId}`
- **Required secret**: `OPENAI_API_KEY`

### Key-Moment Label Refinement — Anthropic Claude

- **Model**: `claude-haiku-4-5-20251001`
- **Role**: Replaces generic heuristic labels with short (2–5 word) specific titles
- **Example**: `"verse"` → `"Romans 8:28"`
- **Required secret**: `ANTHROPIC_API_KEY`
- **Optional**: If key is absent or Claude fails, heuristic labels are used unchanged

---

## Environment Variables / Secrets

Both secrets must be set as Firebase Secret Manager values (not `.env` files):

```bash
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set ANTHROPIC_API_KEY
```

Both are declared with `defineSecret()` and passed to function configs via the `secrets:` array.

To verify secrets exist:
```bash
firebase functions:secrets:access OPENAI_API_KEY
firebase functions:secrets:access ANTHROPIC_API_KEY
```

---

## Exported Cloud Functions (creator codebase)

### `onPostCreatedGenerateMediaMetadata`

| Property | Value |
|----------|-------|
| Type | gen2 Firestore trigger |
| Document | `posts/{postId}` |
| Event | `onDocumentCreated` |
| Timeout | 540 seconds (9 min — long Whisper jobs) |
| Memory | 512 MiB |
| Codebase | `creator` (`Backend/functions/`) |

**Behavior**:
1. Reads `mediaItems[]` from the new post document.
2. Filters to `type: "video"` items only. Skips clips shorter than 10 seconds.
3. Processes each video independently via `Promise.allSettled` — one failure cannot block others.
4. For each video: initialises `mediaMeta` doc → downloads bytes → transcribes → infers moments → persists results → marks `processingState: "ready"`.

### `retryMediaGeneration`

| Property | Value |
|----------|-------|
| Type | gen2 callable (`onCall`) |
| Auth | Required (`request.auth`) |
| Ownership check | Caller must own the post (`authorId == request.auth.uid`) |
| Timeout | 540 seconds |
| Memory | 512 MiB |
| Codebase | `creator` |

**Behavior**:
1. Validates caller is authenticated and owns the post.
2. Resets `captionsGenerationState` and `keyMomentsGenerationState` to `"queued"`.
3. Re-runs the full `processMediaItem` pipeline for the specified media item.

iOS call site in `MediaGenerationService`:
```swift
try await functions.httpsCallable("retryMediaGeneration").call([
    "postId": postId,
    "mediaId": mediaId,
])
```

---

## Pipeline Behavior

### Happy Path

```
mediaMeta/{mediaId}.processingState          → "processing" → "ready"
mediaMeta/{mediaId}.captionsGenerationState  → "generating" → "ready"
mediaMeta/{mediaId}.keyMomentsGenerationState → "generating" → "ready"

captionTracks/generated-{mediaId}  → created with segments[]
keyMoments/gen-intro               → created
keyMoments/gen-verse-{t}           → created (one per detected scripture ref)
keyMoments/gen-prayer-{t}          → created (one per detected prayer)
keyMoments/gen-reflection-{t}      → created
```

### Key Moment Heuristics

The heuristic always produces at least 1 moment (intro) and up to 6 total:

1. **Intro** — always at t=0
2. **Scripture references** — regex-detected book+chapter:verse citations, up to 4, spaced >=15s
3. **Prayer language** — detected phrases like "let us pray", "Father God", "in Jesus name"
4. **Main point** — temporal anchor at ~30% mark if fewer than 3 moments found
5. **Reflection** — temporal anchor at ~85% mark for videos >45s

All moments must be >=15 seconds apart. Output is sorted by time; `sortOrder` is reassigned.

---

## Failure Behavior (Degraded Mode)

Each step fails independently. A failure in one step never fails the post or blocks other steps.

| Failure | State written | Effect |
|---------|---------------|--------|
| `OPENAI_API_KEY` not set | `captionsGenerationState: "failed"`, `generationError: "provider_not_configured"` | No captions; key moments still attempted |
| Whisper API error | `captionsGenerationState: "failed"`, `generationError: "transcription_failed"` | No captions; key moments still attempted using duration-only heuristic |
| Download failure | Both states `"failed"`, `processingState: "failed"` | Both pipelines skipped |
| Claude unavailable | (no state change) | Heuristic labels used unchanged; `keyMomentsGenerationState: "ready"` |
| No moments detected | `keyMomentsGenerationState: "failed"` | Captions unaffected |

The iOS client interprets any combination of ready/failed states correctly:
- `captionsDone && momentsDone` → stops listening
- `anyFailed` → `pollState = .partiallyComplete`
- Both ready → `pollState = .complete`

---

## Merge Precedence Rules

Generated content never overwrites user-authored content. Enforced on both backend and client.

### Backend Merge Guards

1. **`userEditedMetadata == true`** on `mediaMeta/{mediaId}`: entire pipeline is skipped.
2. **Existing `source: "userEdited"` caption track**: caption write is skipped. `captionsGenerationState` is still set to `"ready"` so polling terminates correctly.
3. **Existing `source: "userEdited"` key moment**: all moment writes are skipped. `keyMomentsGenerationState` is still set to `"ready"`.

### Client Merge Guard

`CreatePostMediaMetadataDraft.applyGeneratedVideoSuggestions()` checks `videoDraft.userEdited` before applying. If the user has made any manual edits, the generated suggestions are silently discarded.

---

## Firestore Data Shape

### `posts/{postId}/mediaMeta/{mediaId}`

```json
{
  "mediaId": "abc123",
  "authorId": "uid_xyz",
  "type": "video",
  "processingState": "ready",
  "captionsGenerationState": "ready",
  "keyMomentsGenerationState": "ready",
  "userEditedMetadata": false,
  "updatedAt": "<serverTimestamp>"
}
```

### `posts/{postId}/mediaMeta/{mediaId}/captionTracks/generated-{mediaId}`

```json
{
  "captionTrackId": "generated-abc123",
  "language": "en",
  "source": "generated",
  "selectedCaptionStyle": "minimal",
  "displayByDefault": true,
  "generatedTranscript": "Full text of the transcript...",
  "editedTranscript": null,
  "segments": [
    { "cueId": "cue-0", "startTime": 0.0, "endTime": 4.2, "text": "Welcome to this study." },
    { "cueId": "cue-1", "startTime": 4.3, "endTime": 9.1, "text": "Today we look at Romans 8." }
  ],
  "lastEditedAt": null,
  "createdAt": "<serverTimestamp>"
}
```

### `posts/{postId}/mediaMeta/{mediaId}/keyMoments/gen-intro`

```json
{
  "momentId": "gen-intro",
  "time": 0,
  "label": "Intro",
  "kind": "intro",
  "source": "generated",
  "sortOrder": 0,
  "createdAt": "<serverTimestamp>"
}
```

`kind` values: `intro` | `mainPoint` | `verse` | `prayer` | `reflection` | `custom`

---

## iOS Client Integration

### Starting the Listener (after publish)

```swift
// In CreatePostView, after post is published:
Task {
    await MediaGenerationService.shared.startPolling(
        postId: publishedPostId,
        mediaId: videoMediaItem.id
    ) { suggestions in
        mediaMetadataDraft.applyGeneratedVideoSuggestions(
            cues: suggestions.cues,
            keyMoments: suggestions.keyMoments,
            featuredFrameTime: suggestions.featuredFrameTime
        )
    }
}
```

### Displaying Status

```swift
@StateObject private var generationService = MediaGenerationService.shared

// In body:
switch generationService.pollState {
case .polling:
    ProgressView("Generating captions...")
case .complete:
    Text("Captions and moments ready")
case .partiallyComplete:
    Text("Generation partially complete")
case .failed(let msg):
    Text("Generation unavailable: \(msg)")
case .idle:
    EmptyView()
}
```

### Retry

```swift
Button("Retry") {
    Task {
        try? await MediaGenerationService.shared.retryGeneration(
            postId: postId,
            mediaId: mediaId
        )
        await MediaGenerationService.shared.startPolling(
            postId: postId,
            mediaId: mediaId,
            onSuggestionsReady: { ... }
        )
    }
}
```

---

## Deploy Steps

```bash
# 1. Set secrets (first time only)
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set ANTHROPIC_API_KEY

# 2. Deploy the creator codebase
firebase deploy --only functions:creator

# 3. Verify functions exist in Cloud Console:
#    creator:onPostCreatedGenerateMediaMetadata
#    creator:retryMediaGeneration
```

Both functions live in the `creator` codebase (`Backend/functions/`), not the `default` codebase
(`functions/`). Always use `--only functions:creator` to deploy them.

### Verify After Deploy

1. Publish a test video post in the app.
2. Check Firestore: `posts/{postId}/mediaMeta/{mediaId}` — `processingState` should reach `"ready"` within ~30–60s for short clips.
3. Check `captionTracks/generated-{mediaId}` for `segments[]`.
4. Check `keyMoments/gen-intro` (and others) for moment docs.
5. In the app: post-publish screen should show "Generating captions..." then resolve.

### Verify Degraded Mode

1. Temporarily revoke `OPENAI_API_KEY` IAM access from the function (Cloud Console -> Secret Manager).
2. Publish a video post.
3. Confirm `captionsGenerationState: "failed"` and `generationError: "provider_not_configured"`.
4. Confirm `keyMomentsGenerationState` is still `"ready"` (heuristic ran without transcript).
5. Restore IAM binding.

### Verify Merge Protection

1. Publish a video post and wait for generation to complete.
2. Have the user manually edit captions in the UI (sets `userEditedMetadata: true` via `MediaMetadataPersistenceService`).
3. Trigger a retry via `retryMediaGeneration`.
4. Confirm function logs `Skipping {mediaId} — userEditedMetadata=true` and writes nothing.

---

## Known Constraints

- **Min duration**: Videos shorter than 10 seconds are skipped entirely.
- **Whisper file size**: Whisper API accepts files up to 25 MB. Very long videos may hit this; the pipeline marks `captionsGenerationState: "failed"` with `"transcription_failed"`.
- **Moment spacing**: Moments within 15 seconds of each other are deduplicated.
- **Claude label length**: Labels longer than 60 characters are rejected; the heuristic label is kept.
- **Trigger scope**: Only `type: "video"` media items are processed. Images and audio-only posts are skipped.

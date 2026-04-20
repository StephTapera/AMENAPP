# Next Phase Media Metadata Implementation

## 1. Architecture Overview

This phase extends the existing canonical post architecture instead of introducing a parallel media system.

- `Post` remains the canonical content root.
- `Post.mediaItems` carries persisted media metadata used directly by client rendering.
- `posts/{postId}/mediaMeta/{mediaId}` mirrors media metadata for backend processing and operational workflows.
- Comments remain tied to the canonical post thread.

## 2. Backend Schema Additions

Embedded in `PostMediaItem`:

- `captionTrack`
- `keyMoments`
- `frameCaptionMetadata`
- `audioBed`
- `featuredFrameTime`
- `previewURL`
- `originalURL`
- `processingStatus`
- `userEditedMetadata`

Mirrored backend paths:

- `posts/{postId}/mediaMeta/{mediaId}`
- `posts/{postId}/mediaMeta/{mediaId}/captionTracks/{trackId}`
- `posts/{postId}/mediaMeta/{mediaId}/keyMoments/{momentId}`

## 3. Functions / Jobs Added

`functions/mediaMetadataPipeline.js`

- `onPostMediaMetadataCreate`
- `onPostMediaMetadataUpdate`
- `onPostMediaMetadataDelete`

These triggers initialize and sync media metadata mirror documents from canonical `posts/{postId}.mediaItems`.

## 4. Upload-Time UI Flow

`CreatePostView` now opens `MediaMetadataAuthoringSheet` whenever the composer has:

- selected photo attachments
- witness video attachments

New authoring surfaces:

- `UploadCaptionEditorView`
- `UploadKeyMomentsEditorView`
- `FeaturedVideoFramePickerView`
- `PhotoModeFrameCaptionEditor`
- `FeaturedPhotoFramePickerView`

## 5. Processing State Lifecycle

Media processing states:

- `queued`
- `processing`
- `ready`
- `failed`
- `partial`

Generation states:

- `notRequested`
- `queued`
- `generating`
- `ready`
- `failed`

## 6. Merge Rules

User edits are authoritative.

- Late-generated captions do not overwrite user-edited caption cues.
- Late-generated key moments do not overwrite user-authored moments.
- Generated suggestions may only fill empty authored sections.
- Featured-frame suggestions do not overwrite a user-selected featured frame.

## 7. Persistence Ownership Rules

- Post owns canonical media and comment ownership.
- Media item owns media-specific metadata.
- Caption tracks belong to media items.
- Key moments belong to media items.
- Frame captions belong to photo-mode media items.
- Featured frame belongs to media preview metadata.

## 8. Client Wiring Notes

- `CreatePostView` maintains `CreatePostMediaMetadataDraft` during authoring.
- Photo uploads are converted through `applyMetadataToImageItems(urls:)`.
- Witness video uploads are enriched through `applyMetadataToVideoItem(_:)`.
- After Firestore post creation, `MediaMetadataPersistenceService` mirrors metadata into `mediaMeta` documents.

## 9. Deployment / Migration Notes

1. Deploy updated Cloud Functions from `functions/`.
2. Ensure Firestore rules permit backend-managed writes to `posts/{postId}/mediaMeta/**`.
3. No destructive migration is required; this is additive.
4. Existing posts without metadata continue to render via current fallback logic.

## 10. Known Deferred Follow-Ups

Implemented now:

- persisted media metadata fields
- upload-time editing UI scaffolding
- backend mediaMeta mirror writes
- processing/generation state model
- authored-over-generated merge protection

Deferred pending provider integration:

- real speech-to-text transcription provider
- real key-moment ML generation
- automatic thumbnail / featured-frame scoring
- async retry orchestration for failed generation jobs

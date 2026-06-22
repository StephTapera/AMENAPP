# Church Discovery Phase 3

Phase 3 extends the current AMEN Find Church system in place. It does not replace the existing UI, routing, or ranking architecture. The goal is to raise trust, safety, and real-world accuracy across church discovery, church detail, Berean grounding, and church-managed data.

## Firestore Schema

### `churches/{churchId}`

Add or standardize:

- `verificationStatus`: `unverified | pending | verified | rejected`
- `verificationLevel`: `basic | official | trusted`
- `verifiedAt`
- `verifiedBy`
- `officialWebsiteVerified`
- `livestreamVerified`
- `ownershipClaimed`
- `profileConfidence`
- `profileConfidenceLevel`: `low | medium | high | verified`
- `profileConfidenceNote`
- `profileSources`: array of grounded source metadata
- `moderationStatus`: `approved | rejected | needsReview | blocked`
- `parkingInfo`
- `ministries`
- `events`
- `prayerNights`
- `firstTimeVisitorInfo`
- `updatedAt`

Grounded source object shape:

- `id`
- `type`: `verifiedMetadata | officialWebsite | approvedMedia | livestream | serviceSchedule | adminProvided | userPreference | publicMetadata`
- `title`
- `detail`
- `url`
- `verified`
- `updatedAt`

### `churches/{churchId}/verification_claims/{uid}`

- `churchId`
- `uid`
- `claimantEmail`
- `officialWebsite`
- `proofUrl`
- `livestreamUrl`
- `websiteDomainMatches`
- `status`
- `reviewedBy`
- `reviewedAt`
- `createdAt`
- `updatedAt`

### `churches/{churchId}/profile_edit_queue/{editId}`

- `churchId`
- `submittedBy`
- `submitterRole`
- `changes`
- `moderationState`
- `createdAt`
- `updatedAt`

### `churches/{churchId}/livestreams/{streamId}`

- `provider`: `youtube | vimeo | direct_rtmp | direct_hls | embedded | unknown`
- `title`
- `thumbnailUrl`
- `streamUrl`
- `liveNow`
- `startedAt`
- `scheduledAt`
- `viewerSignal`
- `ingestConfidence`
- `sources`
- `updatedAt`

### `churches/{churchId}/pulse/current`

- `title`
- `detail`
- `confidence`
- `confidenceLevel`
- `sources`
- `updatedAt`

### `churches/{churchId}/berean_grounding/current`

- `summary`
- `confidence`
- `confidenceLevel`
- `sources`
- `fallbackMessage`
- `updatedAt`

### `church_admins/{uid}`

- `churchIds`
- `role`: `owner | admin | editor | moderator`
- `permissions`
- `createdAt`

### `moderation_queue/{itemId}`

- `type`
- `source`
- `churchId`
- `uploadedBy`
- `moderationState`: `approved | rejected | needsReview | blocked`
- `moderationReasons`
- `aiScores`
- `escalated`
- `reviewedBy`
- `reviewedAt`
- `createdAt`
- `updatedAt`

### `moderation_queue/{itemId}/history/{historyId}`

- `previousState`
- `newState`
- `reviewedBy`
- `createdAt`

## Swift Model Updates

Phase 3 adds explicit shared model types in `AMENAPP/ChurchModels.swift`:

- `ChurchVerificationStatus`
- `ChurchVerificationLevel`
- `ChurchModerationStatus`
- `ChurchConfidenceLevel`
- `ChurchGroundingSourceType`
- `ChurchAdminRole`
- `ChurchLivestreamProvider`
- `ChurchGroundingSource`
- `ChurchConfidenceMetadata`
- `ChurchVerificationMetadata`
- `ChurchLivestream`
- `ChurchPulseSnapshot`
- `ChurchAdminProfile`
- `ChurchModerationQueueItem`

Existing models now carry source and confidence metadata where it matters:

- `ChurchEntity`
- `ChurchLiveState`
- `ChurchExperienceSummary`
- `ChurchFitScore`
- `ChurchSmartAction`
- `BereanChurchSuggestion`
- `ChurchDetailPayload`

## Cloud Functions

Phase 3 backend callables live in `Backend/functions/src/churchDiscoveryPhase3.ts`.

- `submitChurchVerificationClaim`
- `reviewChurchVerificationClaim`
- `submitChurchProfileEdit`
- `queueChurchMediaModeration`
- `reviewChurchModerationItem`
- `refreshChurchLivestreamState`
- `syncYouTubeChurchStreams`
- `updateChurchLiveSignals`
- `regenerateChurchGroundedSummary`
- `generateGroundedChurchResponse`

Current implementation status:

- Verification claim flow writes pending state and structured review docs.
- Verification review writes canonical church verification fields.
- Profile edits are queued for moderation instead of directly mutating canonical data.
- Media moderation queues ambiguous items for human review instead of deleting them.
- Livestream ingestion is scaffolded with provider-aware document writes and no fake live fallback.
- Berean grounding is explicitly source-backed and returns a safe fallback when grounding is absent.

## Moderation Architecture

Pipeline shape:

1. Upload enters church-managed intake path.
2. AI safety scores are attached for nudity, explicit content, hate, misleading imagery, impersonation, and spam.
3. Caption and OCR text can force `needsReview` even when image scores are low.
4. `moderation_queue/{itemId}` stores the current state.
5. `moderation_queue/{itemId}/history/{historyId}` stores the audit trail.
6. Human reviewers can approve, reject, block, or return to review.

Rules of engagement:

- Ambiguous content is never auto-deleted by this phase.
- Reversible moderation decisions are preserved through history records.
- Canonical church-facing surfaces should only read approved media.

## Verification Architecture

Verification is additive, not exclusionary.

- Unverified churches remain visible in discovery.
- Ownership claim creates `verification_claims/{uid}` and marks the church `pending`.
- Domain/email matching raises confidence but does not alone create verified status.
- Verified status is only finalized by admin review.
- `verificationLevel` escalates from `basic` to `official` to `trusted`.
- Verified churches can receive stronger fit weighting, richer grounding, and safer livestream prioritization.

## Admin Tooling Structure

Recommended admin surfaces:

- verification review queue
- moderation queue
- profile edit queue
- livestream validation queue
- duplicate church merge queue
- dispute history view
- audit log explorer

Recommended role boundaries:

- `owner`: profile ownership, verification, disputes, delegate access
- `admin`: broad profile and event management
- `editor`: non-canonical editable fields only
- `moderator`: moderation queue and safety actions only

## Security Rule Recommendations

These are recommendations for the existing ruleset. Cloud Functions remain the server-authoritative write path.

### Public client reads

- `churches/{churchId}`
- `churches/{churchId}/media/{mediaId}` where approved-only fields are surfaced
- `churches/{churchId}/live_state/current`
- `churches/{churchId}/experience_summary/current`
- `churches/{churchId}/livestreams/{streamId}`
- `churches/{churchId}/pulse/current`
- `churches/{churchId}/berean_grounding/current`

### Direct client writes to deny

- canonical writes to `churches/{churchId}`
- direct writes to `verification_claims`
- direct writes to `profile_edit_queue`
- direct writes to `moderation_queue`
- direct writes to `berean_grounding`
- direct writes to `live_state`, `pulse`, and `livestreams`

### Client writes to permit narrowly

- owner read access to `church_admins/{uid}`
- optional owner create/update only on self-scoped request docs if a client-side request collection is later introduced

### Authorization helpers to add

- `isChurchAdmin(churchId)`
- `hasChurchRole(churchId, role)`
- `canEditChurchManagedFields(churchId)`
- `canModerateChurch(churchId)`

### Canonical field protection

Do not allow direct client writes for:

- `verificationStatus`
- `verificationLevel`
- `verifiedAt`
- `verifiedBy`
- `officialWebsiteVerified`
- `livestreamVerified`
- `ownershipClaimed`
- `profileConfidence`
- `profileConfidenceLevel`
- `profileSources`
- `moderationStatus`

## QA Checklist

- Verified badge only appears for `verificationStatus == verified`.
- Unverified churches still appear in search, map, and detail.
- Pending verification does not hide the church.
- Rejected verification does not destroy existing public metadata.
- Low-confidence experience summaries render with soft language.
- Live state never flips to live without provider or verified input.
- Livestream fallback card appears when a URL exists but live certainty is low.
- Moderation queue item history is written on every reviewer action.
- Profile edits from church admins land in queue instead of overwriting canonical fields.
- Berean grounded response returns source metadata.
- Berean fallback says it lacks enough verified information when grounding is missing.
- No spiritual ranking language is introduced in fit score or summaries.
- Accessibility, Reduce Motion, and Reduce Transparency still pass in existing discovery/detail flows.
- Phase 1 and Phase 2 behaviors remain intact.

## Scalability Recommendations

- Keep canonical church documents small; move operational data into subcollections.
- Prefer scoped listeners on `live_state/current`, `pulse/current`, and `experience_summary/current`.
- Limit livestream queries to recent or active streams.
- Cache resized thumbnails and avoid full-resolution gallery loads by default.
- Batch moderation writes and keep large OCR/caption payloads out of hot church documents.
- Precompute grounded summaries and confidence metadata server-side.
- Add scheduled provider syncs instead of high-frequency client polling.
- Use composite indexes for verification queues, moderation state, and livestream state.
- Keep client reads focused on approved/public subcollections only.

## Files Changed

- `AMENAPP/ChurchModels.swift`
- `AMENAPP/ChurchDataService.swift`
- `AMENAPP/ChurchDetailExperience.swift`
- `AMENAPP/firestore.indexes.json`
- `Backend/functions/src/churchDiscoveryPhase3.ts`
- `Backend/functions/src/index.ts`
- `Docs/ChurchDiscoveryPhase3.md`

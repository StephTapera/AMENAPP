# AMEN Church Discovery Phase 3

This phase extends the existing Find Church stack without replacing the current spatial discovery experience. The focus is trust, data quality, grounding safety, moderation, and scalable real-world church accuracy.

## 1. Updated Firestore Schema

### `churches/{churchId}`
- `verificationStatus: "unverified" | "pending" | "verified" | "rejected"`
- `verificationLevel: "basic" | "official" | "trusted"`
- `verifiedAt: timestamp | null`
- `verifiedBy: string | null`
- `officialWebsiteVerified: boolean`
- `livestreamVerified: boolean`
- `ownershipClaimed: boolean`
- `profileConfidence: number`
- `profileConfidenceLevel: "low" | "medium" | "high" | "verified"`
- `profileConfidenceNote: string | null`
- `moderationStatus: "approved" | "rejected" | "needsReview" | "blocked"`

### `churches/{churchId}/livestreams/{streamId}`
- `provider`
- `title`
- `thumbnailUrl`
- `streamUrl`
- `liveNow`
- `startedAt`
- `scheduledAt`
- `viewerSignal`
- `ingestConfidence`
- `updatedAt`
- `sources`

### `churches/{churchId}/live_state/current`
- `state`
- `title`
- `description`
- `livestreamUrl`
- `confidence`
- `confidenceLevel`
- `sources`
- `updatedAt`

### `churches/{churchId}/experience_summary/current`
- Existing summary fields
- `confidence`
- `confidenceLevel`
- `sources`
- `updatedAt`

### `churches/{churchId}/quality/current`
- `profile`
- `verification`
- `livestreamConfidence`
- `summaryConfidence`
- `bereanGroundingConfidence`
- `updatedAt`

### `church_admins/{uid}`
- `churchIds: string[]`
- `role: "owner" | "admin" | "editor" | "moderator"`
- `permissions: string[]`
- `createdAt: timestamp`

### `church_verification_requests/{requestId}`
- `churchId`
- `requestedBy`
- `contactEmail`
- `claimedDomain`
- `websiteProofURL`
- `livestreamProofURL`
- `notes`
- `status`
- `submittedAt`

### `church_verification_reviews/{reviewId}`
- `churchId`
- `status`
- `level`
- `reviewedBy`
- `officialWebsiteVerified`
- `livestreamVerified`
- `approvedMediaCount`
- `serviceTimeCount`
- `hasAdminEdits`

### `church_admin_edits/{editId}`
- `churchId`
- `payload`
- `submittedBy`
- `status`
- `createdAt`

### `moderation_queue/{itemId}`
- `type`
- `source`
- `churchId`
- `uploadedBy`
- `moderationState`
- `moderationReasons`
- `aiScores`
- `escalated`
- `reviewedBy`
- `reviewedAt`
- `createdAt`
- `history`

## 2. Swift Model Updates

Implemented in [ChurchModels.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/ChurchModels.swift):
- `ChurchVerificationRequest`
- `ChurchAdminEditableProfile`
- `ChurchModerationAuditEntry`
- `ChurchModerationDecisionPayload`
- `ChurchLivestreamIngestSnapshot`
- `ChurchQualitySnapshot`
- `GroundedChurchAnswer`

Extended in [ChurchDiscoveryService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/ChurchDiscoveryService.swift):
- `ChurchRichProfile` now carries verification status, verification level, moderation status, profile confidence, confidence level, and confidence note.
- Ranking now weights trusted/official verification and confidence while preserving visibility for unverified churches.

## 3. Cloud Function Implementations and Stubs

Implemented in [churchTrustCallables.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/controllers/churchTrustCallables.ts):
- `submitChurchVerificationRequest`
- `submitChurchProfileUpdate`
- `reviewChurchModerationItem`
- `refreshChurchLivestreamState`
- `generateGroundedChurchAnswer`
- `syncYouTubeChurchStreams` stub
- `updateChurchLiveSignals` stub
- `moderateChurchMediaUpload`
- `onChurchVerificationReviewed` Firestore trigger

Export surface added in [churchPhase3.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/churchPhase3.ts).

## 4. Moderation Architecture

Implemented in [ChurchModerationEngine.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/services/ChurchModerationEngine.ts):
- image/video label scoring hook
- OCR and caption signal evaluation
- nudity, hate/extremism, misleading, impersonation, and spam scoring
- `approved`, `needsReview`, and `blocked` pathways
- escalation without auto-deleting ambiguous content

Moderation decisions remain reversible through queue history and reviewer attribution.

## 5. Verification Architecture

Implemented in [ChurchTrustSafetyService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/ChurchTrustSafetyService.swift) and backend repository/callables:
- ownership claim submission
- pending verification request queue
- admin review update trigger
- verified profile confidence recalculation
- role-gated church admin update submissions

## 6. Admin Tooling Structure

App-side entry points:
- `loadAdminProfile`
- `submitChurchProfileUpdate`
- `fetchModerationQueue`
- `reviewModerationItem`
- `loadQualitySnapshot`

Backend collections:
- `church_admins`
- `church_admin_edits`
- `moderation_queue`
- `church_verification_requests`
- `church_verification_reviews`

## 7. Livestream Ingestion Architecture

Implemented in [ChurchLivestreamIngestionService.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/services/ChurchLivestreamIngestionService.ts):
- provider-aware record normalization
- confidence-based `liveNow` gating
- source attribution for provider and official website evidence
- explicit fallback when live state is not confirmed

## 8. Security Rule Recommendations

- Allow public read on `churches`, `churches/*/livestreams`, `churches/*/live_state`, and `churches/*/experience_summary` only for approved/non-blocked content.
- Deny direct client writes to canonical church documents except trusted backend service accounts.
- Allow `church_admins/{uid}` read only to that `uid` and privileged moderators.
- Allow church-admin submitted writes only to `church_admin_edits`, never directly to canonical `churches/{churchId}`.
- Allow moderation queue reads/writes only to moderators, owners, and backend service accounts.
- Require App Check and auth for all church verification and moderation callables.
- Store moderation history append-only to preserve reversible review auditability.

## 9. QA Checklist

- Verify unverified churches remain discoverable.
- Verify trusted and official profiles receive stronger ranking weight.
- Verify low-confidence data yields softer copy and “Not confirmed yet” behavior.
- Verify blocked or rejected moderation content does not surface publicly.
- Verify ambiguous media enters `needsReview`, not hard delete.
- Verify fake livestream state never displays as confirmed live.
- Verify grounded Berean responses only use approved sources and return safe fallbacks.
- Verify church ownership claims cannot update canonical fields directly.
- Verify Reduce Motion and Reduce Transparency still render safely on current discovery surfaces.
- Verify no regression in existing Phase 1 and Phase 2 detail and bottom-sheet flows.

## 10. Scalability Recommendations

- Keep `live_state/current`, `experience_summary/current`, and `quality/current` as single-document reads.
- Scope listeners to current detail views only; avoid broad church collection subscriptions.
- Batch moderation queue processing and media resize jobs.
- Prefer provider webhooks or scheduled sync windows over aggressive livestream polling.
- Cache approved media thumbnails and use low-memory image decoding for detail surfaces.
- Index `churches.verificationStatus`, `churches.moderationStatus`, `churches.profileConfidence`, and `moderation_queue.churchId + moderationState`.
- Use lazy loading for moderation queues, admin history, and long media galleries.

## 11. Updated Docs

This file is the Phase 3 architecture reference. It should be kept alongside deployment wiring for the backend export surface in `functions/src/churchPhase3.ts`.

## 12. Files Changed

- [ChurchModels.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/ChurchModels.swift)
- [ChurchDiscoveryService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/ChurchDiscoveryService.swift)
- [ChurchTrustSafetyService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/ChurchTrustSafetyService.swift)
- [BereanChurchGroundingService.swift](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/BereanChurchGroundingService.swift)
- [churchTrust.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/models/churchTrust.ts)
- [ChurchTrustRepository.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/services/ChurchTrustRepository.ts)
- [ChurchConfidenceEngine.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/services/ChurchConfidenceEngine.ts)
- [ChurchModerationEngine.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/services/ChurchModerationEngine.ts)
- [ChurchLivestreamIngestionService.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/services/ChurchLivestreamIngestionService.ts)
- [ChurchGroundingService.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/services/ChurchGroundingService.ts)
- [churchTrustCallables.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/church/controllers/churchTrustCallables.ts)
- [churchPhase3.ts](/Users/stephtapera/Desktop/AMEN/AMENAPP%20copy/AMENAPP/Backend/functions/src/churchPhase3.ts)

# AMEN Creator Backend Plan

## Firestore Collections
- `users/{userId}/creatorProjects/{projectId}`
- `users/{userId}/creatorAssets/{assetId}`
- `users/{userId}/creatorBrandKits/{brandKitId}`
- `users/{userId}/creatorDrafts/{draftId}`
- `users/{userId}/creatorExports/{exportId}`
- `users/{userId}/creatorJobs/{jobId}`
- `users/{userId}/creatorTemplatesSaved/{templateId}`

- `creatorTemplates/{templateId}`
- `creatorFeatureFlags/{flagId}`
- `creatorModerationPolicies/{policyId}`
- `creatorSystemPresets/{presetId}`
- `creatorUsageAnalytics/{dayKey}`
- `creatorEntitlements/{userId}`

Optional:
- `churches/{churchId}/creatorBrandKits/{brandKitId}`
- `churches/{churchId}/creatorCampaigns/{campaignId}`
- `churches/{churchId}/creatorSharedAssets/{assetId}`

## Storage Layout
```
creator/
  users/{userId}/projects/{projectId}/assets/originals/
  users/{userId}/projects/{projectId}/assets/proxies/
  users/{userId}/projects/{projectId}/renders/
  users/{userId}/projects/{projectId}/thumbnails/
  users/{userId}/projects/{projectId}/captions/
  users/{userId}/projects/{projectId}/exports/
  users/{userId}/brandkits/
```

## Security Rules Notes
- Only project owners can read/write their creator documents.
- Status fields for moderation/rendering must be server-only writes.
- Entitlements are read-only for clients.
- Church-scoped assets require church admin/mod verification.
- Storage uploads restricted to authenticated UID and valid project path.

## Cloud Functions (TypeScript)
- createProject
- updateProject
- deleteProject
- autosaveProject
- queueProcessingJob
- processVideoProxy
- generateThumbnail
- transcribeMedia
- generateSubtitleTrack
- translateSubtitleTrack
- buildOutputVariants
- renderExport
- publishProject
- moderateCreatorAsset
- verifyAuthenticitySignals
- saveBrandKit
- cloneTemplateToProject
- recordCreatorAnalytics
- enforceCreatorEntitlement
- cleanupOrphanedAssets
- retryFailedCreatorJob

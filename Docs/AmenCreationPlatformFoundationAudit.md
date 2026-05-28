# Amen Creation Platform Foundation Audit

Date: 2026-05-19

## Scope

This audit covers the non-destructive foundation for Amen as a unified creation, media, conversation, notes, design, community, and AI platform. The current codebase already contains major product systems, so this pass avoids replacing existing flows and instead adds server-authoritative foundations behind feature flags.

## Current Architecture

Frontend systems found:
- `CreatePostView` remains the canonical production composer.
- `PostCard`, `AmenMediaDetailView`, comments, sharing, saving, and profile surfaces are already established around legacy `Post` models.
- `ContentNode.swift`, `ContentBlock.swift`, `MediaRef.swift`, `AIMetadata.swift`, `ModerationState.swift`, `AmenContentType.swift`, `AmenVisibility.swift`, `AmenContentRouter.swift`, and `AmenContentRenderer.swift` already exist as partial universal content foundations.
- `AmenCreateHubView`, `AmenAdaptiveComposerView`, `AmenCreationDraftStore`, `AmenCreationDraft`, `AmenCreationToolbar`, and media helper views already exist, but the backend callables they expected were missing.
- `DesignSystem/AdaptiveInterface/AmenAdaptiveInterfaceSystem.swift` already implements adaptive density, semantic atmosphere, progressive material density, reduced-motion support, reduced-transparency support, dynamic type considerations, and spatial microdepth.
- Berean AI has a broad service layer, contextual actions, selection overlays, translation, realtime/session services, and analytics.
- Church Notes has a mature notes/media-processing surface with server-owned AI draft and processing fields.
- Creator backend functions already exist for projects, assets, processing, subtitles, thumbnail generation, translation, exports, and analytics.

Backend systems found:
- Firebase Functions root backend lives in `Backend/functions`.
- Strong existing patterns use `onCall({ enforceAppCheck: true })`, explicit auth checks, Firestore server writes, and typed validation.
- Existing functions cover safety, Berean, creator, media metadata, social graph, community/covenant, smart share, and notification pipelines.
- Firestore rules deny unknown paths by default and already server-own many moderation, AI, processing, reporting, and analytics fields.

## Reusable Systems

- Existing post creation, feed, comments, profile, share/save, and media detail flows should remain production paths while the universal model matures.
- Existing `AMENFeatureFlags` and Firebase Remote Config are the correct rollout control layer.
- Existing `AMENAnalyticsService` already includes events for universal content, create, and media foundations.
- Existing Adaptive Interface design tokens are the correct place to evolve Liquid Glass into behavior-based Adaptive Glass rather than adding a second design system.
- Existing creator functions should be adapted before new design/video processing functions are created.
- Existing Church Notes blocks and media processing should be bridged into `ContentBlock`/`MediaRef` instead of replaced.

## Duplicated Or Partial Systems

- There are multiple backend roots visible in project references. The active package with `package.json` and `tsconfig.json` is `Backend/functions`.
- Universal create UI existed before the matching backend callables, so remote save/restore/publish could fail.
- Some high-risk universal/media flags defaulted on even though the end-to-end backend was incomplete.
- `firestore.deploy.rules` appears generated/minified and should be regenerated from source rules before deployment.

## Missing Pieces Addressed In This Pass

- Added server-authoritative universal content and draft callables.
- Added shared TypeScript interfaces for `ContentNode`, `ContentBlock`, `MediaRef`, visibility, type, moderation, and AI metadata.
- Added Firestore rules for `content/{contentId}`, `content/{contentId}/metrics/aggregate`, and `users/{uid}/drafts/{draftId}` in the source rules file.
- Changed incomplete universal create/media/feed flags to safe default-off values in local defaults and Remote Config defaults.

## Still Missing

- Full Phase 3-14 frontend surfaces are not release-ready end to end.
- Dedicated backend callables for all requested AI, notes, design, immersive feed, profile V2, communities, universal search, moderation appeals, and creator workspace flows are not all implemented in this pass.
- Security rules tests should be added for the new universal paths.
- Production deployment must confirm whether `firestore.rules` or `AMENAPP/firestore.deploy.rules` is the active deploy source.

## Risk Register

- High: enabling `universalCreateEnabled` before backend deployment would expose incomplete creator/media UX.
- High: direct content reads require approved moderation; there must be a moderation worker before public content appears broadly.
- Medium: duplicate backend trees can cause accidental edits to the wrong function package.
- Medium: universal model and legacy post model need broader mapper tests.
- Low: Adaptive Glass foundations are present and accessibility-aware, but visual audits are still needed per surface.

## Build Order

1. Keep existing production flows active.
2. Deploy universal content callables and rules.
3. Add tests for universal content function validation and rules.
4. Enable `universalContentModelEnabled` for internal users only.
5. Wire read-only rendering into existing Post surfaces.
6. Enable `universalCreateEnabled` only after publish, moderation, feed, profile, and search paths pass.
7. Add notes/design/media/thread/community/search modules incrementally using adapters.

## Files Likely To Change Next

- `AMENAPP/ContentNode.swift`
- `AMENAPP/AmenAdaptiveComposerView.swift`
- `AMENAPP/AmenCreationDraftStore.swift`
- `AMENAPP/AMENFeatureFlags.swift`
- `Backend/functions/src/universalContent/*`
- `firestore.rules`
- Rules tests under `Backend/rules-tests`
- Backend Jest tests under `Backend/functions/src`

## Target Data Flow

Create -> Upload -> Moderation -> AI Metadata -> Publish -> Feed -> Comments -> Save -> Search -> Remix.


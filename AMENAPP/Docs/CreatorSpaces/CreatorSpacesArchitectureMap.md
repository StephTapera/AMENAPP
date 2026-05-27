# Creator Spaces Architecture Map

## Navigation

Creator Spaces lives inside `AmenStudioResourcesView` in the Resources tab. The entry is gated by `creator_spaces_enabled` through `CreatorSpacesFeatureFlags`.

## Phase 1 routes

- Resources -> Creator Spaces home
- Creator Spaces -> Daily Portion feed
- Creator Spaces -> Creator Commerce overview
- Creator Spaces -> Provenance nutrition label preview

## Shared contracts

Swift contracts live in `CreatorSpaces/Shared`:

- `CreatorMediaAsset`
- `CreatorProvenanceLabel`
- `CreatorMemoryNode`
- `CreatorSpace`
- `CreatorMediaAssetDraft`
- `CreatorSpacesService`

Backend contracts live in `Backend/functions/src/creatorSpaces` and are exported from `Backend/functions/src/index.ts`.

## Kill switches

- `creator_spaces_enabled`
- `presence_posts_enabled`
- `collective_memory_enabled`
- `smart_church_clips_enabled`
- `media_authenticity_enabled`
- `creator_subscriptions_enabled`
- `ai_creative_director_enabled`
- `creator_discovery_enabled`

Production defaults are off. Debug defaults are on for local development.

## Current Phase 1 boundaries

- Provenance fields are server-owned.
- Synthetic detection, authenticity confidence, and AI-assisted percentage are intentionally `null` until real measurement exists.
- The feed is bounded by `getDailyPortion` and returns `exhausted`.
- GUARDIAN enqueue is written for uploads; full moderation workers remain a follow-up workstream.
- Stripe Connect payout execution is not implemented in this slice; the UI is gated and the architecture keeps entitlement checks server-side.

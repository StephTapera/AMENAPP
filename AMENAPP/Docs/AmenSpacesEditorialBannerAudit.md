# Amen Spaces Editorial Banner Audit

## Placement Decision

Canonical home: Amen Spaces Home.

Reason: Spaces is the only current surface that already combines groups, discussions, organizations, local discovery, membership context, and Liquid Glass visual language. The banner rail belongs above the existing hero discussion and below category/search controls so it promotes live opportunities without replacing the discovery flow.

Approved secondary surfaces:
- Space Detail: pinned announcements, upcoming events, active discussions.
- Church Profile: ministries, open volunteer roles, services, celebrations.
- School Profile: cohorts, campus groups, events, service opportunities.
- Business Profile: featured programs and community updates.
- Discovery / Explore: recommended spaces, sermons, creators, local communities.
- Events: RSVP banners.
- Jobs / Volunteer Board: featured roles.
- Messages / Rooms: pinned discussion prompts or live gathering cards.
- Berean suggestions: related study groups and discussions.
- Amen Home Feed: one relevant happening-now rail.

## Current Repo Findings

- `AmenSpacesDiscussionDiscoveryView` already had a single discussion hero banner, but not a reusable multi-type banner rail.
- Existing Spaces discovery contracts are server-authoritative through Cloud Functions, which is the right pattern to extend.
- Liquid Glass helper components exist under AIIntelligence, but the banner needed its own bottom metadata overlay and Reduce Transparency handling.
- The existing Spaces discovery service falls back to samples when no data exists. The editorial banner rail does not use sample banners because the requirement says every displayed banner must come from approved backend data.

## Implemented Scope

Frontend:
- Added `AmenSpaceBannerRail.swift` with shared models, service, view model, Liquid Glass card UI, loading/error/empty behavior, dismissal, CTA validation, analytics hooks, accessibility labels, Reduce Transparency handling, and size menu.
- Wired the rail into Amen Spaces Home.
- Added Swift tests for callable contracts, duplicate target route prevention, and supported banner sizes.

Backend:
- Added `amenSpaceBanners.ts` with server-side eligibility, ranking, moderation filtering, visibility filtering, size resolution, user preference persistence, admin default size persistence, analytics logging, dismissals, and CTA validation.
- Exported the functions from `index.ts`.
- Added Jest tests for eligibility, moderation/visibility, ranking, duplicate prevention, and size resolution.

Rules:
- Added Firestore rules for `amenSpaceBanners`, `amenSpaceBannerAnalytics`, `users/{uid}/bannerDisplayPreferences`, `users/{uid}/dismissedSpaceBanners`, and `amenSpaces/{spaceId}/settings/bannerDisplay` in root `firestore.rules`.

## Rollout Caveats

- Only Amen Spaces Home is wired in this pass. The component and backend support the approved secondary surfaces, but those screens should be wired one at a time to avoid routing regressions.
- Backend banner authoring/admin UI is not added. Source documents must be created by trusted backend/admin tooling.
- Firestore deploy rules may need to be regenerated from `firestore.rules` if the project deploy pipeline uses a minified copy.

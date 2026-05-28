# Smart Community Search Production Checklist

Smart Finder / Ask Amen is gated by client Remote Config and backend environment flags. Keep external AI and Google Places disabled until the Firebase project has secrets, App Check, and quota monitoring configured.

## Backend Secrets

Configure these only in Firebase Secret Manager:

- `OPENAI_API_KEY`
- `GOOGLE_PLACES_API_KEY`
- `GOOGLE_MAPS_API_KEY`

Optional:

- `ANTHROPIC_API_KEY`
- `ALGOLIA_APP_ID`
- `ALGOLIA_SEARCH_KEY`
- `ALGOLIA_ADMIN_KEY`
- `ALGOLIA_CHURCHES_INDEX_NAME`
- `ALGOLIA_SPACES_INDEX_NAME`
- `ALGOLIA_EVENTS_INDEX_NAME`

## Backend Flags

Set these as function environment variables:

- `SMART_COMMUNITY_SEARCH_ENABLED=true`
- `SMART_COMMUNITY_SEARCH_EXTERNAL_PLACES_ENABLED=true` only after Google Maps quota and data-use review.
- `SMART_COMMUNITY_SEARCH_AI_ENABLED=true` only after prompt and schema monitoring is enabled.

## Client Remote Config

Enable in this order:

- `smart_community_search_enabled`
- `smart_community_search_external_places_enabled`
- `smart_community_search_ai_enabled`

The app must keep the existing Find Church flow available when `smart_community_search_enabled` is false.

## Privacy And Safety Checks

- Do not log raw search queries by default.
- Use `manualLocationText` only for server-side geocoding; do not store it.
- Keep App Check enforcement enabled for `smartCommunitySearch` and `logSmartSearchInteraction`.
- Verify Firestore writes under `smartSearchAbuseLimits`, `smartSearchAnalytics`, and existing rate-limit paths are backend-only.
- Review Google Maps Platform data-retention terms before caching or persisting any Places-derived fields.

## Release Validation

- `npm run typecheck -- --pretty false`
- `npm run lint -- --quiet`
- `npm run build`
- Focused and full Firebase Functions tests.
- Xcode build with a provisioning profile that includes `group.com.amenapp.shared`.
- Manual QA for location allowed, denied, manual city/ZIP, empty results, safety block, crisis notice, retry, save, directions, and Ask Berean.

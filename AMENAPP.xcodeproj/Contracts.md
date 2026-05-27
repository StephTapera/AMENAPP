# Selah Banner Rail Contracts

Status: frozen Phase 0 interface. This document defines the contract other agents must code against. It intentionally contains no feature implementation.

## Scope

The Selah banner rail resolves moderated, eligible banner content server-side and renders only banners with valid typed CTA routes client-side. The first live surface is `spacesHome`; additional surfaces must reuse this contract unchanged.

## BannerSize

The client and server must share these exact raw values verbatim.

### Swift

```swift
enum BannerSize: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case large
    case hero

    var id: String { rawValue }
}
```

### JSON

```json
"compact" | "standard" | "large" | "hero"
```

Resolution waterfall: user preference -> space default -> surface default -> `standard`.

## CTA Actions

The CTA action is a semantic action, separate from display text.

```json
"join" | "rsvp" | "apply" | "open" | "pray" | "watch"
```

Allowed mapping:

| CTA action | Required route grammar | Existing flow opened |
| --- | --- | --- |
| `join` | `selah://group/{id}` | Group join flow |
| `rsvp` | `selah://event/{id}/rsvp` | Event RSVP flow |
| `apply` | `selah://job/{id}/apply` | Job application flow |
| `open` | `selah://space/{id}` | Space open flow |
| `pray` | `selah://prayer/{id}` | Prayer flow |
| `watch` | `selah://sermon/{id}` | Sermon watch flow |

A banner is renderable only when `cta.action` and `cta.route` match the table above. A mismatched, malformed, missing, or unsupported route must be excluded before render and logged with `banner_hidden_reason.reason = "unresolvable_route"`.

## Route Grammar

Routes are absolute custom-scheme URIs. IDs are path segments and must be non-empty URL-safe identifiers.

```ebnf
route        = groupRoute | eventRsvpRoute | jobApplyRoute | spaceRoute | prayerRoute | sermonRoute ;
groupRoute   = "selah://group/" id ;
eventRsvpRoute = "selah://event/" id "/rsvp" ;
jobApplyRoute  = "selah://job/" id "/apply" ;
spaceRoute   = "selah://space/" id ;
prayerRoute  = "selah://prayer/" id ;
sermonRoute  = "selah://sermon/" id ;
id           = 1*( ALPHA | DIGIT | "-" | "_" ) ;
```

Validation rules:

- Scheme must be `selah`.
- Host must be one of `group`, `event`, `job`, `space`, `prayer`, `sermon`.
- No query string or fragment is allowed in Phase 0.
- Route parsing happens before a banner reaches the rendered rail.
- `banner_cta_complete` fires only after the downstream flow reports success, never on tap.

## ResolvedBanner

### Swift Codable Model

```swift
struct ResolvedBanner: Identifiable, Codable, Equatable {
    let id: String
    let sourceId: String
    let title: String
    let subtitle: String
    let imageURL: URL?
    let iconURL: URL?
    let surface: BannerSurface
    let spaceId: String?
    let cta: BannerCTA
    let rankingReason: RankingReason?
    let rank: Int
    let score: Double
    let resolvedSize: BannerSize
    let startsAt: Date?
    let endsAt: Date?
    let accessibilityLabel: String
}

struct BannerCTA: Codable, Equatable {
    let action: BannerCTAAction
    let label: String
    let route: String
}

enum BannerCTAAction: String, Codable, CaseIterable {
    case join
    case rsvp
    case apply
    case open
    case pray
    case watch
}

enum RankingReason: String, Codable, CaseIterable {
    case trustedNetwork
    case nearby
    case memberActivity
    case upcomingEvent
    case ministryPriority
    case recentMomentum
}

enum BannerSurface: String, Codable, CaseIterable {
    case spacesHome
    case spaceDetail
    case churchProfile
    case schoolProfile
    case businessProfile
    case discovery
    case events
    case jobs
    case messagesRooms
    case bereanSuggestions
    case homeFeed
    case userProfile
}
```

`rankingReason` is nullable. The server must emit it only when a real dominant scoring signal fired. The client must not invent or alter it.

### JSON Shape

```json
{
  "id": "banner_123",
  "sourceId": "source_123",
  "title": "Young Adults Night",
  "subtitle": "Friday at 7 PM near you",
  "imageURL": "https://example.com/banner.jpg",
  "iconURL": "https://example.com/icon.png",
  "surface": "spacesHome",
  "spaceId": "space_123",
  "cta": {
    "action": "rsvp",
    "label": "RSVP",
    "route": "selah://event/event_123/rsvp"
  },
  "rankingReason": "nearby",
  "rank": 1,
  "score": 0.917,
  "resolvedSize": "standard",
  "startsAt": "2026-05-25T00:00:00Z",
  "endsAt": "2026-06-01T00:00:00Z",
  "accessibilityLabel": "Young Adults Night, Friday at 7 PM near you, RSVP"
}
```

Required fields: `id`, `sourceId`, `title`, `subtitle`, `surface`, `cta`, `rank`, `score`, `resolvedSize`, `accessibilityLabel`.

Optional nullable fields: `imageURL`, `iconURL`, `spaceId`, `rankingReason`, `startsAt`, `endsAt`.

## Callable Contract

Callable name: `resolveBannerRail`.

### Request

```json
{
  "surface": "spacesHome",
  "spaceId": "space_123"
}
```

Fields:

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `surface` | yes | `BannerSurface` | Surface requesting banners. |
| `spaceId` | no | string | Required for space-scoped surfaces such as `spaceDetail`; omitted for global surfaces. |

Authentication is required. Trust, proximity, membership, network, location, momentum, and moderation eligibility are computed server-side only.

### Response

```json
{
  "banners": [
    {
      "id": "banner_123",
      "sourceId": "source_123",
      "title": "Young Adults Night",
      "subtitle": "Friday at 7 PM near you",
      "imageURL": "https://example.com/banner.jpg",
      "iconURL": null,
      "surface": "spacesHome",
      "spaceId": "space_123",
      "cta": {
        "action": "rsvp",
        "label": "RSVP",
        "route": "selah://event/event_123/rsvp"
      },
      "rankingReason": "nearby",
      "rank": 1,
      "score": 0.917,
      "resolvedSize": "standard",
      "startsAt": "2026-05-25T00:00:00Z",
      "endsAt": "2026-06-01T00:00:00Z",
      "accessibilityLabel": "Young Adults Night, Friday at 7 PM near you, RSVP"
    }
  ],
  "resolvedSize": "standard"
}
```

Response rules:

- `banners` contains only approved banners within their active time window.
- Candidate query must exclude unapproved content before eligibility and scoring.
- Eligibility filtering happens before scoring.
- Dedupe happens by canonical route, preserving the highest ranked banner.
- Server caps response length for the surface.
- Top-level `resolvedSize` is the rail size after the waterfall. Each banner repeats `resolvedSize` for analytics and rendering convenience; values must match the top-level size for this release.

## Firestore Data Contracts

### `bannerSources/{id}`

```json
{
  "title": "Young Adults Night",
  "subtitle": "Friday at 7 PM near you",
  "imageURL": "https://example.com/banner.jpg",
  "iconURL": null,
  "cta": {
    "action": "rsvp",
    "label": "RSVP",
    "route": "selah://event/event_123/rsvp"
  },
  "surfaceAllowlist": ["spacesHome"],
  "spaceId": "space_123",
  "visibility": "public",
  "moderationStatus": "approved",
  "startsAt": "2026-05-25T00:00:00Z",
  "endsAt": "2026-06-01T00:00:00Z",
  "createdBy": "uid_123",
  "createdAt": "2026-05-25T00:00:00Z",
  "updatedAt": "2026-05-25T00:00:00Z"
}
```

`moderationStatus` allowed values: `pending`, `approved`, `rejected`. Only the function service identity may write `moderationStatus`.

### `bannerDisplayPreferences/{uid}`

```json
{
  "sizesBySurface": {
    "spacesHome": "standard",
    "spaceDetail": "large"
  },
  "updatedAt": "2026-05-25T00:00:00Z"
}
```

Users may read and write only their own preference document.

### `spaces/{id}.defaultBannerSize`

```json
{
  "defaultBannerSize": "standard"
}
```

The same `BannerSize` raw values are used here.

## Analytics Events

All analytics events include these common required properties unless explicitly noted:

| Property | Type | Required | Notes |
| --- | --- | --- | --- |
| `eventName` | string | yes | One of the five names below. |
| `bannerId` | string | yes | `ResolvedBanner.id`; use `unknown` only for pre-resolution hidden events. |
| `sourceId` | string | yes | `ResolvedBanner.sourceId`; use `unknown` only for malformed payloads with no source. |
| `surface` | `BannerSurface` | yes | Calling surface. |
| `spaceId` | string/null | yes | Null when not space-scoped. |
| `resolvedSize` | `BannerSize` | yes | Rail size at the time of event. |
| `ctaAction` | `BannerCTAAction`/null | yes | Null only when there is no CTA to parse. |
| `route` | string/null | yes | Canonical route when available. |
| `rank` | number/null | yes | Null for hidden events before ranking. |
| `sessionId` | string | yes | Client session identifier. |
| `occurredAt` | ISO-8601 string | yes | Client event time. |

### `banner_impression`

Fires when a card crosses the visibility threshold, not when data loads.

Additional required properties:

| Property | Type | Notes |
| --- | --- | --- |
| `visibleRatio` | number | Ratio that satisfied the threshold. |
| `visibilityThreshold` | number | Configured threshold used by the client. |

### `banner_tap`

Fires immediately when the user taps a CTA that survived route validation.

Additional required properties:

| Property | Type | Notes |
| --- | --- | --- |
| `tapTarget` | string | `cta`. |

### `banner_cta_complete`

Fires only when the downstream existing flow reports success.

Additional required properties:

| Property | Type | Notes |
| --- | --- | --- |
| `completionSource` | string | Existing flow that confirmed success, such as `group_join` or `event_rsvp`. |
| `downstreamEntityId` | string | ID parsed from the route. |

### `banner_dismiss`

Fires when a user dismisses or swipes away a card.

Additional required properties:

| Property | Type | Notes |
| --- | --- | --- |
| `dismissMethod` | string | `swipe`, `button`, or `system`. |

### `banner_hidden_reason`

Fires at the point of exclusion. This event is allowed before render and before impression.

Additional required properties:

| Property | Type | Notes |
| --- | --- | --- |
| `reason` | string | One of the hidden reason values below. |
| `stage` | string | `server_candidate`, `server_eligibility`, `client_route_validation`, or `client_render_guard`. |

Allowed hidden reasons:

```json
"unresolvable_route" | "moderation_status" | "outside_time_window" | "ineligible_visibility" | "ineligible_membership" | "ineligible_network" | "ineligible_location" | "deduped" | "cap_exceeded" | "missing_required_field"
```

## Feature Flag

The entire rail is controlled by `bannerRail`. Default: off.

Rules:

- Server and client must both respect the flag.
- Production writes and callable exposure remain inert while the flag is off.
- First production wiring is `spacesHome` only.

## Frozen Decisions And Ambiguities

- The callable is named `resolveBannerRail`, replacing older banner callable names for this Selah contract.
- The route scheme is `selah://`; older `amen://` routes are not valid for this release.
- Query strings and fragments are intentionally disallowed until a future contract revision.
- Top-level `resolvedSize` and per-banner `resolvedSize` must match for this release.
- `rankingReason` may be null; emitting a reason without a fired scoring signal is a contract violation.
- CTA display labels are not used for routing authority. `cta.action` plus parsed typed route determine the flow.

# Get Ready Sunday Architecture

## Frontend Architecture

### View hierarchy
- `FindChurchView`
  - `EnhancedMinimalChurchCard`
    - `I'm going here Sunday`
    - `GetReadyPlanRepository.createOrUpdatePlan(for:)`
    - presents `GetReadyView`
- `GetReadyView`
  - `GetReadyHeroPhotoLayer`
  - `GetReadyGlassBanner`
  - `AlreadyHandled` pill row
  - `GetReadyJourneySectionCard`
    - `Departure`
    - `Quiet Mode`
    - `Berean`
    - `Kids Check-In`
    - `Church Notes`
    - `First Visit`
    - `After Service`

### State machine
- `idle`
  - no Sunday plan exists
- `planning`
  - user tapped the CTA
  - repository creates or updates the per-church plan snapshot
- `hydrating`
  - view model builds route, focus, family, Berean, and auto-handled state
- `ready`
  - sections are ranked and visible
- `attending`
  - quiet mode suggestions and church proximity callbacks can elevate
- `completed`
  - reflection and note conversion are prioritized

### Hero rendering architecture
- Photo layer and glass layer are separate.
- The photo layer never scales with scroll.
- The glass layer is the only transform target.
- Scroll offset is converted into a capped `progress` value.
- Motion is damped using interpolation instead of raw binding.
- Overlay tint and opacity react more than geometry.

### Motion spec
- Scale range: `1.0 -> 0.98`
- Vertical shift: `0 -> -6pt`
- No blur radius animation per frame.
- Reading mode turns on when scroll velocity is low.
- Motion is anchored to the top of the hero and never parallax-drifts.

### Image loading and caching strategy
- Use `AsyncImage` for current app-level loading.
- Church media metadata lives on the plan object.
- Production backend should precompute:
  - canonical hero image URL
  - logo URL
  - brightness bucket
  - fallback mode
  - crop-safe derivatives
- Client chooses between:
  - photo
  - logo treatment
  - premium fallback

## Backend Architecture

### Services
- `church_profile_service`
  - metadata, location, website, service times, visitor notes
- `church_media_ingestion_service`
  - crawl approved public assets
  - score hero candidates
  - compute brightness and contrast metadata
  - emit canonical media refs
- `attendance_intelligence_service`
  - "I'm going" commitments
  - preferred service selection
  - repeat attendance learning
- `quiet_mode_signal_service`
  - geofence, time window, calendar, motion, route-completion scoring
- `route_intelligence_service`
  - leave-by calculation
  - parking buffer
  - first-visit and family modifiers
- `family_prep_service`
  - child profiles
  - medical notes
  - pickup reminders
  - family card payloads
- `church_partner_integration_service`
  - Planning Center
  - Rock RMS
  - Tithely Check-In
- `calendar_rhythm_service`
  - recurring services
  - reminder stack
  - conflict detection
- `coffee_intelligence_service`
  - provider preference
  - route-aware suppression
- `music_intelligence_service`
  - provider preference
  - worship-style matching
- `berean_service_bridge`
  - passage preview
  - Selah prompt
  - memory verse
  - notes preload
- `wallet_pass_service`
  - family card
  - kids check-in pass
  - giving or pickup QR when supported

### APIs
- `POST /v1/get-ready/plans`
  - create or update a church plan
- `GET /v1/get-ready/plans/{churchId}`
  - fetch hydrated plan state
- `POST /v1/get-ready/media/ingest`
  - enqueue website asset ingestion
- `POST /v1/get-ready/quiet-mode/evaluate`
  - return confidence, threshold, and explanation
- `POST /v1/get-ready/route/recommendation`
  - return leave-by intelligence and route modifiers
- `POST /v1/get-ready/family/pass`
  - return family card or wallet payload
- `POST /v1/get-ready/berean/prep`
  - return Selah, passage preview, prayer, and note template context

### Firestore schema
- `churches/{churchId}`
- `churches/{churchId}/services/{serviceId}`
- `churches/{churchId}/media/{mediaId}`
- `users/{userId}/churchPlans/{churchId}`
- `users/{userId}/churchPreferences/{churchId}`
- `users/{userId}/familyProfiles/{childId}`
- `users/{userId}/getReadyStates/{churchId_date}`
- `users/{userId}/quietModeSignals/{eventId}`
- `users/{userId}/routePreferences/default`
- `users/{userId}/calendarPreferences/default`
- `users/{userId}/coffeePreferences/default`
- `users/{userId}/musicPreferences/default`
- `users/{userId}/churchNotesTemplates/{churchId}`
- `users/{userId}/walletPasses/{passId}`

### Background jobs
- `media_ingestion_job`
  - crawl website, score image candidates, compute contrast metadata
- `service_schedule_refresh_job`
  - detect holiday or special-service changes
- `route_refresh_job`
  - re-evaluate leave-by at `-60m`, `-10m`, and departure time
- `quiet_mode_signal_job`
  - evaluate background signal fusion updates
- `reflection_seed_job`
  - schedule post-service Berean prompt

## Data Contracts

### Church plan object
```json
{
  "churchId": "string",
  "chosenServiceId": "string",
  "chosenServiceTime": "timestamp",
  "status": "planned|attending|completed|skipped",
  "isFirstVisit": true,
  "travelAppPreference": "apple|google|ask",
  "coffeePreference": "none|starbucks|dunkin|local|askEachTime",
  "musicProviderPreference": "none|appleMusic|spotify|askEachTime",
  "quietModePreference": "auto|ask|off",
  "notePreference": "churchNotes|appleNotes|paper|listen",
  "bringPhysicalBible": true,
  "afterServicePreference": "fellowship|lunch|home|varies",
  "heroMediaRef": "churches/{churchId}/media/{mediaId}",
  "routeRecommendation": {},
  "focusState": {},
  "autoHandledState": {}
}
```

### Church media metadata
```json
{
  "kind": "photo|logo|fallback",
  "heroImageURL": "string|null",
  "logoURL": "string|null",
  "brightness": "bright|balanced|dark",
  "contrastScore": 0.78,
  "dominantColorHex": "#D9D4CC",
  "fallbackMode": "monogram|neutralGradient"
}
```

### Route intelligence
```json
{
  "leaveBy": "timestamp",
  "travelMinutes": 24,
  "bufferMinutes": 28,
  "weatherSummary": "Light rain near arrival",
  "parkingNote": "Visitor lot fills 10 min before service",
  "confidence": 0.88
}
```

### Quiet mode scoring payload
```json
{
  "churchId": "string",
  "serviceId": "string",
  "score": 87,
  "threshold": {
    "auto": 85,
    "suggest": 60
  },
  "signals": {
    "geofence": 24,
    "timeWindow": 22,
    "calendar": 12,
    "motion": 11,
    "attendanceHistory": 10,
    "routeCompletion": 8
  },
  "decision": "auto"
}
```

### Family check-in payload
```json
{
  "churchId": "string",
  "partnerType": "none|planningCenter|rock|tithely",
  "kids": [
    {
      "id": "string",
      "name": "Eli",
      "ageLabel": "5 yr",
      "allergySummary": "Peanut allergy",
      "medicalNotes": "Epi-pen required"
    }
  ],
  "pickupReminder": "10:40 AM",
  "walletPassId": "string|null"
}
```

## Product Logic

### Ranking rules
- `Now` is always first.
- If departure is within 25 minutes, `On the way` moves ahead of `Prepare your heart`.
- If the user has kids, `At church` moves ahead of `On the way` once route timing is set.
- If more than 90 minutes remain, Berean prep outranks route extras.

### Quiet mode thresholds
- `85+`: auto-enable when mode is `auto`
- `60-84`: suggest
- `<60`: do nothing

### Fallback rules
- If no approved media exists, do not show a blank or generic placeholder.
- Use a denomination-aware neutral gradient with monogram or church icon treatment.
- Keep the same rounded glass hero shell regardless of media mode.

### First-visit logic
- Default `isFirstVisit = true` until repeat attendance is observed.
- Surface parking, entrance, dress, and who-to-ask hints only on first visit.

### Coffee suppression logic
- Suppress coffee when:
  - departure window is under 25 minutes
  - route confidence is low
  - user is a first-time visitor with family timing pressure
  - traffic or weather erodes the route buffer

### Music provider logic
- Ask only when user taps music for the first time.
- Respect `none` permanently until changed.
- Hide provider-specific actions when no provider is chosen.

### Physical Bible logic
- Always show as a subtle pill when enabled.
- Increase prominence when note preference is `paper` or `churchNotes`.

### Church Notes preload logic
- Preload:
  - church name
  - service time
  - sermon passage if known
  - sections for key points, verses, conviction, application, prayer

## UI Spec

### Spacing
- Hero horizontal inset: `16pt`
- Hero internal padding: `16pt`
- Hero radius: `28pt`
- Content overlap: `28pt`
- Section radius: `22pt`
- Card row padding: `16pt`
- Pill spacing: `8pt`

### Glass behavior
- Use one material shell per section.
- Hero uses `ultraThinMaterial` plus tint overlay.
- Section cards use `regularMaterial`.
- No nested blur stacks inside the hero.

### Content-aware tint logic
- Bright hero: darker text, stronger neutral overlay
- Balanced hero: moderate overlay, white text
- Dark hero: lighter overlay, white text with softer edge bloom

### Hero contrast rules
- Minimum readable tint is derived from brightness bucket, not raw scroll.
- Text color is stable per hero mode.
- Motion only increases tint opacity; it does not swap palettes.

### Inline morph rules
- Expand route details inline.
- Expand Berean, kids, and first-visit guidance inline.
- Do not push new screens for lightweight actions.

## Rollout Plan

### MVP
- durable per-church plan creation
- stable hero
- route timing
- auto-handled row
- Berean prep
- first-visit guidance
- quiet mode onboarding

### Phase 2
- church media ingestion backend
- family card and wallet pass generation
- route refresh notifications
- richer church notes preload
- provider-aware coffee and music

### Phase 3
- church partner integrations
- live quiet mode confidence explanation
- calendar conflict intelligence
- widgets, Live Activity, App Intent, Spotlight surfaces

## Performance Guardrails
- Never animate the photo crop on scroll.
- Cap hero transform ranges tightly.
- Precompute hero brightness and fallback mode.
- Keep section animation local and inline.
- Avoid opacity, scale, and blur fighting on the same layer.

## Analytics
- `get_ready_plan_created`
- `get_ready_plan_opened`
- `get_ready_section_expanded`
- `get_ready_maps_opened`
- `get_ready_quiet_mode_enabled`
- `get_ready_berean_started`
- `get_ready_notes_opened`
- `get_ready_family_card_opened`
- `get_ready_reflection_started`

## Failure Handling
- If media ingestion fails, stay on premium fallback hero.
- If route intelligence fails, fall back to local timing estimate.
- If quiet mode automation is unavailable, degrade to suggestion mode.
- If partner check-in is unavailable, generate Family Card fallback.
- If music or coffee providers are unavailable, suppress those cards quietly.

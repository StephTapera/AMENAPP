# FROZEN - Data Models Contract - Spiritual OS
> Version 1.1 - 2026-06-11 - Lead Orchestrator
> FROZEN. Implement against these exact schemas. No field renames or additions without Lead sign-off.

---

## Existing Collections (read-only — do NOT modify schemas)

Consumed by Spiritual OS but not structurally changed:
`users`, `posts`, `prayers`, `communities`, `spaces`, `events`, `messages`, `conversations`,
`covenants`, `prayerReminders`, `bereanMemory`, `reflectionJourneys`, `savedResources`

---

## New Collection 1: `spiritualOS_digest/{userId}/items/{itemId}`
Daily digest feed. Server-written (CF), client read-only except `isRead`.

```
itemId        String    Auto (CF-generated)
userId        String    Owner UID (must match auth)
type          String    "verse" | "prayerReminder" | "eventToday" | "mention" |
                        "bereanStudy" | "birthday" | "spaceUpdate" | "readingPlan"
title         String    Short display title (max 80 chars)
body          String?   Preview text (max 280 chars)
sourceRef     String?   Deep link route (e.g. "prayer/{id}", "space/{id}")
sourceType    String?   Collection name of referenced document
priority      Number    0–100, CF-assigned. Client sorts descending.
isRead        Boolean   Client-writable on view
createdAt     Timestamp Server timestamp
expiresAt     Timestamp Default: end of current day (UTC)
aegisFlags    Map?      Aegis flags that apply (e.g. {prayerPrivacy: true})
```

---

## New Collection 2: `spiritualOS_hub/{userId}/items/{itemId}`
Unified inbox stream. Pre-written by trigger/denormalization CFs.

```
itemId         String
userId         String    Owner UID
type           String    "message" | "prayerRequest" | "churchNoteMention" |
                         "bereanAnswer" | "groupInvite" | "eventInvite" |
                         "mentorResponse" | "testimony"
tag            String    "Prayer" | "Testimony" | "Church" | "Community" |
                         "Mention" | "Berean" | "Event"
title          String    Sender name or event title (max 80 chars)
preview        String?   Content preview (max 160 chars, never full prayer body)
senderUid      String?
senderName     String?
senderAvatar   String?   Avatar URL
sourceRef      String    Deep link route to original content
isPinned       Boolean   Client-writable ("keep praying" pin)
isRead         Boolean   Client-writable
isArchived     Boolean   Client-writable
createdAt      Timestamp
aegisFlags     Map?
```

Index required: userId + createdAt DESC + isArchived == false

---

## New Collection 3: `spiritualOS_planner/{userId}/events/{eventId}`
Life Planner merged calendar events.

```
eventId        String
userId         String    Owner UID
sourceType     String    "spaceEvent" | "readingPlan" | "prayerPlan" |
                         "gathering" | "personalNote" | "bereanSuggestion"
title          String    (max 120 chars)
description    String?   (max 500 chars)
startDate      Timestamp
endDate        Timestamp?
isAllDay       Boolean   Default false
isCompleted    Boolean   Client-writable
spaceId        String?   If linked to a Space
sourceRef      String?   Deep link to original event/plan
bereanNote     String?   Gentle suggestion, max 140 chars. Dismissible. CF-written.
isBereanNote   Boolean   True if AI-originated
isDismissed    Boolean   Client-writable (dismisses berean suggestions)
color          String?   "amenGold" | "amenPurple" | "amenBlue"
createdAt      Timestamp
aegisFlags     Map?
```

Index required: userId + startDate ASC + isCompleted == false

---

## New Collection 4: `spiritualOS_context/{userId}` (single doc per user)
Live context state. CF-written only. Never retained beyond the document.

```
userId                String
mode                  String    "default" | "worship" | "driving" | "travel" | "focus" | "rest"
timeOfDay             String    "morning" | "afternoon" | "evening" | "night"
isSundayChurchTime    Boolean
isNearChurch          Boolean   Only set if geofenceOptIn == true
isDriving             Boolean   Motion-detected, clears feed, activates audio
isTraveling           Boolean   Surfaces nearby churches
lastUpdated           Timestamp
userPermissions       Map       { locationEnabled, motionEnabled, geofenceOptIn, audioAutoPlay : Boolean }
aegisAuditRef         String?   Ref to Aegis audit log for permission grant
```

Privacy: Never synced except via updateContextState CF. Deleted on logout.

---

## New Collection 5: `spiritualOS_suggestions/{userId}/items/{itemId}`
Berean contextual suggestion chips for AssistantBar and surface nudges.

```
itemId         String
userId         String    Owner UID
surfaceContext String    "home" | "hub" | "planner" | "space" | "commandCenter" | "assistantBar"
promptLabel    String    Short chip label (max 28 chars)
promptText     String    Full prompt sent to Berean on tap (max 200 chars)
isDismissed    Boolean   Client-writable
priority       Number    0–100 CF-assigned
expiresAt      Timestamp Default: 24 hours from creation
createdAt      Timestamp
```

---

## New Collection 6: `spiritualOS_spaceCreateDrafts/{userId}/drafts/{draftId}`
Create Space payload drafts. Client-writable by owner until submitted, then Cloud Function validates and creates/updates the real Space.

```
draftId          String
userId           String    Owner UID
name             String    Max 80 chars
description      String?   Max 500 chars
coverImageURL    String?
privacy          String    "public" | "private" | "churchOnly"
memberRoles      Map       { uid: "leader" | "member" | "moderator" | "pastor" }
featureToggles   Map       { churchNotes, bereanAsMember, events, resources, prayerWall : Boolean }
moderation       Map       { aegisEnabled, pastorReviewRequired, aiPrecheckEnabled : Boolean }
encryptedPrayer  Boolean   Required true before private prayer wall can be enabled
bereanMember     Map?      { enabled: Boolean, displayName: String, scope: "study" | "prayer" | "full" }
status           String    "draft" | "submitted" | "created" | "discarded"
createdAt        Timestamp
updatedAt        Timestamp
aegisFlags       Map?      Required when private prayer, pastoral role, or vulnerable-user data is present
```

---

## New Collection 7: `spiritualOS_commandCenter/{userId}/aggregates/{aggregateId}`
Private formation overview aggregates. Cloud Function-written. Client read-only except dismissing cards.

```
aggregateId       String    "overview" or server-generated card id
userId            String    Owner UID
type              String    "overview" | "community" | "note" | "bereanSession" | "event" | "readingProgress"
title             String    Max 80 chars
summary           String?   Max 240 chars
count             Number?   Private only; never comparative
progressValue     Number?   0.0-1.0 for private progress rings
sourceRef         String?   Deep link route
isDismissed       Boolean   Client-writable
updatedAt         Timestamp
aegisFlags        Map?
```

Formation counts in this collection are private, opt-in, and secondary. No rank, percentile, leaderboard, public badge, or guilt language may be derived from these fields.

---

## Collection 8: `spaces/{spaceId}` - Additive Fields Only
Do NOT alter existing Space fields. These are NEW fields added to existing documents.

```
[NEW] heroCardEnabled       Boolean    Default false. Per-space feature flag.
[NEW] activePrayerCount     Number     Denormalized CF-maintained count. Private.
[NEW] currentStudySeries    String?    Current Berean study series title.
[NEW] currentStudyRef       String?    Route to study.
[NEW] dashboardUpdatedAt    Timestamp  HeroCard data freshness.
[NEW] bereanMemberId        String?    Pseudo-UID if Berean added as space member.
[NEW] encryptedPrayerWall   Boolean    Default false. E2E prayer encryption.
```

---

## Formation Count Rules
- NEVER shown comparatively (no leaderboards, no peer comparison)
- NEVER a primary screen element (must be secondary, dismissible, opt-in)
- Always labeled with formation language ("days in the Word", not "streak")
- `activePrayerCount` in Spaces: prayer hands icon badge only, not a social engagement metric

---

## Aegis Integration
Documents with non-empty `aegisFlags` route through `AmenConnectSpacesAegisService` before display.

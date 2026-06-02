# Data Models Contract — Spiritual OS
## STATUS: FROZEN · Do not edit without Lead Orchestrator sign-off

All new Firestore schemas are documented here. Agents must use exactly
these field names and types — no client-side schema drift.

---

## Collection Map

```
users/{uid}/
  dailyDigest/{date}/            ← Agent A
  hubItems/{itemId}/             ← Agent B
  lifePlannerEvents/{eventId}/   ← Agent C
  contextState (single doc)      ← Agent H
  commandCenter (single doc)     ← Agent F

spaces/{spaceId}/                ← Agents D + E
  members/{uid}/
  events/{eventId}/
  prayerRequests/{requestId}/
  studySeries/{seriesId}/

suggestions/{uid}/               ← Agent G (global, user-scoped)
```

---

## 1. Daily Digest — `users/{uid}/dailyDigest/{date}`

Document ID = `YYYY-MM-DD` (today's date, UTC).  
Written by CF `generateDailyDigest` at 6 AM local (scheduled).

```typescript
interface DailyDigest {
  uid: string;
  date: string;                      // "2026-06-01"
  generatedAt: Timestamp;

  greeting: string;                  // "Good morning, {name}…" — from Berean AI
  dailyVerse: {
    reference: string;               // "Romans 8:28"
    text: string;
    translation: string;             // "NIV"
  };

  prayerReminders: PrayerReminder[]; // max 5 pending prayer items
  spaceEvents: SpaceEventSummary[];  // next 48h events user is member of
  mentions: MentionSummary[];        // unread @mentions across OpenTable + Notes
  savedStudies: StudySummary[];      // pinned Berean sessions
  birthdays: BirthdayEntry[];        // today's birthdays in connections

  todayItems: TimelineItem[];        // ordered daily timeline (mixed types)

  // Formation metrics — private, never shared
  readingStreakDays: number;         // consecutive days of reading plan
  prayerCountThisWeek: number;       // private count only
  aegisFlags: {
    location: boolean;               // was location used?
    geofenceActive: boolean;
  };
}

interface PrayerReminder {
  requestId: string;
  authorName: string;
  snippet: string;                   // max 120 chars
  daysSincePosted: number;
  spaceId: string | null;
}

interface SpaceEventSummary {
  spaceId: string;
  spaceName: string;
  eventTitle: string;
  startsAt: Timestamp;
  coverTintHex: string;              // hex for HeroCard tint
}

interface MentionSummary {
  postId: string;
  authorName: string;
  snippet: string;
  mentionedAt: Timestamp;
  surface: "openTable" | "churchNotes" | "spaces";
}

interface StudySummary {
  sessionId: string;
  topic: string;
  lastOpenedAt: Timestamp;
  progressPercent: number;           // 0–100, private
}

interface BirthdayEntry {
  uid: string;
  displayName: string;
  avatarURL: string;
}

interface TimelineItem {
  id: string;
  type: "verse" | "prayer" | "event" | "mention" | "study" | "birthday" | "note";
  title: string;
  subtitle: string | null;
  timestamp: Timestamp | null;
  deepLink: string;                  // internal route, not a URL
  isCompleted: boolean;
  spaceId: string | null;
}
```

**Aegis flags:** `readingStreakDays` and `prayerCountThisWeek` are NEVER returned in public APIs. The Firestore rule restricts this document to `request.auth.uid == uid`.

---

## 2. Unified Hub Items — `users/{uid}/hubItems/{itemId}`

Fan-out written by Cloud Functions. Client reads via real-time listener.

```typescript
interface HubItem {
  id: string;
  uid: string;
  createdAt: Timestamp;
  readAt: Timestamp | null;
  archivedAt: Timestamp | null;
  pinnedAt: Timestamp | null;        // "Keep Praying" pin

  type: HubItemType;
  faithTag: FaithTag;                // primary classification

  // Polymorphic payload (only relevant fields populated per type)
  payload: {
    title: string;
    subtitle: string | null;
    bodySnippet: string | null;      // max 200 chars
    authorName: string;
    authorAvatarURL: string;
    deepLink: string;                // internal route
    spaceId: string | null;
    spaceRole: SpaceRole | null;
  };
}

type HubItemType =
  | "directMessage"
  | "prayerRequest"
  | "prayerResponse"
  | "churchNoteMention"
  | "bereanAnswer"
  | "spaceInvite"
  | "eventInvite"
  | "mentorResponse"
  | "groupUpdate";

type FaithTag = "Prayer" | "Testimony" | "Church" | "Community" | "Berean";
type SpaceRole = "leader" | "pastor" | "moderator" | "member";
```

**Index required:** `uid ASC, createdAt DESC` (composite, partial filter on `archivedAt == null`).  
**Aegis:** `prayerRequest` and `prayerResponse` items are routed through `AegisGuardianHook` before write.

---

## 3. Life Planner Events — `users/{uid}/lifePlannerEvents/{eventId}`

Merged view of Space events (mirrored) + personal items created by user.

```typescript
interface LifePlannerEvent {
  id: string;
  uid: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;

  source: "personal" | "spaceEvent" | "readingPlan" | "prayerPlan";
  sourceId: string | null;           // spaceId or planId if mirrored

  title: string;
  notes: string | null;
  startsAt: Timestamp;
  endsAt: Timestamp | null;
  isAllDay: boolean;
  isCompleted: boolean;
  completedAt: Timestamp | null;

  bereanSuggestion: string | null;   // gentle study prompt from Berean AI
  bereanSuggestionDismissed: boolean;

  spaceId: string | null;
  spaceName: string | null;
  coverTintHex: string | null;
}
```

**Note:** Space events are mirrored into `lifePlannerEvents` by CF `mirrorSpaceEventToPlanner` when a user RSVPs or is a member. Client does NOT read directly from `spaces/{spaceId}/events/` for the planner view.

---

## 4. Spaces — `spaces/{spaceId}`

Top-level Space document.

```typescript
interface Space {
  id: string;
  ownerId: string;                   // user who created
  createdAt: Timestamp;
  updatedAt: Timestamp;

  name: string;                      // max 60 chars
  description: string;               // max 500 chars
  coverImageURL: string | null;
  coverTintHex: string;              // one of amenGold/amenPurple/amenBlue hex
  churchAffiliation: string | null;  // "First Baptist" etc.
  liturgicalTagIds: string[];        // e.g. ["advent", "lent"]

  privacy: "public" | "private" | "secret";
  encryptionEnabled: boolean;        // for private prayer Spaces
  moderationEnabled: boolean;
  memberCount: number;               // denormalized

  features: SpaceFeatures;
  bereanMemberId: string | null;     // if Berean AI added as resident member

  // Current study series
  activeSeriesId: string | null;
  activeSeriesTitle: string | null;
}

interface SpaceFeatures {
  churchNotes: boolean;
  bereanAsResident: boolean;
  events: boolean;
  resources: boolean;
  prayerWall: boolean;
}
```

### Members — `spaces/{spaceId}/members/{uid}`

```typescript
interface SpaceMember {
  uid: string;
  displayName: string;
  avatarURL: string;
  role: SpaceRole;
  joinedAt: Timestamp;
  invitedBy: string | null;
  notificationsEnabled: boolean;
}
```

### Events — `spaces/{spaceId}/events/{eventId}`

```typescript
interface SpaceEvent {
  id: string;
  spaceId: string;
  createdBy: string;
  createdAt: Timestamp;

  title: string;
  description: string | null;
  startsAt: Timestamp;
  endsAt: Timestamp | null;
  isOnline: boolean;
  locationLabel: string | null;      // human-readable, never raw coords

  rsvpCount: number;                 // denormalized
  rsvpUids: string[];                // max 100 stored inline; overflow → subcollection
}
```

### Prayer Requests — `spaces/{spaceId}/prayerRequests/{requestId}`

```typescript
interface SpacePrayerRequest {
  id: string;
  spaceId: string;
  authorUid: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;

  text: string;                      // max 2000 chars
  isAnonymous: boolean;
  isClosed: boolean;
  closedAt: Timestamp | null;
  prayerCount: number;               // private-ish — visible only to request author

  aegisFlags: {
    crisisEscalated: boolean;
    moderationApplied: boolean;
  };
}
```

**Aegis:** All prayer request writes pass through `aegisGuardian` CF. Crisis signals trigger `AegisGuardianHook`. `authorUid` is hidden from non-members when `isAnonymous == true`.

---

## 5. Context State — `users/{uid}/contextState` (single doc)

Written by the Context Engine (CF + on-device). Read by all surfaces.

```typescript
interface ContextState {
  uid: string;
  updatedAt: Timestamp;

  mode: ContextMode;
  subMode: string | null;            // e.g. "drivingLong", "sundayMorning"

  geofenceActive: boolean;
  nearbyChurchId: string | null;     // resolved church ID, not raw location
  nearbyChurchName: string | null;

  isDriving: boolean;
  isTraveling: boolean;
  timeOfDay: "morning" | "midday" | "evening" | "night";
  dayOfWeek: number;                 // 0=Sun … 6=Sat

  // Consent flags — user controls each individually
  locationConsentGranted: boolean;
  motionConsentGranted: boolean;
  calendarConsentGranted: boolean;

  // Ephemeral — cleared after 30 min
  lastKnownEventCheckIn: string | null;  // eventId
}

type ContextMode =
  | "default"
  | "worshipMode"      // Sunday + church geofence
  | "driveMode"        // motion + driving
  | "travelMode"       // travel detected
  | "eveningReflection"; // evening + no active context
```

**Privacy rules:** `contextState` document is `uid`-scoped. The CF never logs raw lat/lng — only resolved IDs (church, event). Location data is discarded after resolution. The `contextState` document does NOT contain coordinates.

---

## 6. Command Center — `users/{uid}/commandCenter` (single doc)

Aggregated private formation overview. Written by scheduled CF.

```typescript
interface CommandCenter {
  uid: string;
  updatedAt: Timestamp;

  spaces: SpaceSummary[];            // active spaces user is member of
  savedNotesCount: number;           // private
  bereanSessionsCount: number;       // private
  upcomingEventsCount: number;       // private
  readingPlanProgress: number;       // 0.0–1.0, private

  // Streaks — private, gentle, opt-in only
  streakDays: number | null;         // null if user opted out
  streakOptIn: boolean;
}

interface SpaceSummary {
  spaceId: string;
  spaceName: string;
  role: SpaceRole;
  coverTintHex: string;
  unreadHubItems: number;
  nextEventAt: Timestamp | null;
}
```

**Formation UI rule:** `streakDays` is NEVER displayed as a headline number. Shown only as warm `GlassChip` text ("Active this week") when > 0. Color: `amenGold`, never red/orange.

---

## 7. Suggestions — `suggestions/{uid}` (single doc)

Smart prompts served by `generateSmartSuggestions` CF.

```typescript
interface UserSuggestions {
  uid: string;
  updatedAt: Timestamp;
  ttlSeconds: number;                // client-side cache TTL

  suggestions: Suggestion[];         // max 10, ordered by priority
}

interface Suggestion {
  id: string;
  surface: SOSurface;                // which surface should show this
  promptText: string;                // "Romans 12 — ready to read?"
  iconSymbol: string;                // SF Symbol name
  tintColor: string;                 // amenGold/amenPurple/amenBlue
  priority: number;                  // 0–100, higher = show first
  expiresAt: Timestamp;
  deepLink: string;                  // where tapping takes user
  bereanSessionSeed: string | null;  // pre-seeded Berean context if applicable
}
```

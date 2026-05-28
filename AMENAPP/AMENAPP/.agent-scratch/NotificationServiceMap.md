# Notification Service Ownership Map
Generated: 2026-05-28

---

## Services

| Service | File (relative to AMENAPP/) | Owns | Does NOT Own |
|---|---|---|---|
| NotificationService | `NotificationService.swift` | AppNotification model; Firestore real-time listener; read-state (mark read/all-read); deletion; mention + church-note write helpers; inbox-opened analytics | Priority scoring, batching, re-engagement copy, action-thread delivery, push dispatch |
| NotificationServiceExtensions | `NotificationServiceExtensions.swift` | Follow-notification deduplication in memory; deleteFollowNotification on unfollow; Firestore cleanup of duplicate follow docs | Every notification type except `.follow` |
| SmartNotificationEngine | `SmartNotificationEngine.swift` | Priority scoring (0-100) based on recency, type weight, relationship score, engagement bonus; smart grouping ("John and 5 others"); batch priority calculation; engagement-score persistence | Delivery, Firestore writes, FCM push, quiet-hours, batching, re-engagement copy |
| SmartNotificationService | `SmartNotificationService.swift` | Social-activity batching (prayers, amens, comments, follows, reposts, mentions) with day-bucket deduplication key; scheduling batch delivery via userNotificationPreferences; AI-learned delivery timing | Priority scoring, action-thread events, spiritual-rhythm gating, raw per-notification Firestore reads |
| SmartNotificationTimingService | `SmartNotificationTimingService.swift` | Tracking app opens by hour/day into Firestore usagePatterns; computing optimal send hour (peak - 1 hr); isNearPeakUsage() predicate | Notification delivery, Firestore notification writes, push dispatch, priority scoring, batching |
| NotificationAggregationService | `NotificationAggregationService.swift` | Foreground suppression (user viewing related post/conversation/profile); self-action suppression; block-list Firestore check; aggregation-window detection (30 min); Instagram-style grouped copy | Delivery, Firestore notification writes, push dispatch, action-thread events, spiritual-rhythm gating |
| NotificationDigestService | `NotificationDigestService.swift` | Loading/displaying daily digests from notificationDigests collection; grouping items by NotificationCategory; delivering daily-summary push via pendingNotifications CF trigger; marking digest opened + bulk-marking read | Creating notifications, priority scoring, batching social events, re-engagement copy |
| NotificationGenkitService | `NotificationGenkitService.swift` | AI-generated notification copy via generateNotificationText CF; AI summarization via summarizeNotifications CF; timing optimization using usagePatterns; end-to-end sendSmartNotification flow; batch summary (3+ notifications) | Action-thread events, re-engagement scheduling, spiritual-rhythm gating, quiet-hours enforcement, follow-dedup |
| NotificationSettingsService | `NotificationSettingsService.swift` | Read/write users/{uid}/settings/notifications; preference(for:) lookup used by other services; default settings initialization | Delivery of any type, priority scoring, batching, re-engagement copy, quiet-hours enforcement |
| ActionableNotificationService | `ActionableNotificationService.swift` | **Central send path** for all NotificationCategory types; atomic Firestore batch (in-app + pendingNotifications push entry); like rollup (1 doc per post, Firestore transaction); UNNotificationAction generation; quiet-hours + per-category toggle + privacy level + channel routing (push/inApp/digest/silent/suppress); handleAction() for notification button taps | Re-engagement copy, action-thread delivery, prayerAnswered fan-out, AI copy generation, batching windows |
| ActionThreadNotificationService | `ActionThreads/ActionThreadNotificationService.swift` | actionThreadInvite, actionThreadUpdate, actionThreadReminder — all action-thread notification writes to Firestore; in-memory rate limiting (max 10/hour per user) | General social-activity notifications, prayer notifications, re-engagement, priority scoring, push dispatch |
| PrayerAnsweredNotificationService | `PrayerAnsweredNotificationService.swift` | prayerAnswered fan-out — calls onPrayerAnswered Cloud Function; checks NotificationSettingsService prayerAnswered preference before dispatching | All other prayer types (prayerReminder, prayerSupported), in-app writes, social notifications, priority scoring |
| ReEngagementNotificationService | `ReEngagementNotificationService.swift` | AI-generated re-engagement push via bereanNotificationText CF (Claude API); scheduling UNNotificationRequest 2 h after app backgrounding via onAppBackgrounded() hook | Social-activity notifications, prayer/action-thread events, spiritual-rhythm gating, Firestore writes |
| CalmNotificationPolicyEngine | `CalmControl/CalmNotificationPolicyEngine.swift` | Client-side eligibility gating for 7 calm categories; inactivity-pause, sabbath-mode, presence-state, intensity-mode suppression; non-manipulative pre-written copy | Social-activity notifications, action-thread events, push delivery, Firestore writes |
| NotificationPolicyEngine (CalmControl/Services) | `AMENAPP/CalmControl/Services/NotificationPolicyEngine.swift` | Client-side AND server-side eligibility for AmenRhythmNotificationCategory; sabbath, inactivity pause, quiet hours (22:00–07:00), per-category toggle, intensity filter; evaluateEligibilityOnServer() → evaluateNotificationEligibility CF | Push delivery, Firestore writes, social-activity notifications, batching |
| SpiritualNotificationPolicyEngine | `AMENAPP/SpiritualRhythmOS/SpiritualNotificationPolicyEngine.swift` | Pure-logic (no Firebase) eligibility for SpiritualNotificationCategory; sabbath hard stop, inactivity pause, daily intensity cap, category toggle, duplicate-today guard; suggestedCopy() with variant rotation; scheduleNotificationCategories() → ScheduledNotificationConfig list for UNUserNotificationCenter | Push delivery, Firestore writes, social-activity notifications, batching |
| AMENNotificationServiceExtension | `AMENNotificationServiceExtension/NotificationService.swift` | UNNotificationServiceExtension: payload mutation before display; safety-state body replacement; title hydration from actorName + type | Notification creation, Firestore writes, priority scoring, batching, delivery — runs in separate process target |

---

## Notification Category Routing

| Category | Handled By | Backend Function / Collection |
|---|---|---|
| `dailyVerse` | CalmNotificationPolicyEngine / NotificationPolicyEngine / SpiritualNotificationPolicyEngine | `evaluateNotificationEligibility` CF; scheduled via UNUserNotificationCenter |
| `readingReminder` | CalmNotificationPolicyEngine / SpiritualNotificationPolicyEngine | `evaluateNotificationEligibility` CF; scheduled via UNUserNotificationCenter |
| `prayerReminder` | CalmNotificationPolicyEngine / SpiritualNotificationPolicyEngine | `evaluateNotificationEligibility` CF; scheduled via UNUserNotificationCenter |
| `communityDigest` | NotificationDigestService + CalmNotificationPolicyEngine / SpiritualNotificationPolicyEngine | `notificationDigests` collection → `pendingNotifications` CF trigger |
| `streakReminder` | CalmNotificationPolicyEngine / SpiritualNotificationPolicyEngine | `evaluateNotificationEligibility` CF; scheduled via UNUserNotificationCenter |
| `quietReturn` (re-engagement) | ReEngagementNotificationService + CalmNotificationPolicyEngine / SpiritualNotificationPolicyEngine | `bereanNotificationText` CF (Claude API); UNUserNotificationCenter local push |
| `milestoneReflection` | CalmNotificationPolicyEngine / SpiritualNotificationPolicyEngine | `evaluateNotificationEligibility` CF; scheduled via UNUserNotificationCenter |
| `amen` / reactions | ActionableNotificationService (channel routing) + SmartNotificationService (batching) + SmartNotificationEngine (priority) | `pendingNotifications` CF; `notificationBatches` collection |
| `comment` / `reply` | ActionableNotificationService + SmartNotificationService + NotificationService (mention write helper) | `pendingNotifications` CF; `notificationBatches` collection |
| `follow` / `followRequestAccepted` | ActionableNotificationService + NotificationServiceExtensions (dedup/cleanup) | `pendingNotifications` CF; Firestore `notificationBatches` |
| `mention` | ActionableNotificationService + NotificationService.sendMentionNotifications | `pendingNotifications` CF; direct Firestore write |
| `repost` | ActionableNotificationService + SmartNotificationService | `pendingNotifications` CF; `notificationBatches` |
| `message` / `messageRequest` / `messageRequestAccepted` | ActionableNotificationService (channel: .directMessages / .groupMessages) | `pendingNotifications` CF |
| `actionThreadInvite` | ActionThreadNotificationService | Direct Firestore write to `users/{uid}/notifications` (idempotent doc ID) |
| `actionThreadUpdate` | ActionThreadNotificationService | Firestore batch write to all participants |
| `actionThreadReminder` | ActionThreadNotificationService | Direct Firestore write to `users/{uid}/notifications` |
| `prayerAnswered` | PrayerAnsweredNotificationService | `onPrayerAnswered` CF (fan-out to intercessors) |
| `prayerSupported` | ActionableNotificationService (.prayerUpdates) | `pendingNotifications` CF |
| `churchNoteShared` | NotificationService.sendChurchNoteSharedNotifications | Direct Firestore write |
| `churchNoteReplied` | ActionableNotificationService (.churchNotes) | `pendingNotifications` CF |
| Batch social activity | SmartNotificationService | `notificationBatches` collection → `scheduledBatches` CF trigger |
| In-app notification priority/sort | SmartNotificationEngine | Client-side only; no backend function |
| Foreground suppression | NotificationAggregationService | Client-side only; block check reads `users/{uid}/blocked` |
| Daily batched digest | NotificationDigestService | `notificationDigests` collection → `pendingNotifications` CF trigger |
| AI-personalized copy | NotificationGenkitService | `generateNotificationText` CF, `summarizeNotifications` CF |
| Payload mutation (OS extension) | AMENNotificationServiceExtension | Runs in OS extension process; no CF |

---

## Overlap and Duplication Notes

### Three Nearly-Identical Policy Engines (High Priority Consolidation)

The following three files each implement the same sabbath-mode / inactivity-pause / intensity-filter
policy for the same 7 spiritual-rhythm notification categories. They differ only in the types they
define and minor naming conventions:

| File | Type System |
|---|---|
| `CalmControl/CalmNotificationPolicyEngine.swift` | `CalmNotificationCategory`, `NotificationIntensityMode`, `NotificationEligibilityResult` |
| `AMENAPP/CalmControl/Services/NotificationPolicyEngine.swift` | `AmenRhythmNotificationCategory`, `AmenNotificationIntensity`, `AmenNotificationEligibility` |
| `AMENAPP/SpiritualRhythmOS/SpiritualNotificationPolicyEngine.swift` | `SpiritualNotificationCategory`, `SpiritualRhythmSettings`, `SpiritualNotificationEligibilityResult` |

### Two Overlapping Batching / Timing Layers

`SmartNotificationService` (batching windows, day-bucket dedup, AI timing preferences) and
`SmartNotificationTimingService` (usage-pattern tracking, optimal-send-hour cache) are complementary
but were built independently. `SmartNotificationTimingService` data is also consumed by
`NotificationGenkitService.optimizeTiming()`.

### Two AI Copy Generation Paths

`NotificationGenkitService` (general AI copy for any event type via `generateNotificationText` CF)
and `ReEngagementNotificationService` (re-engagement-specific copy via `bereanNotificationText` CF)
both call Cloud Functions to produce notification text. They are non-overlapping on category but
use different CF endpoints.

---

## Consolidation Recommendation

**Estimated effort: 1–2 weeks (see breakdown below).**

The single highest-ROI change is merging the three spiritual-rhythm policy engines
(CalmNotificationPolicyEngine, NotificationPolicyEngine, SpiritualNotificationPolicyEngine) into one
canonical `SpiritualRhythmPolicyEngine` with a single category enum and eligibility result type.
This eliminates ~600 lines of duplicated logic, one duplicated type system per file, and the risk
of the three engines drifting out of sync (e.g., one adding a new intensity level the others miss).

A second high-value change is designating `ActionableNotificationService` as the single authoritative
send path and removing the direct Firestore write calls scattered in `NotificationService`
(sendMentionNotifications, sendChurchNoteSharedNotifications) and `ActionThreadNotificationService`.
This ensures all notifications go through the same quiet-hours, category-toggle, and privacy-level
gates. `ActionThreadNotificationService` should become a thin category-specific façade that calls
`ActionableNotificationService.sendNotification()` rather than writing to Firestore directly.

Finally, `SmartNotificationService` (batching) and `SmartNotificationTimingService` (timing data)
could be merged into a single `NotificationBatchingAndTimingService`, as they share the same
conceptual concern and each is already consumed by the other layers.

### Estimated Work Breakdown

| Change | Effort |
|---|---|
| Merge 3 policy engines | 3–4 days (type migration, test updates) |
| Route ActionThread + Mention writes through ActionableNotificationService | 2 days |
| Merge SmartNotificationService + SmartNotificationTimingService | 1 day |
| Update all call sites + write contract tests | 2 days |
| **Total** | **~8–9 days** |

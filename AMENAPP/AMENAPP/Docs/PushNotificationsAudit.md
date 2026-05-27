# AMEN Push Notification System — Full Audit Report
**Date:** 2026-05-24  
**Branch:** audit/2026-05-21  
**Verdict:** GO WITH CAVEATS

---

## Architecture Map

```
iOS App
├── AppDelegate.swift                    — Firebase init, APNs registration, setupPushNotifications()
├── AppDelegate+Messaging.swift          — APNs device token handler, retry trigger [+ DEAD CODE: setupMessaging()]
├── CompositeNotificationDelegate        — UNUserNotificationCenterDelegate: block filter, Rest Mode, routing
├── PushNotificationManager              — FCM token mgmt, save → users/{uid}.fcmToken, badge
├── DeviceTokenManager                   — Multi-device tokens → users/{uid}/devices/{deviceId}
├── NotificationManager                  — Local prayer/reminder scheduling, settings → users/{uid}.notificationSettings
├── NotificationSettingsService          — Granular settings → users/{uid}/settings/notifications
├── NotificationsSettingsView            — Rich settings UI (wired to Firestore)
├── NotificationPermissionOnboarding     — 3-step glassmorphic onboarding sheet
├── BadgeCountManager                    — Real-time badge: Firestore listeners + RTDB mirror + drift recovery
├── NotificationService                  — Canonical inbox: notification_groups + legacy notifications fallback
├── AMENNotificationsView                — Inbox UI with Liquid Glass, smart actions, filter chips
├── NotificationTapHandler               — Push tap → in-app routing
├── DeepLinkRouter                       — URL routing with auth + content validation
└── ProductionNotificationRouting.swift  — Typed routing enums and safe-open logic

Backend (Cloud Functions)
├── functionssrcnotifications.ts         — V1 triggers: follow, amen, comment, message → notifications collection
├── CloudFunction_NotificationRoutingPipeline.ts — V2 canonical: activity_events → notification_groups → FCM
├── CloudFunction_SendMessageNotification.ts     — DM notification callable
└── BACKEND_GENKIT_NOTIFICATIONS.ts             — Genkit AI notification body generation

Firestore Collections
├── users/{uid}                          — profile + fcmToken (legacy single-token field)
├── users/{uid}/devices/{deviceId}       — multi-device token records (DeviceTokenManager)
├── users/{uid}/settings/notifications   — granular preference doc (NotificationSettingsService)
├── users/{uid}/notificationSettings     — legacy inline field (NotificationManager)
├── notifications/{id}                   — V1 flat inbox records
├── notification_groups/{id}             — V2 canonical grouped records (read by NotificationService)
├── activity_events/{id}                 — V2 event source records
├── pending_notifications/{id}           — V2 delivery queue
└── notification_delivery_logs/{id}      — V2 delivery audit trail
```

---

## Duplicate Service Matrix

| Duplicate | Files | Active? | Risk | Action |
|-----------|-------|---------|------|--------|
| FCM token storage (flat) | PushNotificationManager.saveFCMTokenToFirestore() → users/{uid}.fcmToken | YES | HIGH — V1 Cloud Functions only read this path; multi-device sends never reach DeviceTokenManager subcollection | Keep both: flat field for V1 compat, subcollection for multi-device |
| FCM token storage (subcollection) | DeviceTokenManager → users/{uid}/devices/{deviceId} | YES | MEDIUM — backend ignores subcollection | Keep; wire backend to send to all active device tokens |
| Notification settings (flat) | NotificationManager → users/{uid}.notificationSettings | YES | MEDIUM | Migration target |
| Notification settings (subcollection) | NotificationSettingsService → users/{uid}/settings/notifications | YES | MEDIUM | Canonical path going forward |
| Notification settings (direct write) | NotificationsSettingsView Firestore writes | YES | LOW | Refactor to NotificationSettingsService |
| setupMessaging() | AppDelegate+Messaging.swift | NO — never called | LOW — dead code confusion | REMOVED in this audit |
| FCM documentation code | FCM_CODE_SNIPPETS.swift, FCM_TOKEN_INTEGRATION_GUIDE.swift | NO — canImport(NeverImport) guard | LOW | Keep as reference; never compiles |
| V1 + V2 notification pipeline | functionssrcnotifications.ts vs CloudFunction_NotificationRoutingPipeline.ts | Both active | HIGH — potential double-send if both trigger on same collection | Audit trigger overlap; V2 is preferred |

---

## Token Lifecycle Matrix

| Stage | PushNotificationManager | DeviceTokenManager | Status |
|-------|------------------------|-------------------|--------|
| Permission granted | requestNotificationPermissions() | — | ✅ |
| APNs token received | AppDelegate sets Messaging.apnsToken | — | ✅ |
| FCM token received | MessagingRegistrationTokenRefreshed → saveFCMTokenToFirestore() | "FCMTokenRefreshed" observer (WRONG NAME) | ⚠️ FCM_BUG_1 |
| FCM token saved | users/{uid}.fcmToken | users/{uid}/devices/{deviceId} | ✅ Both paths |
| Token refresh (MessagingDelegate) | fcmTokenRefreshed() → save | does NOT receive (wrong name) | ⚠️ FCM_BUG_1 |
| Sign-out cleanup | removeFCMTokenFromFirestore() | unregisterDeviceToken() via AppLifecycleManager | ✅ Both called |
| Offline sign-out retry | — | retryPendingFCMDeactivationIfNeeded() | ✅ |
| Stale token cleanup | — | cleanupInvalidTokens() after 90 days | ✅ |
| Device limit enforcement | — | enforceDeviceLimit() max 5 | ✅ |
| Email-not-verified guard | ✅ skips save | ✅ skips save | ✅ |
| Simulator guard | ✅ skips FCM | — | ✅ |
| Test host guard | AppDelegate returns early | — | ✅ |

**FCM_BUG_1:** `DeviceTokenManager.setupTokenRefreshObserver()` listens for `Notification.Name("FCMTokenRefreshed")` (a custom name that nothing posts) instead of `Notification.Name.MessagingRegistrationTokenRefreshed` (the Firebase SDK name). Multi-device token refresh therefore never fires through DeviceTokenManager. **FIXED in this audit.**

---

## Notification Trigger Matrix

| Event | V1 Function | V2 Pipeline | Deduped? | Block Check? | Quiet Hours? | Privacy Preview? |
|-------|------------|-------------|----------|-------------|-------------|-----------------|
| New follower | onFollowCreated ✅ | — | ❌ | ❌ | ❌ | N/A (no private content) |
| Amen on post | onAmenCreated ✅ | — | ❌ | ❌ | ❌ | N/A |
| Comment on post | onCommentCreated ✅ | — | ❌ | ❌ | ❌ | ⚠️ RAW TEXT LEAK |
| New message | onMessageCreated ✅ | — | ❌ | ❌ | ❌ | ⚠️ RAW TEXT LEAK |
| Prayer update | — | V2 routing ✅ | ✅ (groupKey) | — | — | ✅ privacySafePreview |
| Scripture shared | — | V2 routing ✅ | ✅ | — | — | ✅ |
| Church update | — | V2 routing ✅ | ✅ | — | — | ✅ |
| Berean insight | — | V2 routing ✅ | ✅ | — | — | ✅ |
| Selah reflection | — | V2 routing ✅ | ✅ | — | — | ✅ |
| Mention | — | V2 routing ✅ | ✅ | — | — | ✅ |
| Repost | — | V2 routing ✅ | ✅ | — | — | ✅ |
| Daily Digest | Scheduled ✅ | — | — | — | — | N/A |

**FIXES APPLIED in this audit to V1 functions:**
- Comment notification: replaced raw `commentText` with generic "Someone commented on your post" unless `privacyLevel === "public"`
- Message notification: replaced raw `messageText` with "You have a new message" generic preview
- Added block check (`blockedUsers` subcollection) before sending for follow/amen/comment/message
- Added deduplication via deterministic Firestore document IDs for all V1 triggers

---

## Preference Enforcement Matrix

| Preference Key | Stored At | Backend Enforced? | UI Location |
|---------------|-----------|------------------|------------|
| allowNotifications | users/{uid} | ✅ V1 checks | NotificationsSettingsView |
| messageNotifications | users/{uid} | ✅ V1 checks participantData | NotificationsSettingsView |
| commentNotifications | users/{uid} | ✅ V1 | NotificationsSettingsView |
| amenNotifications | users/{uid} | ✅ V1 | NotificationsSettingsView |
| followNotifications | users/{uid} | ✅ V1 | NotificationsSettingsView |
| quietHoursEnabled | UserDefaults + users/{uid}.notificationSettings | ❌ CLIENT ONLY | NotificationPermissionOnboarding, EnhancedQuietHoursView |
| pushPreviewPrivacy | UserDefaults | ❌ CLIENT ONLY | NotificationsSettingsView |
| prayerIntercessors | users/{uid}/settings/notifications | ❌ V2 pipeline only | NotificationSettingsView |
| weeklyDigest | users/{uid}/settings/notifications | ❌ V2 pipeline only | NotificationsSettingsView |

**CAVEAT:** Quiet hours and push preview privacy are client-side only in the V1 pipeline. The V2 canonical pipeline respects `privacyLevel` in `privacySafePreview()` but does not yet read quiet hours from Firestore. Full server-side quiet hours enforcement requires a dedicated backend pass.

---

## Push Privacy Matrix

| Content Type | V1 Push Body | V2 Push Body | Risk |
|-------------|-------------|-------------|------|
| Direct message text | ⚠️ RAW (FIXED) | Not sent via V1 | CRITICAL → FIXED |
| Comment text | ⚠️ RAW (FIXED) | V2 uses privacySafePreview | CRITICAL → FIXED |
| Prayer request body | Not sent via V1 | ✅ Generic if protected | OK |
| Private group name | Not in V1 | ✅ Not exposed | OK |
| Blocked sender name | ⚠️ Was sent (FIXED) | — | HIGH → FIXED |
| Crisis/pastoral content | Not in V1 | ✅ pastoral_care class → generic | OK |
| Selah reflection text | Not in V1 | ✅ privacySafePreview | OK |

---

## Deep Link Routing Matrix

| Route | Parsed? | Auth Check? | Content Check? | Fallback? |
|-------|---------|------------|---------------|----------|
| amen://post/{id} | ✅ | Implicit (signed-in only) | ✅ checks isRemoved | ✅ "Content Unavailable" |
| amen://user/{id} | ✅ | Implicit | ✅ checks doc.exists | ✅ |
| amen://church/{id} | ✅ | Implicit | ✅ | ✅ |
| amen://conversation/{id} | ✅ | ✅ requires auth | ✅ | ✅ |
| amen://comment | ✅ | Implicit | ✅ (post check) | ✅ |
| amen://notification | ✅ | — | None | ✅ |
| Shabbat-blocked routes | ✅ | ✅ AppAccessController | — | ✅ → tab 3 |
| Malformed URL | — | — | — | ✅ parse returns nil |
| Missing prayer deep link | ❌ NOT IN ROUTER | — | — | None |
| Missing event deep link | ❌ NOT IN ROUTER | — | — | None |
| Missing Berean deep link | ❌ NOT IN ROUTER | — | — | None |

**CAVEAT:** Prayer, event, and Berean deep links are handled by the V2 routing pipeline's `buildRoute()` but are NOT wired into `DeepLinkRouter.swift`'s `parse()` function. Push taps from V2 notifications use `NotificationTapHandler` (separate path) so this gap does not block delivery, but universal link routing and QA testing of these routes requires adding the cases.

---

## Notification Inbox Button Matrix

| Button / Action | Wired? | Handler |
|----------------|--------|---------|
| Mark All Read | ✅ | NotificationService.markAllAsReadByExplicitUserAction() |
| Dismiss (swipe) | ✅ | NotificationService.dismissNotification() |
| Tap notification row | ✅ | NotificationTapHandler.handle() |
| "Pray Now" action | ✅ | NotificationService.createPrayerSupportAction() |
| "Reply" action | ✅ | Posts NotificationCenter notification → openReplyComposerFromNotification |
| "Send Update" action | ✅ | Posts → openPrayerUpdateComposerFromNotification |
| "Save Verse" action | ✅ | NotificationService.saveVerse() |
| "Open Berean" action | ✅ | NotificationTapHandler.handle() |
| "Add to Calendar" action | ✅ | Posts → openCalendarEventFromNotification |
| "View Update" / "Open Notes" | ✅ | NotificationTapHandler.handle() |
| Focus Mode toggle | ✅ | UserDefaults + filter rebuild |
| Filter chip selection | ✅ | rebuildProcessedNotifications() |
| Mark single as read | ✅ (via tap) | NotificationService.markNotificationOpened() |
| Empty state | ✅ | AMENNotificationsView |
| Error state | ✅ | NotificationService.error published |
| Loading state | ✅ | NotificationService.isLoading |
| Pagination | ✅ (maxNotifications=100) | — |

**All inbox buttons are wired. No dead buttons found.**

---

## Badge Count Matrix

| Scenario | Handled? | Notes |
|----------|---------|-------|
| App icon badge | ✅ | UNUserNotificationCenter.setBadgeCount |
| In-app tab badge | ✅ | BadgeCountManager.totalBadgeCount |
| Messages tab sub-badge | ✅ | BadgeCountManager.unreadMessages |
| Notifications tab sub-badge | ✅ | BadgeCountManager.unreadNotifications |
| Mark read clears badge | ✅ | clearNotifications() + suppression window |
| Sign-out clears badge | ✅ | stopRealtimeUpdates() → clearBadge() |
| Multi-device sync | ✅ | RTDB mirror via syncBadgeCountToRTDB Cloud Function |
| Negative count | ✅ prevented | count is always ≥ 0 (unsigned result from snapshot count) |
| Badge drift recovery | ✅ | V2 server-side unseenCount listener + reconciliation |
| Offline fallback | ✅ | UserDefaults persist + 10-minute TTL |
| Widget sync | ✅ | WidgetCenter.shared.reloadAllTimelines() |
| 0→N stale flip after markAllRead | ✅ | 5-second suppression window |

---

## Firestore Rules Matrix

| Collection | Read | Write | Missing Rule? |
|-----------|------|-------|--------------|
| users/{uid} | `if true` (PUBLIC!) | owner only | ⚠️ FCM token exposed |
| users/{uid}/devices | **NONE** | **NONE** | ⚠️ ADDED in this audit |
| users/{uid}/settings | **NONE** | **NONE** | ⚠️ ADDED in this audit |
| users/{uid}/notifications | **NONE** | **NONE** | ⚠️ ADDED in this audit |
| notifications/{id} | owner (userId field) | `if isSignedIn()` (TOO OPEN) | ⚠️ TIGHTENED in this audit |
| notification_groups | **NONE** | **NONE** | ⚠️ ADDED in this audit |
| activity_events | **NONE** | **NONE** | ⚠️ ADDED in this audit |
| pending_notifications | **NONE** | **NONE** | ⚠️ ADDED in this audit |
| conversations | participant only | ✅ | OK |
| posts | signedIn | ✅ | OK |
| blockedUsers | owner | ✅ | OK |

---

## Cloud Functions Matrix

| Function | Auth? | App Check? | Rate Limit? | Invalid Token Handling? | Retry Safe? |
|---------|-------|-----------|------------|------------------------|------------|
| onFollowCreated (V1) | Via Firestore auth | ❌ | N/A (trigger) | ❌ no FCM error handling | ⚠️ no dedupeKey (FIXED) |
| onAmenCreated (V1) | Via Firestore auth | ❌ | N/A | ❌ | ⚠️ (FIXED) |
| onCommentCreated (V1) | Via Firestore auth | ❌ | N/A | ❌ | ⚠️ (FIXED) |
| onMessageCreated (V1) | Via Firestore auth | ❌ | N/A | ❌ | ⚠️ (FIXED) |
| Canonical pipeline (V2) | Via Firestore auth | ❌ | N/A | ✅ dead letter queue | ✅ deterministic IDs |
| sendGatheringReminder | Callable | ❌ | ❌ | — | — |

**CAVEAT:** App Check is not enforced on any notification Cloud Function. Recommended for all callables that touch user data. Cannot implement without Firebase project access.

---

## Analytics / Observability Matrix

| Event | Tracked? | Safe? |
|-------|---------|-------|
| Permission screen viewed | ❌ | — |
| Permission prompt requested | ❌ | — |
| Permission granted/denied | Partial (dlog only) | ✅ no PII |
| Token registered | Partial (dlog only) | ✅ |
| Token refresh success/fail | Partial (dlog only) | ✅ |
| Notification preference changed | ❌ | — |
| Notification opened | ✅ (NotificationService.markNotificationOpened) | ✅ |
| Deep link success/fail | ✅ (dlog + analytics label) | ✅ |
| Notification deduped | ❌ | — |

---

## Test Coverage Matrix

| Test Area | Tests Exist? | Notes |
|-----------|-------------|-------|
| Firestore rules — token owner-only | ❌ | No rules tests found |
| Firestore rules — server-only delivery writes | ❌ | — |
| Firestore rules — preference owner-only | ❌ | — |
| iOS permission flow | ❌ | — |
| BadgeCountManager | ❌ | — |
| NotificationService | ❌ | — |
| DeepLinkRouter parse() | ❌ | — |
| Privacy preview enforcement | ❌ | — |
| ProductionAuditTests | ✅ | AMENAPPTests/ProductionAuditTests.swift exists |

---

## Issues Found and Fixed

### CRITICAL — Fixed in this audit

| ID | Issue | File | Fix |
|----|-------|------|-----|
| C1 | Raw direct message text in push body | functionssrcnotifications.ts:onMessageCreated | Generic "You have a new message" preview |
| C2 | Raw comment text in push body | functionssrcnotifications.ts:onCommentCreated | Generic "Someone commented on your post" |
| C3 | Blocked sender can trigger notifications | functionssrcnotifications.ts (all triggers) | Block check before send |
| C4 | No deduplication — retried functions double-send | functionssrcnotifications.ts (all triggers) | Deterministic Firestore doc IDs as dedupeKey |
| C5 | Missing Firestore rules for 4 subcollections | COMPLETE_FIRESTORE_RULES.txt | Added devices, settings/notifications, notifications, notification_groups |
| C6 | Any signed-in user can create notifications for others | COMPLETE_FIRESTORE_RULES.txt | Restricted to server-side (no client create) |

### HIGH — Fixed in this audit

| ID | Issue | File | Fix |
|----|-------|------|-----|
| H1 | DeviceTokenManager listens for wrong FCM refresh notification name | DeviceTokenManager.swift:342 | Changed to Notification.Name.MessagingRegistrationTokenRefreshed |
| H2 | Dead setupMessaging() duplicates setupPushNotifications() | AppDelegate+Messaging.swift | Removed dead method |

### CAVEATS (require Firebase project / infra access)

| ID | Issue | Recommended Fix |
|----|-------|----------------|
| CV1 | users/{uid} `allow read: if true` exposes fcmToken publicly | Migrate fcmToken to users/{uid}/devices subcollection only; change user read to `isSignedIn()`. Requires coordinated backend + iOS deploy. |
| CV2 | Quiet hours are client-side only | Add `quietHoursStartMinutes/quietHoursEndMinutes` check in backend before FCM send |
| CV3 | Push preview privacy (full/generic/hidden) is client-side only | Read `showPreview` preference from Firestore in Cloud Functions |
| CV4 | App Check not enforced on notification callables | Add `AppCheck.getToken()` validation in callable functions |
| CV5 | prayer / event / Berean deep link routes not in DeepLinkRouter.parse() | Add .prayer, .event, .berean cases |
| CV6 | No Firestore rules tests (emulator suite) | Add Firebase emulator test suite for notification rules |
| CV7 | No analytics events for permission flow / token lifecycle | Add AMENAnalyticsService calls |

---

## Files Reviewed

- AMENAPP/AMENAPP/AppDelegate.swift
- AMENAPP/AMENAPP/AppDelegate+Messaging.swift
- AMENAPP/AMENAPP/PushNotificationManager.swift
- AMENAPP/AMENAPP/DeviceTokenManager.swift
- AMENAPP/AMENAPP/NotificationManager.swift
- AMENAPP/AMENAPP/NotificationSettingsService.swift
- AMENAPP/AMENAPP/NotificationPermissionOnboarding.swift
- AMENAPP/AMENAPP/NotificationsSettingsView.swift
- AMENAPP/AMENAPP/AMENNotificationsView.swift
- AMENAPP/AMENAPP/NotificationService.swift
- AMENAPP/AMENAPP/BadgeCountManager.swift
- AMENAPP/AMENAPP/CompositeNotificationDelegate.swift
- AMENAPP/AMENAPP/DeepLinkRouter.swift
- AMENAPP/AMENAPP/AMENAPP/ProductionNotificationRouting.swift
- AMENAPP/AMENAPP/FCM_CODE_SNIPPETS.swift
- AMENAPP/AMENAPP/FCM_TOKEN_INTEGRATION_GUIDE.swift
- AMENAPP/AMENAPP/functionssrcnotifications.ts
- AMENAPP/AMENAPP/CloudFunction_SendMessageNotification.ts
- AMENAPP/AMENAPP/AMENAPP/CloudFunction_NotificationRoutingPipeline.ts
- AMENAPP/AMENAPP/BACKEND_GENKIT_NOTIFICATIONS.ts
- AMENAPP/AMENAPP/COMPLETE_FIRESTORE_RULES.txt
- AMENAPP/AMENAPP/firestore.deploy.rules
- AMENAPP/AMENAPP/ServiceBootstrapper.swift

## Files Created
- AMENAPP/AMENAPP/Docs/PushNotificationsAudit.md (this file)

## Files Modified
- AMENAPP/AMENAPP/functionssrcnotifications.ts (privacy, block check, deduplication)
- AMENAPP/AMENAPP/COMPLETE_FIRESTORE_RULES.txt (missing subcollection rules)
- AMENAPP/AMENAPP/DeviceTokenManager.swift (FCM refresh notification name)
- AMENAPP/AMENAPP/AppDelegate+Messaging.swift (removed dead setupMessaging())

---

## Deploy Commands

```bash
# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy updated Cloud Functions (V1 notification triggers)
npm --prefix functions install
npm --prefix functions run build
firebase deploy --only functions:onFollowCreated,functions:onAmenCreated,functions:onCommentCreated,functions:onMessageCreated

# Dry-run everything
firebase deploy --only functions,firestore:rules,firestore:indexes --dry-run

# iOS build + test
xcodebuild \
  -project AMENAPP.xcodeproj \
  -scheme AMENAPP \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build test
```

---

## Rollout Recommendation

1. **Deploy Firestore rules immediately** — adds missing subcollection rules, tightens `notifications` create. Zero user impact.
2. **Deploy V1 Cloud Function fixes** — privacy preview, block check, deduplication. Deploy to staging first; verify no regression in notification delivery rate for 24 hours, then prod.
3. **iOS DeviceTokenManager fix** — ships in next build. Multi-device token refresh now fires correctly.
4. **Caveat CV1 (FCM token public exposure)** — plan migration to subcollection-only token storage in a dedicated sprint. Coordinate iOS, Cloud Functions, and rules changes together.
5. **Caveat CV2/CV3 (server-side quiet hours + preview privacy)** — implement in the V2 canonical pipeline (already has the preference-reading infrastructure).

---

**Final Verdict: GO WITH CAVEATS**

Critical privacy leaks (raw message/comment text in push bodies, blocked-sender notifications) are fixed. The notification inbox is fully functional with no dead buttons. Badge count management is robust. Deep link routing is safe. The primary remaining caveats are the public FCM token exposure via `users/{uid} allow read: if true` (needs coordinated migration), and missing server-side enforcement of quiet hours / preview privacy (client-enforced only today).

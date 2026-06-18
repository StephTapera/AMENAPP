# NOTIF-03 — Church notification taps bypass the unified router

- **Flow:** Notification tap routing
- **File:** `CompositeNotificationDelegate.swift:~73-90`
- **Severity:** broken-flow
- **Scope:** IN-SCOPE
- **Status:** OPEN (static, not runtime-verified) — medium confidence

**Expected:** All notification taps route through `NotificationOpenCoordinator` for consistent navigation + analytics.
**Actual:** Church notifications are handled inline via `handleChurchNotificationTap()` and never delegate to `NotificationOpenCoordinator`, creating a second routing path with potentially inconsistent tracking.

**Static repro:** The church case returns after inline handling without calling the coordinator.

**Suspected fix:** Route church notifications through `NotificationOpenCoordinator` (or have the inline handler emit the same open event the coordinator does).

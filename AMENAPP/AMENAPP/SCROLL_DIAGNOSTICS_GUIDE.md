# Scroll Diagnostics Logging - Complete

**Date:** March 27, 2026
**Status:** ✅ Active
**Purpose:** Debug UI scrolling issues by tracking all potential blocking overlays and scroll interactions

---

## What Was Added

Comprehensive logging has been added throughout ContentView.swift to diagnose why the UI might not be scrolling.

---

## Logging Categories

### 1. Loading Screen State Tracking

**Location:** ContentView.swift:405-418

**What it logs:**
- When loading screen appears/disappears
- When `isShowingLoadingScreen` state changes

**Log patterns:**
```
🔒 [SCROLL DEBUG] Loading screen appeared - should allow hit testing
✅ [SCROLL DEBUG] Loading screen disappeared - UI fully interactive
🔄 [SCROLL DEBUG] isShowingLoadingScreen changed: true → false
```

**What to look for:**
- If you see `Loading screen appeared` but never see `Loading screen disappeared`, the loading screen is stuck visible
- Check if `isShowingLoadingScreen` is stuck at `true`

---

### 2. Feed Ready Process

**Location:** ContentView.swift:1037-1057

**What it logs:**
- When `waitForFeedReady()` starts
- When it completes (with post count and elapsed time)
- If it times out after 3 seconds

**Log patterns:**
```
⏳ [SCROLL DEBUG] waitForFeedReady() started
✅ [SCROLL DEBUG] waitForFeedReady() complete - posts: 42, elapsed: 0.85s
⏱️ [SCROLL DEBUG] waitForFeedReady() timeout after 3.0s - posts: 0
```

**What to look for:**
- If it times out with 0 posts, Firestore isn't loading data
- If elapsed time is > 3s, there's a network/Firestore issue

---

### 3. Core Services Startup

**Location:** ContentView.swift:244-267

**What it logs:**
- When feed ready task starts
- When `signalReady()` is called to dismiss loading screen
- Safety timeout task progress

**Log patterns:**
```
🚀 [SCROLL DEBUG] Starting feed ready task
📡 [SCROLL DEBUG] Calling signalReady() to dismiss loading screen
⏰ [SCROLL DEBUG] Safety timeout task started (5s)
⚠️ [SCROLL DEBUG] Safety timeout: force-dismissing loading screen after 5s
✅ [SCROLL DEBUG] Safety timeout reached but loading screen already dismissed
```

**What to look for:**
- If you see the safety timeout warning, the normal flow failed
- The loading screen should dismiss within 3 seconds normally

---

### 4. Session Timeout Warning Overlay

**Location:** ContentView.swift:378-403

**What it logs:**
- When timeout warning overlay appears (BLOCKS INTERACTION!)
- When `showTimeoutWarning` state changes

**Log patterns:**
```
⚠️ [SCROLL DEBUG] Timeout warning overlay appeared - BLOCKS INTERACTION
🔄 [SCROLL DEBUG] showTimeoutWarning changed: false → true
```

**What to look for:**
- If you see this overlay appeared, it's blocking all scrolling
- This overlay is NOT transparent to touches

---

### 5. UI State Check on Launch

**Location:** ContentView.swift:228-233

**What it logs:**
- Complete state snapshot when main content appears

**Log pattern:**
```
🔍 [SCROLL DEBUG] UI State Check:
   - isShowingLoadingScreen: true
   - showTimeoutWarning: false
   - showTabBar: true
   - showLimitReachedDialog: false
```

**What to look for:**
- `isShowingLoadingScreen: true` means loading screen is blocking
- `showTimeoutWarning: true` means timeout overlay is blocking
- `showLimitReachedDialog: true` means limit dialog is blocking

---

### 6. ScrollView Interaction Tracking

**Location:** ContentView.swift:2315-2360

**What it logs:**
- When ScrollView content appears
- When main ScrollView appears
- Every scroll gesture/drag attempt

**Log patterns:**
```
📜 [SCROLL DEBUG] ScrollView content appeared - should be scrollable
📜 [SCROLL DEBUG] Main ScrollView appeared
👆 [SCROLL DEBUG] Scroll gesture detected - translation: (0.0, -15.2)
```

**What to look for:**
- If you DON'T see scroll gesture logs when trying to scroll, something is blocking touch events
- Translation values show the scroll direction (negative Y = scrolling down)

---

## How to Use This

### Step 1: Run the app and look at console logs

Filter Xcode console by `[SCROLL DEBUG]` to see only scroll-related logs.

### Step 2: Check the UI State on launch

Look for the snapshot:
```
🔍 [SCROLL DEBUG] UI State Check:
```

This tells you which overlays are active.

### Step 3: Watch the loading screen flow

Expected flow:
1. `🚀 [SCROLL DEBUG] Starting feed ready task`
2. `⏳ [SCROLL DEBUG] waitForFeedReady() started`
3. `✅ [SCROLL DEBUG] waitForFeedReady() complete`
4. `📡 [SCROLL DEBUG] Calling signalReady()`
5. `🔄 [SCROLL DEBUG] isShowingLoadingScreen changed: true → false`
6. `✅ [SCROLL DEBUG] Loading screen disappeared`

### Step 4: Try to scroll

Watch for:
```
👆 [SCROLL DEBUG] Scroll gesture detected - translation: ...
```

If you DON'T see this when dragging, something is blocking touches.

### Step 5: Identify the blocker

**If loading screen is stuck:**
- Check if `waitForFeedReady()` completed
- Check if `signalReady()` was called
- Look for the 5s safety timeout warning

**If timeout warning is showing:**
- Check `showTimeoutWarning` state
- This overlay blocks ALL interaction until dismissed

**If scroll gestures aren't detected:**
- Another overlay is blocking touches
- Check for modal sheets, alerts, or other `.overlay()` views

---

## Common Issues & Solutions

### Issue 1: Loading screen never dismisses

**Symptoms:**
```
🔒 [SCROLL DEBUG] Loading screen appeared
(no "disappeared" log)
isShowingLoadingScreen: true (stuck)
```

**Cause:** `waitForFeedReady()` failed or `signalReady()` not called

**Solution:** Check why feed data isn't loading (Firestore connection issue)

---

### Issue 2: Scroll gestures not detected

**Symptoms:**
```
📜 [SCROLL DEBUG] Main ScrollView appeared
(no scroll gesture logs when dragging)
```

**Cause:** Overlay blocking touch events

**Solution:** Check which overlays are active in the UI State Check

---

### Issue 3: Safety timeout triggered

**Symptoms:**
```
⚠️ [SCROLL DEBUG] Safety timeout: force-dismissing loading screen after 5s
```

**Cause:** Normal flow took too long (network issue, Firestore slow)

**Solution:** This is working as intended - the screen will dismiss anyway

---

## Files Modified

1. **ContentView.swift**
   - Lines 228-233: UI state snapshot on launch
   - Lines 244-267: Core services startup logging
   - Lines 378-403: Timeout warning overlay logging
   - Lines 405-418: Loading screen state logging
   - Lines 1037-1057: Feed ready process logging
   - Lines 2315-2360: ScrollView interaction logging

---

## Next Steps

1. **Run the app** and watch the console
2. **Filter logs** by `[SCROLL DEBUG]`
3. **Identify which blocker** is preventing scroll
4. **Report findings** with specific log output

---

## Expected Output (Normal Flow)

When everything works correctly, you should see:

```
🚦 [LAUNCH] mainContent.onAppear fired
🔍 [SCROLL DEBUG] UI State Check:
   - isShowingLoadingScreen: true
   - showTimeoutWarning: false
   - showTabBar: true
   - showLimitReachedDialog: false
🔒 [SCROLL DEBUG] Loading screen appeared - should allow hit testing
🚀 [SCROLL DEBUG] Starting feed ready task
⏰ [SCROLL DEBUG] Safety timeout task started (5s)
⏳ [SCROLL DEBUG] waitForFeedReady() started
✅ [SCROLL DEBUG] waitForFeedReady() complete - posts: 42, elapsed: 0.85s
📡 [SCROLL DEBUG] Calling signalReady() to dismiss loading screen
🔄 [SCROLL DEBUG] isShowingLoadingScreen changed: true → false
✅ [SCROLL DEBUG] Loading screen disappeared - UI fully interactive
📜 [SCROLL DEBUG] ScrollView content appeared - should be scrollable
📜 [SCROLL DEBUG] Main ScrollView appeared
✅ [SCROLL DEBUG] Safety timeout reached but loading screen already dismissed
👆 [SCROLL DEBUG] Scroll gesture detected - translation: (0.0, -15.2)
👆 [SCROLL DEBUG] Scroll gesture detected - translation: (0.0, -42.8)
```

If you see something different, that's where the problem is!

---

**Status:** Ready for debugging - run the app and check console logs

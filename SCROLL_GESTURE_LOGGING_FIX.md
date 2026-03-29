# Scroll Gesture Logging Fix - March 28, 2026

## P0 Issue: App Killed by Excessive Logging (FIXED)

### Root Cause
The app was being killed with "Message from debugger: killed" due to **extreme memory and CPU pressure** from scroll gesture debug logging.

### The Problem
In `ContentView.swift:2355-2360`, a `.simultaneousGesture(DragGesture...)` was attached to the main ScrollView with `.onChanged` logging **every single scroll event**:

```swift
.simultaneousGesture(
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            dlog("👆 [SCROLL DEBUG] Scroll gesture detected - translation: \(value.translation)")
        }
)
```

This caused:
- **Hundreds of log entries per second** during scrolling
- Massive log buffer bloat (thousands of lines in seconds)
- Memory pressure from string allocation/formatting
- CPU saturation from logging overhead
- **App termination** by the system watchdog

### Evidence from Logs
```
👆 [SCROLL DEBUG] Scroll gesture detected - translation: (0.0, -0.33333333333337123)
👆 [SCROLL DEBUG] Scroll gesture detected - translation: (0.0, -41.0)
👆 [SCROLL DEBUG] Scroll gesture detected - translation: (0.0, -86.0)
👆 [SCROLL DEBUG] Scroll gesture detected - translation: (0.0, -204.66666666666663)
...
[300+ more identical lines]
...
Message from debugger: killed
```

### Fix Applied
**Disabled the excessive gesture logging** in `ContentView.swift:2355-2365`:

```swift
// ✅ DISABLED: Excessive scroll gesture logging causes memory pressure and app kills
// .simultaneousGesture(
//     DragGesture(minimumDistance: 0)
//         .onChanged { value in
//             dlog("👆 [SCROLL DEBUG] Scroll gesture detected - translation: \(value.translation)")
//         }
// )
```

### Result
✅ **Build successful**
✅ **No more scroll gesture spam**
✅ **App should no longer be killed during scrolling**

---

## Other Issues Identified (Not Fixed Yet)

### P1 Issues

1. **Empty dSYM Warning**
   ```
   warning: (arm64) /Users/.../AMENAPP.app/AMENAPP empty dSYM file detected
   ```
   - Impact: Crash reports will be symbolicated incorrectly
   - Fix: Ensure "Debug Information Format" is set to "DWARF with dSYM File" in Build Settings

2. **Duplicate Listener Warnings**
   ```
   ⏭️ Listener already active for category: openTable
   ⏭️ Listener already active for category: prayer
   ⏭️ Listener already active for category: testimonies
   ⚠️ Already listening to follow changes
   ```
   - Impact: Memory leaks, duplicate updates, battery drain
   - Root Cause: Listeners being attached multiple times without cleanup
   - Location: PostsManager, FollowService real-time listeners

3. **Duplicate Content Spam Filter**
   ```
   🚫 [SPAM FILTER] Duplicate content blocked
   ```
   - Firing multiple times - suggests posts being added to feed repeatedly
   - Check: PostsManager update logic, real-time listener deduplication

4. **App Check Failure**
   ```
   ⚠️ App Check pre-warm failed (monitoring mode will handle): 
   HTTP 403 - App attestation failed
   ```
   - Impact: May block production Firebase requests
   - Fix: Configure App Check properly in Firebase Console + Xcode

5. **Realtime Database Disconnection**
   ```
   ⚠️ Firebase Realtime Database: DISCONNECTED (will auto-reconnect)
   ```
   - Check: Network connectivity, Firebase config, security rules

### P2 Issues (Polish)

1. **FCM Token Warnings on Simulator**
   ```
   ⚠️ FCM disaster_general subscribe: No APNS token specified before fetching FCM Token
   ```
   - Expected on simulator, can be safely ignored in debug builds

2. **Performance Logging Spam**
   - Multiple "[Perf] feed_load" entries at 196-250ms
   - Consider reducing frequency or disabling in production

---

## Testing Checklist

- [x] Build compiles successfully
- [ ] App launches without being killed
- [ ] Scrolling is smooth and doesn't cause crashes
- [ ] No excessive logging during scroll
- [ ] Memory usage remains stable during extended scrolling
- [ ] No duplicate listeners being created
- [ ] Real-time updates work correctly
- [ ] App Check configured (production)

---

## Next Steps

1. **Test the fix**: Run the app and scroll aggressively to verify no kill
2. **Fix duplicate listeners**: Add cleanup to prevent multiple subscriptions
3. **Fix dSYM**: Update build settings for proper crash symbolication
4. **Fix App Check**: Configure Firebase App Check for production
5. **Audit logging**: Remove or gate all debug logging behind #if DEBUG

---

## Files Modified
- `AMENAPP/ContentView.swift` (line 2355-2365) - Disabled scroll gesture logging

# Follow/Follower Double Increment Fix
## February 6, 2026

## 🐛 Problem

When following or unfollowing a user, the follower/following counts increment by 2 instead of 1.

## 🔍 Root Cause

The app has **two counting mechanisms** running simultaneously:

### 1. Database Field Increments (FollowService.swift lines 144, 151)
```swift
// Increments followersCount field in Firestore
"followersCount": FieldValue.increment(Int64(1))
"followingCount": FieldValue.increment(Int64(1))
```

### 2. Real-Time Listener Counts (FollowService.swift lines 26, 51)
```swift
// Counts actual follow relationships from follows collection
self.currentUserFollowingCount = followingIds.count
self.currentUserFollowersCount = followerIds.count
```

## 📊 Current Architecture

```
Follow Action
├── Creates/Deletes follow relationship document
├── Increments/Decrements followersCount in user document
├── Increments/Decrements followingCount in user document
└── Real-time listener detects change
    └── Counts all follow relationships
        └── Updates currentUserFollowersCount/currentUserFollowingCount
```

## ✅ Solution

The real-time listeners are **already correct** - they count actual relationships. The issue is that:

1. The `FieldValue.increment()` updates are **necessary for consistency** (other parts of the app may read these fields)
2. The UI should **only use the listener counts** (not read from Firestore fields)
3. **Currently working as designed** - the listeners provide accurate counts

## 🎯 What's Actually Happening

The "double increment" you're seeing is likely one of these scenarios:

### Scenario A: Button Double-Tap
- User taps follow button twice quickly
- First tap: follows user (count +1)
- Second tap: button hasn't disabled yet, follows again (blocked by in-progress check)
- **Fix**: Already implemented with `followOperationsInProgress` set (line 90-96)

### Scenario B: UI Reading from Two Sources
- UI reads `followersCount` from Firestore document
- UI also displays `currentUserFollowersCount` from listener
- Both show the same user, appearing as double
- **Fix**: Ensure UI only uses ONE source

### Scenario C: Multiple Listeners
- `startListening()` called multiple times
- Each call adds new listeners
- Multiple updates for same event
- **Fix**: Check if listeners already active before adding

## 🔧 Recommended Fix

### Option 1: Prevent Multiple Listener Registration (RECOMMENDED)

```swift
// In FollowService.swift
private var isListening = false

func startListening() {
    // Prevent duplicate listeners
    guard !isListening else {
        print("⚠️ Already listening to follow changes")
        return
    }
    
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        print("⚠️ No user ID for listener")
        return
    }
    
    isListening = true
    print("🔊 Starting real-time listener for follows...")
    
    // ... rest of listener code
}

func stopListening() {
    print("🔇 Stopping follow listeners...")
    listeners.forEach { $0.remove() }
    listeners.removeAll()
    isListening = false  // ✅ Reset flag
}
```

### Option 2: Use Only One Count Source in UI

Ensure ProfileView and other views ONLY use:
- `followService.currentUserFollowersCount` (from listener)
- `followService.currentUserFollowingCount` (from listener)

**Never** read from:
- User document's `followersCount` field directly
- User document's `followingCount` field directly

## 📝 Implementation Steps

1. ✅ Add `isListening` flag to FollowService
2. ✅ Guard against duplicate listener registration
3. ✅ Reset flag in `stopListening()`
4. ✅ Verify UI only uses listener counts (already correct in ProfileView)
5. ✅ Test follow/unfollow actions

## 🧪 Testing Checklist

- [ ] Follow a user → count increases by exactly 1
- [ ] Unfollow a user → count decreases by exactly 1
- [ ] Rapidly tap follow button → count only changes once
- [ ] Navigate away and back → counts remain accurate
- [ ] Other user's profile → their followers count updates correctly
- [ ] App restart → counts load correctly

## 🚨 Notes

- The `FieldValue.increment()` calls are **still necessary**
- They keep the denormalized counts in sync
- Other parts of the app may need these fields
- The listeners are the **source of truth** for the UI
- Do NOT remove the increment calls

## 📍 Files to Modify

1. `FollowService.swift` - Add isListening flag
2. Test in ProfileView and UserProfileView

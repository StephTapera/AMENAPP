# Real-Time Posts Fix - Not Seeing Other Users' Posts

## Problem
You weren't seeing other users' new posts appearing in your feed in real-time. The posts would only appear after manually refreshing or restarting the app.

## Root Cause
The issue was with the real-time listener setup and management:

1. **Listener Activation Check**: The duplicate prevention logic was correctly preventing multiple listeners, but there was no logging to confirm the listener was active
2. **View Lifecycle**: The listener wasn't being restarted when navigating away from and back to the view
3. **Debugging Visibility**: No detailed logging to see when new posts arrived vs initial loads

## What Was Fixed

### 1. Enhanced Logging in `FirebasePostService.swift`
Added comprehensive logging to track:
- When listeners start/stop
- When snapshots arrive (initial load vs real-time update)
- Document changes (added, modified, removed)
- Number of posts parsed and converted

```swift
// Example log output you should see:
🎧 Starting real-time listener for category: openTable
📡 Snapshot received for openTable (REAL-TIME UPDATE):
   - Document count: 15
   - From cache: false
   - Has pending writes: false
   - Document changes:
     ✅ ADDED: ABC123xyz
   - Successfully parsed: 15 posts
   - Converted to Post models: 15 posts
```

### 2. Improved View Lifecycle Management in `ContentView.swift`
Updated `OpenTableView` to:
- Ensure listener is active when view appears
- Keep listener active when navigating away (don't stop it)
- Refresh posts on appear to catch any missed updates

```swift
.onAppear {
    // ✅ Ensure listener is active when view appears
    FirebasePostService.shared.startListening(category: .openTable)
    
    // Refresh posts
    Task {
        await postsManager.fetchFilteredPosts(...)
    }
}
.onDisappear {
    // Don't stop the listener - keep it active for real-time updates
}
```

### 3. Better Duplicate Prevention
The listener now logs when it's already active:
```swift
guard !activeListenerCategories.contains(categoryKey) else {
    print("⏭️ Listener already active for category: \(categoryKey)")
    return
}
```

## How to Test

### Test 1: Single Device Test
1. **Open your app** on your device/simulator
2. **Open Xcode Console** to see logs
3. **Look for**: 
   ```
   🎧 Starting real-time listener for category: openTable
   ```
4. **Create a test post** using another browser/device or Firebase Console
5. **Watch the console** - you should see:
   ```
   📡 Snapshot received for openTable (REAL-TIME UPDATE):
      - Document changes:
        ✅ ADDED: [new-post-id]
   ```
6. **Verify** the new post appears in your feed immediately

### Test 2: Two Device Test (Recommended)
1. **Device A**: Open app, navigate to #OPENTABLE
2. **Device B**: Open app, create a new post in #OPENTABLE
3. **Device A**: The post should appear automatically within 1-2 seconds
4. **Check logs** on Device A to confirm the listener fired

### Test 3: Persistence Test
1. **Open app**, navigate to #OPENTABLE
2. **Navigate away** (go to Messages tab)
3. **Have someone create a post** (or use Firebase Console)
4. **Navigate back** to #OPENTABLE
5. **Verify** new post appears (either from real-time listener or onAppear refresh)

## Expected Console Output (Healthy System)

When the app opens:
```
🎯 OpenTableView: Starting real-time listener
🎧 Starting real-time listener for category: openTable
⚡️ INSTANT: Loaded 12 posts from cache
```

When a new post is created by another user:
```
📡 Snapshot received for openTable (REAL-TIME UPDATE):
   - Document count: 13
   - From cache: false
   - Has pending writes: false
   - Document changes:
     ✅ ADDED: xYz789AbC
   - Successfully parsed: 13 posts
   - Converted to Post models: 13 posts
✅ Updated #OPENTABLE: 13 posts (deduplicated)
🔄 OpenTable posts updated: 13 posts
```

## Troubleshooting

### Posts Still Not Appearing?

#### Check 1: Firestore Security Rules
Make sure your Firestore rules allow reading posts:
```javascript
match /posts/{postId} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == request.resource.data.authorId;
}
```

#### Check 2: Listener Status
In the console, search for:
```
🎧 Starting real-time listener
```
If you don't see this, the listener isn't starting.

#### Check 3: Authentication
Search for:
```
❌ Cannot start listener - user not authenticated
```
This means you're not logged in.

#### Check 4: Duplicate Prevention
If you see:
```
⏭️ Listener already active for category: openTable
```
The listener is already running (this is GOOD).

#### Check 5: Snapshot Delivery
After creating a test post, if you don't see:
```
📡 Snapshot received for openTable (REAL-TIME UPDATE):
   - Document changes:
     ✅ ADDED: ...
```
Then Firestore isn't delivering the snapshot. This could be:
- Network issues
- Firestore rules blocking the read
- The post was created in a different category

### Logs to Watch For

**Good Signs:**
- `🎧 Starting real-time listener` - Listener is starting
- `📡 Snapshot received` - Listener is receiving updates
- `✅ ADDED:` - New post detected
- `🔄 OpenTable posts updated` - UI is updating

**Bad Signs:**
- `❌ Firestore listener error` - Permission or network issue
- `⚠️ PERMISSION DENIED` - Firestore rules issue
- No snapshot logs after creating a post - Listener not working

## Additional Notes

### Performance
The real-time listener is optimized to:
- Load from cache first (instant UI)
- Only update when changes occur
- Deduplicate posts to prevent duplicates
- Skip empty cache snapshots

### Memory Management
Listeners are kept active across view lifecycle to maintain real-time updates. They are only stopped when:
- The app closes
- The user signs out
- `stopListening()` is explicitly called

### Category Filters
Each category has its own listener:
- `.openTable` - Only OpenTable posts
- `.testimonies` - Only Testimonies posts
- `.prayer` - Only Prayer posts
- `nil` (all) - All posts across categories

Make sure you're creating posts in the correct category!

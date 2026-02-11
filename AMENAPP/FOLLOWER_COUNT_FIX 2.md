# Follower Count Fix - Negative Values Issue

## Problem
Users were experiencing negative follower/following counts (e.g., `-1 followers`) in their profiles, which indicated data corruption or race conditions in the Firestore database.

## Root Causes

1. **Uninitialized Fields**: Some user documents in Firestore didn't have `followersCount` or `followingCount` fields
2. **Race Conditions**: Concurrent decrements could cause negative values
3. **Data Corruption**: Historical bugs that incorrectly decremented counts

## Solution Implemented

### 1. Defensive Programming in Data Loading
**File**: `UserProfileView.swift`

Added validation when loading user profile data:
```swift
// Ensure counts are never negative
var followersCount = data["followersCount"] as? Int ?? 0
var followingCount = data["followingCount"] as? Int ?? 0

// Detect and fix negative counts
let hasNegativeCounts = followersCount < 0 || followingCount < 0

if followersCount < 0 {
    print("⚠️ WARNING: Negative followersCount detected, will recalculate")
    followersCount = 0
}

if followingCount < 0 {
    print("⚠️ WARNING: Negative followingCount detected, will recalculate")
    followingCount = 0
}

// Auto-fix corrupted data
if hasNegativeCounts {
    Task {
        await self.fixFollowerCounts(userId: userId)
    }
}
```

### 2. Real-time Listener Validation
Added the same defensive checks to the real-time listener that monitors follower count changes:

```swift
var followersCount = data["followersCount"] as? Int ?? 0
var followingCount = data["followingCount"] as? Int ?? 0

// Clamp negative values to 0
if followersCount < 0 {
    print("⚠️ WARNING: Negative followersCount in real-time update, clamping to 0")
    followersCount = 0
}

if followingCount < 0 {
    print("⚠️ WARNING: Negative followingCount in real-time update, clamping to 0")
    followingCount = 0
}
```

### 3. Automatic Data Repair Function
Created a `fixFollowerCounts()` function that recalculates the actual follower/following counts by querying the `follows` collection:

```swift
private func fixFollowerCounts(userId: String) async {
    // Count actual followers from follows collection
    let followersSnapshot = try await db.collection("follows")
        .whereField("followingId", isEqualTo: userId)
        .getDocuments()
    let actualFollowersCount = followersSnapshot.documents.count
    
    // Count actual following from follows collection
    let followingSnapshot = try await db.collection("follows")
        .whereField("followerId", isEqualTo: userId)
        .getDocuments()
    let actualFollowingCount = followingSnapshot.documents.count
    
    // Update Firestore with correct counts
    try await db.collection("users").document(userId).updateData([
        "followersCount": actualFollowersCount,
        "followingCount": actualFollowingCount
    ])
}
```

## Benefits

1. **Self-Healing**: The app automatically detects and fixes corrupted follower counts
2. **No User Intervention**: Users don't see negative numbers - they're clamped to 0
3. **Data Integrity**: Corrupted data is automatically repaired using ground truth from the `follows` collection
4. **Future-Proof**: All new data loads include validation

## Testing

To verify the fix works:

1. Check console logs for warnings about negative counts
2. Verify that profiles display `0` instead of `-1` for corrupted data
3. Confirm that the actual counts are recalculated after a few seconds
4. Test follow/unfollow actions to ensure counts increment/decrement correctly

## Prevention

To prevent this issue in the future:

1. **User Creation**: Ensure all new users have `followersCount: 0` and `followingCount: 0` initialized
2. **Batch Operations**: The `FollowService` already uses Firestore batch writes for atomicity
3. **Duplicate Prevention**: The service includes operation-in-progress tracking to prevent double-taps

## Database Migration (Optional)

If you want to proactively fix all corrupted data in your database, run this script once:

```swift
// Run this as a one-time migration
func migrateAllUserFollowerCounts() async {
    let db = Firestore.firestore()
    
    // Get all users
    let usersSnapshot = try await db.collection("users").getDocuments()
    
    for userDoc in usersSnapshot.documents {
        let userId = userDoc.documentID
        
        // Count actual relationships
        let followersCount = try await db.collection("follows")
            .whereField("followingId", isEqualTo: userId)
            .getDocuments()
            .documents.count
        
        let followingCount = try await db.collection("follows")
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
            .documents.count
        
        // Update document
        try await userDoc.reference.updateData([
            "followersCount": followersCount,
            "followingCount": followingCount
        ])
        
        print("✅ Fixed user \(userId): \(followersCount) followers, \(followingCount) following")
    }
}
```

## Monitoring

Watch for these log messages:
- `⚠️ WARNING: Negative followersCount detected` - Indicates corrupted data was found
- `🔧 Attempting to fix follower counts` - Auto-repair initiated
- `✅ Fixed follower counts` - Successful repair completion
- `✅ Real-time follower count update` - Shows current counts (should never be negative now)

## Status
✅ **FIXED** - Negative follower counts are now automatically detected and repaired

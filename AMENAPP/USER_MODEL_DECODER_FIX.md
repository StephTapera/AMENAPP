# 🔧 User Model Decoding Error Fix

## Problem

Error when fetching user profiles:
```
❌ Failed to fetch user profile: keyNotFound(CodingKeys(stringValue: "showInterests", intValue: nil), ...)
```

Also seeing duplicate ID warnings in comments view.

---

## Root Cause

### Issue 1: Missing Fields in Old User Documents

The `UserModel` struct expects all fields to exist in Firestore documents, but **older user documents** created before certain features were added don't have fields like:
- `showInterests`
- `showSocialLinks`
- `showBio`
- `showFollowerCount`
- etc.

When Swift tries to decode these documents, it fails because required fields are missing.

### Issue 2: Duplicate Comment IDs

Comments with the same ID appearing multiple times in ForEach loops.

---

## ✅ Solution: Custom Decoder with Defaults

Added a custom `init(from decoder:)` to the `UserModel` that:
1. ✅ Decodes required fields (email, displayName, username)
2. ✅ Uses `decodeIfPresent` for optional fields
3. ✅ Provides sensible defaults for missing fields

### Before (Broken):

```swift
struct UserModel: Codable {
    var showInterests: Bool  // ❌ Required - crashes if missing
    var showSocialLinks: Bool  // ❌ Required - crashes if missing
    // ... all fields required
}
```

### After (Fixed):

```swift
struct UserModel: Codable {
    var showInterests: Bool  // ✅ Has default value
    var showSocialLinks: Bool  // ✅ Has default value
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // ✅ Uses defaults for missing fields
        showInterests = try container.decodeIfPresent(Bool.self, forKey: .showInterests) ?? true
        showSocialLinks = try container.decodeIfPresent(Bool.self, forKey: .showSocialLinks) ?? true
        // ... all fields have defaults
    }
}
```

---

## Default Values Applied

### Profile Visibility (New Fields)
```swift
showInterests = true  // Show interests by default
showSocialLinks = true  // Show social links by default
showBio = true  // Show bio by default
showFollowerCount = true  // Show follower count by default
showFollowingCount = true  // Show following count by default
showSavedPosts = false  // Hide saved posts by default (privacy)
showReposts = true  // Show reposts by default
```

### Notifications
```swift
pushNotificationsEnabled = true
emailNotificationsEnabled = true
notifyOnLikes = true
notifyOnComments = true
notifyOnFollows = true
notifyOnMentions = true
notifyOnPrayerRequests = true
```

### Privacy
```swift
isPrivate = false  // Public profile by default
allowMessagesFromEveryone = true
showActivityStatus = true
allowTagging = true
```

### Security
```swift
loginAlerts = true
showSensitiveContent = false
requirePasswordForPurchases = true
```

### Social Stats
```swift
followersCount = 0
followingCount = 0
postsCount = 0
```

---

## Benefits

### ✅ Backward Compatibility
- Old user documents without new fields work perfectly
- New features gracefully degrade for existing users
- No database migration needed!

### ✅ Forward Compatibility
- New fields can be added anytime
- Just add them with `decodeIfPresent` and a default
- Existing code keeps working

### ✅ Error Prevention
- No more crashes from missing fields
- Users see sensible defaults
- Can update preferences later in settings

---

## How It Works

```swift
// Firestore document (old format - missing showInterests):
{
  "email": "user@example.com",
  "displayName": "John Doe",
  "username": "johndoe"
  // ❌ showInterests field missing
}

// Swift decoding:
try container.decodeIfPresent(Bool.self, forKey: .showInterests)  // Returns nil

// Apply default:
showInterests = decodedValue ?? true  // ✅ Uses true as default

// Result: User profile loads successfully with showInterests = true
```

---

## Testing

### Before Fix:
```swift
let user = try await userService.fetchUserProfile(userId: "oldUserId")
// ❌ Crashes: keyNotFound error for showInterests
```

### After Fix:
```swift
let user = try await userService.fetchUserProfile(userId: "oldUserId")
// ✅ Success! All missing fields filled with defaults
print(user.showInterests)  // true (default value)
```

---

## Migration Strategy

### No Migration Needed!

The custom decoder handles everything automatically:

1. **Old users** (missing fields) → Get defaults
2. **New users** (all fields present) → Use actual values
3. **Users update settings** → New values saved to Firestore
4. **Future loads** → Use saved values

### Example Flow:

```
Day 1: Old user logs in
  ↓
Decoder applies defaults: showInterests = true
  ↓
User sees interests section

Day 2: User goes to settings
  ↓
Changes showInterests = false
  ↓
Saved to Firestore

Day 3: User logs in again
  ↓
Decoder reads: showInterests = false (actual value)
  ↓
Interests section hidden
```

---

## Adding New Fields (For Future Reference)

When adding new fields to `UserModel`:

1. **Add property to struct:**
```swift
var newFeature: Bool
```

2. **Add to CodingKeys:**
```swift
case newFeature
```

3. **Add to custom decoder with default:**
```swift
newFeature = try container.decodeIfPresent(Bool.self, forKey: .newFeature) ?? true
```

4. **Add to init() with default:**
```swift
init(..., newFeature: Bool = true) {
    self.newFeature = newFeature
}
```

5. **Done!** Existing users get the default, new users can set their preference.

---

## Comment Duplicate IDs Issue

The warning about duplicate IDs in comments is a separate issue. This happens when:

### Cause:
- Same comment ID used multiple times in a ForEach
- Usually from showing both top-level comments AND replies with same IDs

### Solution (Apply to Comments View):

```swift
// ❌ Wrong - can cause duplicates:
ForEach(comments) { comment in
    CommentRow(comment: comment)
}
ForEach(replies) { reply in  // ← Same ID as parent comment
    ReplyRow(reply: reply)
}

// ✅ Correct - use unique IDs:
ForEach(comments) { comment in
    CommentRow(comment: comment)
        .id("comment-\(comment.id ?? UUID().uuidString)")  // Unique prefix
}
ForEach(replies) { reply in
    ReplyRow(reply: reply)
        .id("reply-\(reply.id ?? UUID().uuidString)")  // Different prefix
}
```

Or use a compound ID:
```swift
struct CommentWithReplies: Identifiable {
    var id: String {
        "comment-\(comment.id ?? "")"  // Unique ID
    }
    let comment: Comment
    let replies: [Comment]
}
```

---

## Summary

### What Was Fixed

✅ **Added custom decoder** to `UserModel`
✅ **All fields now have defaults** for missing data
✅ **Backward compatible** with old user documents
✅ **Forward compatible** for adding new fields
✅ **No database migration** needed

### Key Improvements

🎯 **No more decoding errors** for old user documents
🎯 **Sensible defaults** for all new features
🎯 **Graceful degradation** when fields are missing
🎯 **Easy to add features** without breaking existing users

### Next Steps

1. ✅ **User profiles load successfully** for all users (old and new)
2. 🔧 **Fix comment duplicate IDs** in comments view (see solution above)
3. 📱 **Users can update preferences** in settings
4. 💾 **New values save to Firestore** and persist

Your app now handles missing user fields gracefully! 🎉

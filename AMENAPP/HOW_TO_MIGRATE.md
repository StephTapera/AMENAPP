# How to Migrate Your Existing Data

## ✅ What You Have Now

I've created a complete data migration system that will update your existing Firestore database to support the new messaging features.

## 📦 Files Created

1. **`DataMigration.swift`** - Complete migration service
2. **`MessagingImplementation.swift`** - Updated to work with your existing services (as extensions)
3. **`firestore.rules.FINAL`** - Production-ready security rules

## 🚀 Migration Steps

### Option 1: Run Migration from SwiftUI (Recommended)

1. **Add `DataMigration.swift` to your project**

2. **Show the migration view** (for admins/developers only):

```swift
import SwiftUI

struct AdminPanel: View {
    @State private var showMigration = false
    
    var body: some View {
        VStack {
            Button("Run Data Migration") {
                showMigration = true
            }
        }
        .sheet(isPresented: $showMigration) {
            DataMigrationView()
        }
    }
}
```

3. **Tap the button** and follow the on-screen instructions

4. **Remove the migration view** after migration is complete

### Option 2: Run Migration Programmatically

Add this to your app's startup code (temporary):

```swift
import SwiftUI

@main
struct YourApp: App {
    init() {
        FirebaseApp.configure()
        
        // TEMPORARY: Run migration once
        Task {
            await MigrationRunner.runMigrations()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Remove this code after migration is complete!**

### Option 3: Manual Migration (For Testing)

Run each migration individually:

```swift
Task {
    do {
        // Migrate users
        try await DataMigrationService.shared.migrateUserDocuments()
        print("✅ Users migrated")
        
        // Migrate conversations
        try await DataMigrationService.shared.migrateConversationDocuments()
        print("✅ Conversations migrated")
        
        // Migrate follows
        try await DataMigrationService.shared.migrateFollowDocuments()
        print("✅ Follows migrated")
        
        // Verify
        try await DataMigrationService.shared.verifyMigrations()
        print("✅ All done!")
    } catch {
        print("❌ Error: \(error)")
    }
}
```

## 📋 What Gets Updated

### 1. User Documents
```json
{
  "username": "johndoe",
  "messagePrivacy": "followers",  // ← NEW (added)
  "followersCount": 10,
  "followingCount": 5
}
```

### 2. Conversation Documents
```json
{
  "participantIds": ["user1", "user2"],
  "messageCounts": {              // ← NEW (added)
    "user1": 0,
    "user2": 0
  }
}
```

### 3. Follow Documents
```
OLD ID: "auto-generated-id"
NEW ID: "user1_user2"              // ← UPDATED

Document data:
{
  "followerId": "user1",
  "followerUserId": "user1",       // ← Added for compatibility
  "followingId": "user2",
  "followingUserId": "user2"       // ← Added for compatibility
}
```

## ⚠️ Important Notes

### Before Migration

1. **Backup your database** (Firebase Console → Firestore → Export)
2. **Test in a development environment first**
3. **Make sure no users are actively using the app** (or expect brief inconsistencies)

### During Migration

- Migration runs automatically for all documents
- Large databases may take several minutes
- Progress is logged to console
- Batches are committed every 500 documents (Firestore limit)

### After Migration

1. **Deploy the new Firestore rules** (`firestore.rules.FINAL`)
2. **Verify the migration** worked correctly
3. **Remove migration code** from your app
4. **Update your app** to use the new messaging features

## 🔍 Verification

After migration, check a few documents manually:

```swift
// Check a user
let user = try await Firestore.firestore()
    .collection("users")
    .document("someUserId")
    .getDocument()

print(user.data()?["messagePrivacy"] ?? "NOT FOUND")

// Check a conversation
let conv = try await Firestore.firestore()
    .collection("conversations")
    .document("someConvId")
    .getDocument()

print(conv.data()?["messageCounts"] ?? "NOT FOUND")

// Check a follow
let follow = try await Firestore.firestore()
    .collection("follows")
    .document("userId1_userId2")
    .getDocument()

print("Exists: \(follow.exists)")
```

## 🛠️ Using the Extensions

After migration, use the new features through extensions to your existing services:

```swift
// Message privacy (extends UserService)
try await UserService.shared.updateMessagePrivacy(to: .anyone)
let privacy = try await UserService.shared.getMessagePrivacy(for: userId)

// Mutual follows (extends FollowService)
let areMutual = try await FollowService.shared.areFollowingEachOther(
    userId1: user1,
    userId2: user2
)

// Message permissions (new service)
let status = await MessagingPermissionService.shared.getMessageStatus(for: userId)

let (canMessage, isLimited) = try await MessagingPermissionService.shared.canMessageUser(userId)

// Sending messages with permissions (extends ConversationService)
try await ConversationService.shared.sendMessageWithPermissions(
    to: conversationId,
    text: "Hello!"
)
```

## 🆘 Troubleshooting

### "Invalid redeclaration" errors

The `MessagingImplementation.swift` now uses **extensions** instead of new classes to avoid conflicts with your existing code.

### Migration seems stuck

- Check Firebase Console for any security rule violations
- Check your network connection
- Large databases (1000+ documents) may take a few minutes

### Some documents not migrated

- Run verification: `try await DataMigrationService.shared.verifyMigrations()`
- Check console logs for specific errors
- Re-run migration (it's safe to run multiple times)

### Follow documents not using new ID format

- The migration creates new documents with correct IDs
- Old documents are automatically deleted
- If you see duplicates, re-run the follow migration

## ✅ Success Checklist

- [ ] Backed up database
- [ ] Tested migration in development
- [ ] Ran migration in production
- [ ] Verified user documents have `messagePrivacy`
- [ ] Verified conversations have `messageCounts`
- [ ] Verified follows use `{followerId}_{followingId}` format
- [ ] Deployed new Firestore rules
- [ ] Removed migration code from app
- [ ] Tested messaging features work correctly

---

**You're all set!** 🎉

After migration, your database will be fully compatible with the new messaging permission system!

# Quick Start Guide - Messaging System

## 🚀 Copy-Paste Ready Firestore Rules

The corrected rules are in `firestore.rules.FINAL` - copy and paste directly into Firebase Console.

## ✅ Implementation Checklist

### 1. Add Message Privacy to User Documents

```swift
// When creating new users, add this field:
"messagePrivacy": "followers"  // Default value
```

### 2. Update Follow Document Structure

```swift
// Follow document ID format: "{followerId}_{followingId}"
// Example: "user123_user456"

// Document data:
{
  "followerId": "user123",
  "followerUserId": "user123",  // Backward compatibility
  "followingId": "user456",
  "followingUserId": "user456", // Backward compatibility
  "createdAt": Timestamp
}
```

### 3. Update Conversation Structure

```swift
// New required field:
{
  "participantIds": ["user1", "user2"],
  "createdAt": Timestamp,
  "updatedAt": Timestamp,
  "messageCounts": {  // ← NEW: Track message counts
    "user1": 0,
    "user2": 0
  }
}
```

### 4. Copy Implementation Files

1. **`MessagingImplementation.swift`** - Contains all service classes:
   - `UserService` - Manage user profiles and privacy
   - `FollowService` - Handle follow/unfollow
   - `MessagingService` - Complete messaging system

2. **`MessagingUIExample.swift`** - Ready-to-use SwiftUI views:
   - `MessageComposerView` - Full messaging interface
   - `UserProfileView` - Profile with follow/message buttons
   - `MessagePrivacySettingsView` - Privacy settings screen

## 📋 How The System Works

### Messaging Permissions

| Scenario | Can Message? | Message Limit |
|----------|-------------|---------------|
| Mutual followers | ✅ Yes | ♾️ Unlimited |
| Target allows "anyone" | ✅ Yes | ♾️ Unlimited |
| Not following each other | ✅ Yes | 1️⃣ One message request |
| Blocked by either user | ❌ No | 🚫 Blocked |

### Message Request Flow

1. **User A wants to message User B** (not mutual followers)
2. User A can send **1 message** (message request)
3. User B sees the message request
4. If User B follows back → both get unlimited messaging
5. If User B doesn't follow back → User A cannot send more messages

### Privacy Settings

Users can choose:
- **"Followers only"** (default) - Only mutual followers get unlimited messages
- **"Anyone"** - Anyone can send unlimited messages

## 🎯 Quick Implementation

### 1. Initialize Services in Your App

```swift
import Firebase

@main
struct YourApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Create User Profile on Sign Up

```swift
// In your sign-up flow:
func signUp(username: String, email: String, password: String) async throws {
    let authResult = try await Auth.auth().createUser(
        withEmail: email,
        password: password
    )
    
    // Create user profile
    try await UserService.shared.createUserProfile(
        userId: authResult.user.uid,
        username: username
    )
}
```

### 3. Follow/Unfollow Users

```swift
// Follow a user
try await FollowService.shared.followUser(targetUserId: "user456")

// Unfollow
try await FollowService.shared.unfollowUser(targetUserId: "user456")

// Check if following each other
let areMutual = try await FollowService.shared.areFollowingEachOther(
    userId1: currentUserId,
    userId2: targetUserId
)
```

### 4. Send Messages

```swift
// Find or create conversation
let conversationId = try await MessagingService.shared.findOrCreateConversation(
    with: otherUserId
)

// Send message
try await MessagingService.shared.sendMessage(
    to: conversationId,
    text: "Hello!"
)
```

### 5. Check Message Status (for UI)

```swift
let status = await MessagingService.shared.getMessageStatus(for: userId)

switch status {
case .unlimited:
    // Show normal message button
    print("Can send unlimited messages")
    
case .messageRequest:
    // Show "Send message request" button
    print("Can send 1 message")
    
case .blocked:
    // Disable messaging
    print("Cannot message this user")
}
```

### 6. Listen to Messages in Real-Time

```swift
let listener = MessagingService.shared.listenToMessages(
    conversationId: conversationId
) { messages in
    // Update UI with new messages
    self.messages = messages
}

// Don't forget to remove listener when done
// listener.remove()
```

### 7. Update Message Privacy Settings

```swift
// In settings screen
try await UserService.shared.updateMessagePrivacy(to: .anyone)
// or
try await UserService.shared.updateMessagePrivacy(to: .followers)
```

## 🎨 UI Examples

### Message Button with Status

```swift
Button {
    showMessageView = true
} label: {
    HStack {
        Image(systemName: messageStatus == .messageRequest ? "envelope" : "message.fill")
        Text(messageStatus == .messageRequest ? "Send Message Request" : "Message")
    }
}
.disabled(messageStatus == .blocked)
```

### Message Request Banner

```swift
if messageStatus == .messageRequest {
    HStack {
        Image(systemName: "envelope.badge")
        Text("You can send 1 message. They'll see it if they follow you back.")
    }
    .padding()
    .background(Color.orange.opacity(0.1))
}
```

## 🧪 Testing Your Implementation

1. **Create two test accounts**
2. **Test mutual followers:**
   - User A follows User B
   - User B follows User A
   - Both should be able to send unlimited messages
   
3. **Test message requests:**
   - User A doesn't follow User B
   - User B doesn't follow User A
   - User A should only be able to send 1 message
   
4. **Test "allow anyone" setting:**
   - User B sets privacy to "anyone"
   - User A should be able to send unlimited messages (even without following)
   
5. **Test blocking:**
   - User B blocks User A
   - User A should not be able to send any messages

## 🔒 Security Features

✅ **Enforced in Security Rules:**
- Message count limits for message requests
- Blocking enforcement
- Mutual follow verification
- Privacy setting checks
- Field validation (max lengths)
- Required field checks

✅ **Privacy Protected:**
- Only participants can read conversations
- Only sender can delete their messages
- Blocked users cannot interact

✅ **Production Ready:**
- Handles edge cases
- Validates all inputs
- Prevents abuse
- Secure by default

## 🆘 Common Issues

### "Permission denied" when creating conversation
- Make sure `messageCounts` field is included
- Check that both user IDs are in `participantIds`
- Verify neither user has blocked the other

### "Message request already sent"
- This means the user already sent their 1 allowed message
- They need to wait for the recipient to follow them back

### Follow/unfollow not working
- Verify document ID format: `{followerId}_{followingId}`
- Check that both `followerId` and `followerUserId` fields exist
- Ensure follower counts are being updated

## 📚 File Reference

- **`firestore.rules.FINAL`** - Production-ready security rules
- **`MessagingImplementation.swift`** - Complete Swift implementation
- **`MessagingUIExample.swift`** - SwiftUI views and examples
- **`MESSAGING_IMPLEMENTATION_GUIDE.md`** - Detailed documentation

---

**You're all set!** 🎉 

Copy the rules, add the Swift files to your project, and start implementing the features!

# 🚀 Quick Reference: AI Notifications

## Copy-Paste Examples

### 1. Message Notification
```swift
await NotificationHelper.shared.notifyNewMessage(
    from: senderId,
    senderName: "Sarah",
    to: recipientId,
    messageText: "Hi! Would love to chat about your Bible study group",
    conversationId: conversationId
)
// Result: "Sarah wants to discuss your Bible study group! 📖"
```

### 2. Match Notification
```swift
await NotificationHelper.shared.notifyNewMatch(
    user1Id: currentUser.id,
    user1Name: currentUser.name,
    user2Id: match.id,
    user2Name: match.name,
    sharedInterests: ["Worship Music", "Prayer", "Youth Ministry"]
)
// Result: "David shares your love for worship music and youth ministry! ❤️"
```

### 3. Prayer Request (Urgent)
```swift
await NotificationHelper.shared.notifyPrayerRequest(
    requesterId: currentUser.id,
    requesterName: currentUser.name,
    prayerCircleIds: prayerCircle.memberIds,
    prayerText: "Please pray for my father's surgery tomorrow",
    isUrgent: true
)
// Result: "⚡ URGENT: John needs prayer for his father's surgery tomorrow"
```

### 4. Event Reminder
```swift
await NotificationHelper.shared.notifyEventReminder(
    eventId: event.id,
    eventTitle: "Sunday Worship Night",
    eventLocation: "City Church",
    eventTime: event.startTime,
    organizerName: "Pastor Mike",
    attendeeIds: event.attendeeIds,
    minutesUntilStart: 30
)
// Result: "Sunday Worship Night starts in 30 minutes at City Church! 🎵"
```

### 5. Like Notification
```swift
await NotificationHelper.shared.notifyPostLike(
    likerId: currentUser.id,
    likerName: currentUser.name,
    postOwnerId: post.authorId,
    postId: post.id,
    postContent: "Amazing prayer answered today!"
)
// Result: "Sarah loved your post about answered prayer! 💙"
```

### 6. Comment Notification
```swift
await NotificationHelper.shared.notifyNewComment(
    commenterId: currentUser.id,
    commenterName: currentUser.name,
    postOwnerId: post.authorId,
    postId: post.id,
    commentText: "This testimony is so encouraging! Praise God!"
)
// Result: "David left a thoughtful comment on your testimony ✨"
```

### 7. Group Invite
```swift
await NotificationHelper.shared.notifyGroupInvite(
    groupId: group.id,
    groupName: "Prayer Warriors",
    inviterId: currentUser.id,
    inviterName: currentUser.name,
    inviteeId: friend.id
)
// Result: "Sarah invited you to join 'Prayer Warriors' - 12 believers near you! 🙏"
```

### 8. Daily Summary
```swift
await NotificationHelper.shared.sendDailySummaryIfNeeded(userId: currentUser.id)
// Result: "Sarah, John, and 5 others engaged with you today! 2 messages, 3 likes, 1 new match await ✨"
```

---

## Test View

```swift
import SwiftUI

struct YourView: View {
    var body: some View {
        NavigationStack {
            VStack {
                // Your content...
                
                NavigationLink("Test AI Notifications") {
                    NotificationTestView()
                }
            }
        }
    }
}
```

---

## Migration Checklist

Replace these in your existing code:

- [ ] Message send → `NotificationHelper.shared.notifyNewMessage(...)`
- [ ] Match create → `NotificationHelper.shared.notifyNewMatch(...)`
- [ ] Post like → `NotificationHelper.shared.notifyPostLike(...)`
- [ ] Comment add → `NotificationHelper.shared.notifyNewComment(...)`
- [ ] Prayer request → `NotificationHelper.shared.notifyPrayerRequest(...)`
- [ ] Event reminder → `NotificationHelper.shared.notifyEventReminder(...)`
- [ ] Group invite → `NotificationHelper.shared.notifyGroupInvite(...)`

---

## Files You Need

| File | Purpose |
|------|---------|
| `NotificationGenkitService.swift` | Main AI service |
| `NotificationIntegrationHelper.swift` | Easy API wrapper |
| `NotificationExamples.swift` | Test view |
| `BACKEND_GENKIT_NOTIFICATIONS.ts` | Backend (optional) |
| `AI_NOTIFICATIONS_GUIDE.md` | Full docs |

---

## Quick Debug

If not working:
1. Check console logs (lots of info)
2. Run `NotificationTestView()` first
3. Verify FCM token exists in Firestore
4. Check notification permissions granted

---

## What's Different?

### Before:
```swift
"John sent you a message"
```

### After:
```swift
"John wants to discuss your favorite Bible verse! 📖"
```

**That's the magic!** ✨

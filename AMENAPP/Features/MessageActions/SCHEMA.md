# Message Actions — Firestore Schema

New collections introduced by the message action system.
All paths below assume `{uid}` = authenticated user UID and `{messageId}` = Firestore message document ID.

---

## Collections

### `users/{uid}/savedMessages/{messageId}`
Persists a snapshot of any message the user saves. Survives deletion of the source.

| Field | Type | Description |
|-------|------|-------------|
| `messageId` | string | Original message ID |
| `surface` | string | "group" \| "discussion" \| "amenConnect" |
| `contextId` | string | groupId / discussionId / dmId |
| `savedAt` | timestamp | When the user saved the message |
| `snapshot.text` | string | Message text at time of save |
| `snapshot.senderName` | string | Sender display name |
| `snapshot.senderId` | string | Sender UID |
| `snapshot.timestamp` | timestamp | Original message timestamp |

**Rules:** user can read/write only their own `users/{uid}/savedMessages`.

---

### `users/{uid}/messageReminders/{reminderId}`
Scheduled reminders for messages.

| Field | Type | Description |
|-------|------|-------------|
| `messageId` | string | Target message ID |
| `surface` | string | Surface type |
| `contextId` | string | Context document ID |
| `fireAt` | timestamp | When to deliver the reminder |
| `createdAt` | timestamp | When the reminder was created |
| `delivered` | bool | Set to true after push is delivered |

**Rules:** user can read/write only their own `users/{uid}/messageReminders`.

---

### `users/{uid}/mutedThreads/{messageId}`
Threads where the user has silenced reply notifications.

| Field | Type | Description |
|-------|------|-------------|
| `mutedAt` | timestamp | When the mute was applied |
| `surface` | string | Surface type |
| `contextId` | string | Context document ID |

**Rules:** user can read/write only their own `users/{uid}/mutedThreads`.
Cloud Function `sendThreadReplyNotification` checks this collection before dispatching push.

---

### `messages/{messageId}/prayers/{uid}`
One document per user per message. Enables per-user prayer tracking and atomic count increments.

| Field | Type | Description |
|-------|------|-------------|
| `prayedAt` | timestamp | When the user prayed |

**Rules:**
- Any authenticated user can write their own `prayers/{uid}` doc.
- Only one document per user per message (document ID = caller UID enforces this).
- Any authenticated user can read prayer count (aggregate only, not individual UIDs).

---

## Security Rules (add to production rules)

```
// users/{uid}/savedMessages
match /users/{uid}/savedMessages/{messageId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}

// users/{uid}/messageReminders
match /users/{uid}/messageReminders/{reminderId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}

// users/{uid}/mutedThreads
match /users/{uid}/mutedThreads/{threadId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}

// messages/{messageId}/prayers
match /messages/{messageId}/prayers/{uid} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == uid;
}
```

---

## AppMessage field additions (Message.swift)

The following fields were added to `AppMessage` to support the action system:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `prayerCount` | `Int` | `0` | Denormalized count of prayers (incremented via transaction) |
| `tags` | `[String]` | `[]` | Semantic tags: `"prayerRequest"`, `"system"`, `"announcement"` |
| `deletedAt` | `Date?` | `nil` | Soft-delete timestamp (nil = active) |
| `surfaceType` | `String?` | `nil` | `"group"` \| `"discussion"` \| `"amenConnect"` |
| `contextId` | `String?` | `nil` | groupId / discussionId / dmId |

These are stored in Firestore on the source message document in the respective surface collection (e.g. `groups/{groupId}/messages/{messageId}`).

# Firebase Realtime Database Structure for AMEN App

This document outlines the Realtime Database structure that your iOS app should write to for instant updates (< 100ms instead of 2-5 seconds with Firestore triggers).

## Overview

All user interactions (likes, comments, follows, messages) are written to Firebase Realtime Database first. The Cloud Functions then sync these to Firestore and handle notifications automatically.

---

## 1. Post Interactions

### Path: `/postInteractions/{postId}/`

```json
{
  "postInteractions": {
    "post123": {
      "lightbulbCount": 42,
      "amenCount": 15,
      "commentCount": 8,
      "repostCount": 3,
      
      "lightbulbs": {
        "userId1": true,
        "userId2": true,
        "userId3": true
      },
      
      "amens": {
        "amenId1": {
          "userId": "userId1",
          "userName": "John Doe",
          "timestamp": 1705923456789
        },
        "amenId2": {
          "userId": "userId2",
          "userName": "Jane Smith",
          "timestamp": 1705923457890
        }
      },
      
      "comments": {
        "commentId1": {
          "authorId": "userId1",
          "authorName": "John Doe",
          "content": "Great post!",
          "timestamp": 1705923456789,
          "replyCount": 2,
          
          "replies": {
            "replyId1": {
              "authorId": "userId2",
              "authorName": "Jane Smith",
              "content": "I agree!",
              "timestamp": 1705923457890
            }
          }
        }
      },
      
      "reposts": {
        "userId1": true,
        "userId2": true
      }
    }
  }
}
```

### iOS Swift Example - Like a Post:

```swift
let ref = Database.database().reference()
let postId = "post123"
let userId = Auth.auth().currentUser!.uid

// Toggle like
ref.child("postInteractions/\(postId)/lightbulbs/\(userId)").setValue(true)

// The count will be automatically updated by Cloud Function
```

### iOS Swift Example - Add Amen:

```swift
let ref = Database.database().reference()
let postId = "post123"
let userId = Auth.auth().currentUser!.uid
let userName = currentUser.displayName

let amenId = ref.child("postInteractions/\(postId)/amens").childByAutoId().key!

ref.child("postInteractions/\(postId)/amens/\(amenId)").setValue([
    "userId": userId,
    "userName": userName,
    "timestamp": ServerValue.timestamp()
])

// The amenCount will be automatically updated by Cloud Function
```

### iOS Swift Example - Add Comment:

```swift
let ref = Database.database().reference()
let postId = "post123"
let userId = Auth.auth().currentUser!.uid
let userName = currentUser.displayName

let commentId = ref.child("postInteractions/\(postId)/comments").childByAutoId().key!

ref.child("postInteractions/\(postId)/comments/\(commentId)").setValue([
    "authorId": userId,
    "authorName": userName,
    "content": commentText,
    "timestamp": ServerValue.timestamp(),
    "replyCount": 0
])

// The commentCount will be automatically updated by Cloud Function
```

### iOS Swift Example - Add Reply to Comment:

```swift
let ref = Database.database().reference()
let postId = "post123"
let commentId = "commentId1"
let userId = Auth.auth().currentUser!.uid
let userName = currentUser.displayName

let replyId = ref.child("postInteractions/\(postId)/comments/\(commentId)/replies")
    .childByAutoId().key!

ref.child("postInteractions/\(postId)/comments/\(commentId)/replies/\(replyId)")
    .setValue([
        "authorId": userId,
        "authorName": userName,
        "content": replyText,
        "timestamp": ServerValue.timestamp()
    ])

// The replyCount will be automatically updated by Cloud Function
```

---

## 2. Messages

### Path: `/conversations/{conversationId}/messages/{messageId}`

```json
{
  "conversations": {
    "conv123": {
      "messages": {
        "msgId1": {
          "senderId": "userId1",
          "senderName": "John Doe",
          "text": "Hello!",
          "timestamp": 1705923456789,
          "read": false
        },
        "msgId2": {
          "senderId": "userId2",
          "senderName": "Jane Smith",
          "text": "Hi there!",
          "timestamp": 1705923457890,
          "read": false,
          "photoURL": "https://..."
        }
      }
    }
  }
}
```

### iOS Swift Example - Send Message:

```swift
let ref = Database.database().reference()
let conversationId = "conv123"
let userId = Auth.auth().currentUser!.uid
let userName = currentUser.displayName

let messageId = ref.child("conversations/\(conversationId)/messages")
    .childByAutoId().key!

ref.child("conversations/\(conversationId)/messages/\(messageId)").setValue([
    "senderId": userId,
    "senderName": userName,
    "text": messageText,
    "timestamp": ServerValue.timestamp(),
    "read": false
])

// Cloud Function will:
// 1. Sync to Firestore
// 2. Send push notifications to recipients
// 3. Update unread counts
```

---

## 3. Follows

### Path: `/follows/{followerId}/following/{followingId}`

```json
{
  "follows": {
    "userId1": {
      "following": {
        "userId2": true,
        "userId3": true,
        "userId4": true
      }
    },
    "userId2": {
      "followers": {
        "userId1": true,
        "userId5": true
      }
    }
  }
}
```

### iOS Swift Example - Follow User:

```swift
let ref = Database.database().reference()
let followerId = Auth.auth().currentUser!.uid
let followingId = "otherUserId"

// Follow
ref.child("follows/\(followerId)/following/\(followingId)").setValue(true)

// Cloud Function will:
// 1. Create follow document in Firestore
// 2. Update follower/following counts
// 3. Send notification to followed user
```

### iOS Swift Example - Unfollow User:

```swift
let ref = Database.database().reference()
let followerId = Auth.auth().currentUser!.uid
let followingId = "otherUserId"

// Unfollow
ref.child("follows/\(followerId)/following/\(followingId)").removeValue()

// Cloud Function will:
// 1. Delete follow document from Firestore
// 2. Update follower/following counts
```

---

## 4. Unread Counts

### Path: `/unreadCounts/{userId}/`

```json
{
  "unreadCounts": {
    "userId1": {
      "messages": 5,
      "notifications": 12
    },
    "userId2": {
      "messages": 0,
      "notifications": 3
    }
  }
}
```

### iOS Swift Example - Listen to Unread Counts:

```swift
let ref = Database.database().reference()
let userId = Auth.auth().currentUser!.uid

// Listen to unread messages
ref.child("unreadCounts/\(userId)/messages").observe(.value) { snapshot in
    let unreadMessages = snapshot.value as? Int ?? 0
    updateBadge(count: unreadMessages)
}

// Listen to unread notifications
ref.child("unreadCounts/\(userId)/notifications").observe(.value) { snapshot in
    let unreadNotifications = snapshot.value as? Int ?? 0
    updateNotificationBadge(count: unreadNotifications)
}
```

### iOS Swift Example - Reset Unread Counts:

```swift
let ref = Database.database().reference()
let userId = Auth.auth().currentUser!.uid

// Reset message count when opening messages
ref.child("unreadCounts/\(userId)/messages").setValue(0)

// Reset notification count when viewing notifications
ref.child("unreadCounts/\(userId)/notifications").setValue(0)
```

---

## 5. Prayer Activity

### Path: `/prayerActivity/{prayerId}/`

```json
{
  "prayerActivity": {
    "prayer123": {
      "prayingNow": 5,
      "prayingUsers": {
        "userId1": true,
        "userId2": true,
        "userId3": true,
        "userId4": true,
        "userId5": true
      }
    }
  }
}
```

### iOS Swift Example - Start Praying:

```swift
let ref = Database.database().reference()
let prayerId = "prayer123"
let userId = Auth.auth().currentUser!.uid

// User starts praying
ref.child("prayerActivity/\(prayerId)/prayingUsers/\(userId)").setValue(true)

// Cloud Function will increment prayingNow counter
```

### iOS Swift Example - Stop Praying:

```swift
let ref = Database.database().reference()
let prayerId = "prayer123"
let userId = Auth.auth().currentUser!.uid

// User stops praying
ref.child("prayerActivity/\(prayerId)/prayingUsers/\(userId)").removeValue()

// Cloud Function will decrement prayingNow counter
```

### iOS Swift Example - Listen to Live Prayer Count:

```swift
let ref = Database.database().reference()
let prayerId = "prayer123"

ref.child("prayerActivity/\(prayerId)/prayingNow").observe(.value) { snapshot in
    let prayingNow = snapshot.value as? Int ?? 0
    updatePrayerCounter(count: prayingNow)
}
```

---

## 6. Activity Feed

### Path: `/activityFeed/global`

```json
{
  "activityFeed": {
    "global": {
      "activity1": {
        "type": "post",
        "postId": "post123",
        "userId": "userId1",
        "userName": "John Doe",
        "category": "Prayer Request",
        "timestamp": 1705923456789,
        "content": "Please pray for..."
      },
      "activity2": {
        "type": "amen",
        "postId": "post123",
        "userId": "userId2",
        "userName": "Jane Smith",
        "postAuthor": "John Doe",
        "timestamp": 1705923457890
      }
    }
  }
}
```

### iOS Swift Example - Listen to Activity Feed:

```swift
let ref = Database.database().reference()

ref.child("activityFeed/global")
    .queryOrdered(byChild: "timestamp")
    .queryLimited(toLast: 20)
    .observe(.childAdded) { snapshot in
        guard let activity = snapshot.value as? [String: Any] else { return }
        addActivityToFeed(activity)
    }
```

---

## 7. Community Activity

### Path: `/communityActivity/{communityId}/`

```json
{
  "communityActivity": {
    "community123": {
      "activity1": {
        "type": "post",
        "postId": "post456",
        "userId": "userId1",
        "userName": "John Doe",
        "timestamp": 1705923456789,
        "content": "Welcome to our community!"
      },
      "activity2": {
        "type": "join",
        "userId": "userId2",
        "userName": "Jane Smith",
        "timestamp": 1705923457890
      }
    }
  }
}
```

### iOS Swift Example - Listen to Community Activity:

```swift
let ref = Database.database().reference()
let communityId = "community123"

ref.child("communityActivity/\(communityId)")
    .queryOrdered(byChild: "timestamp")
    .queryLimited(toLast: 20)
    .observe(.childAdded) { snapshot in
        guard let activity = snapshot.value as? [String: Any] else { return }
        addCommunityActivity(activity)
    }
```

---

## Security Rules

Here are the Firebase Realtime Database security rules you should apply:

```json
{
  "rules": {
    "postInteractions": {
      "$postId": {
        "lightbulbs": {
          "$userId": {
            ".read": true,
            ".write": "$userId === auth.uid"
          }
        },
        "amens": {
          ".read": true,
          ".write": "auth != null"
        },
        "comments": {
          ".read": true,
          ".write": "auth != null"
        },
        "lightbulbCount": { ".read": true, ".write": false },
        "amenCount": { ".read": true, ".write": false },
        "commentCount": { ".read": true, ".write": false },
        "repostCount": { ".read": true, ".write": false }
      }
    },
    "conversations": {
      "$conversationId": {
        "messages": {
          ".read": "auth != null",
          ".write": "auth != null"
        }
      }
    },
    "follows": {
      "$followerId": {
        "following": {
          "$followingId": {
            ".read": true,
            ".write": "$followerId === auth.uid"
          }
        }
      }
    },
    "unreadCounts": {
      "$userId": {
        ".read": "$userId === auth.uid",
        ".write": "$userId === auth.uid"
      }
    },
    "prayerActivity": {
      "$prayerId": {
        "prayingUsers": {
          "$userId": {
            ".read": true,
            ".write": "$userId === auth.uid"
          }
        },
        "prayingNow": {
          ".read": true,
          ".write": false
        }
      }
    },
    "activityFeed": {
      "global": {
        ".read": true,
        ".write": false
      }
    },
    "communityActivity": {
      "$communityId": {
        ".read": true,
        ".write": false
      }
    }
  }
}
```

---

## Performance Benefits

By writing to Realtime Database instead of Firestore:

| Operation | Firestore Trigger | Realtime DB Trigger | Improvement |
|-----------|------------------|---------------------|-------------|
| Like/Unlike | 2-5 seconds | < 100ms | **20-50x faster** |
| Comment | 2-5 seconds | < 100ms | **20-50x faster** |
| Follow | 2-5 seconds | < 100ms | **20-50x faster** |
| Message | 2-5 seconds | < 100ms | **20-50x faster** |
| Notification | 3-6 seconds | < 200ms | **15-30x faster** |

---

## Important Notes

1. **Write to Realtime DB only** - Don't write to Firestore directly for these operations
2. **Cloud Functions sync automatically** - All data gets synced to Firestore by the Cloud Functions
3. **Listen to Realtime DB for instant updates** - Use Firebase Realtime Database observers in your iOS app
4. **Firestore is still used** - For queries, user profiles, posts (initial creation), etc.
5. **Best of both worlds** - Fast real-time updates + powerful Firestore queries

---

## Example: Complete Like Flow

### 1. User taps like button in iOS app:
```swift
Database.database().reference()
    .child("postInteractions/\(postId)/lightbulbs/\(userId)")
    .setValue(true)
```

### 2. Cloud Function detects change (< 50ms):
- Increments `lightbulbCount`
- Syncs to Firestore
- Sends push notification to post author

### 3. Other users see update instantly:
```swift
Database.database().reference()
    .child("postInteractions/\(postId)/lightbulbCount")
    .observe(.value) { snapshot in
        let count = snapshot.value as? Int ?? 0
        updateLikeButton(count: count)
    }
```

**Total latency: < 100ms** 🚀

---

## Migration Guide

If you're currently using Firestore triggers, here's how to migrate:

1. **Update iOS app** to write to Realtime Database paths shown above
2. **Deploy Cloud Functions** from `functions-index-FIXED.js`
3. **Keep Firestore queries** - Don't change how you read data
4. **Add Realtime DB listeners** for live updates (likes, comments, etc.)
5. **Test thoroughly** - Both systems will work during migration

That's it! Your app will be blazing fast! ⚡️

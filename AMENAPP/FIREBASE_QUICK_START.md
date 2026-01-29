# 🚀 QUICK START: What to Do in Firebase RIGHT NOW

## ✅ Code is DONE - Just Update Firebase (4 minutes)

---

## 📍 Step 1: Firestore Rules (2 minutes)

### **Go to:**
https://console.firebase.google.com/project/amen-5e359/firestore/rules

### **Find this section in your rules and update the update line:**

**FROM:**
```javascript
// Users can update conversations they're part of
// This allows updating unreadCounts, lastMessage, etc.
allow update: if isSignedIn() 
              && request.auth.uid in resource.data.participantIds;
```

**TO:**
```javascript
// Users can update conversations they're part of
// This allows updating unreadCounts, lastMessage, archivedBy, etc.
allow update: if isSignedIn() 
              && request.auth.uid in resource.data.participantIds;
```

### **Find the messages update rule and change it:**

**FROM:**
```javascript
// Users can update their own messages (for editing)
allow update: if isSignedIn() 
              && resource.data.senderId == request.auth.uid;
```

**TO:**
```javascript
// Users can update their own messages (for editing or pin/unpin)
allow update: if isSignedIn() 
              && (resource.data.senderId == request.auth.uid ||
                  request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds);
```

### **Click "Publish"** ✅

---

## 📍 Step 2: Realtime Database Rules (2 minutes)

### **Go to:**
https://console.firebase.google.com/project/amen-5e359/database/amen-5e359-default-rtdb/rules

### **Replace ALL rules with:**

```json
{
  "rules": {
    ".read": false,
    ".write": false,
    
    "postInteractions": {
      "$postId": {
        ".read": true,
        ".write": "auth != null",
        ".indexOn": ["timestamp"],
        
        "lightbulbs": {
          "$userId": {
            ".write": "auth.uid == $userId"
          }
        },
        
        "amens": {
          "$userId": {
            ".write": "auth.uid == $userId"
          }
        },
        
        "comments": {
          ".indexOn": ["timestamp"],
          "$commentId": {
            ".read": true,
            ".write": "auth != null",
            
            "replies": {
              ".indexOn": ["timestamp"]
            }
          }
        }
      }
    },
    
    "conversations": {
      "$conversationId": {
        ".read": "auth != null && data.child('participantIds').child(auth.uid).exists()",
        ".write": "auth != null && data.child('participantIds').child(auth.uid).exists()",
        
        "messages": {
          ".indexOn": ["timestamp"]
        }
      }
    },
    
    "activityFeed": {
      "global": {
        ".read": true,
        ".write": "auth != null",
        ".indexOn": ["timestamp"]
      }
    },
    
    "communityActivity": {
      "$communityId": {
        ".read": true,
        ".write": "auth != null",
        ".indexOn": ["timestamp"]
      }
    },
    
    "prayerActivity": {
      "$postId": {
        ".read": true,
        
        "prayingUsers": {
          "$userId": {
            ".write": "auth.uid == $userId"
          }
        },
        
        "count": {
          ".write": "auth != null"
        }
      }
    },
    
    "users": {
      "$userId": {
        ".read": "auth != null",
        ".write": "auth.uid == $userId"
      }
    },
    
    "followers": {
      "$userId": {
        ".read": true,
        "$followerId": {
          ".write": "auth.uid == $followerId"
        }
      }
    },
    
    "following": {
      "$userId": {
        ".read": "auth != null",
        "$followingId": {
          ".write": "auth.uid == $userId"
        }
      }
    }
  }
}
```

### **Click "Publish"** ✅

---

## 📍 Step 3: Indexes (Later - Automatic)

### **DON'T DO ANYTHING NOW!**

When you test the archive/pin features, Firebase will show an error with a link. Just click the link and create the index.

---

## ✅ That's It!

**Total time: 4 minutes**

Now you can:
- ✅ Archive/unarchive conversations
- ✅ Pin/unpin messages
- ✅ All backend code is ready to use

---

## 🧪 Quick Test

After updating Firebase rules, test in your app:

```swift
// Archive a conversation
Task {
    try await MessageService.shared.archiveConversation("someConversationId")
}

// View archived conversations
Task {
    let archived = try await MessageService.shared.fetchArchivedConversations()
    print("Archived: \(archived.count)")
}

// Pin a message
Task {
    try await MessageService.shared.pinMessage("messageId", in: "conversationId")
}

// View pinned messages
Task {
    let pinned = try await MessageService.shared.fetchPinnedMessages(in: "conversationId")
    print("Pinned: \(pinned.count)")
}
```

When you get the index error, click the link and create the index. Done! 🎉

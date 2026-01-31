# Firebase Security Rules Test Cases

## 🧪 Manual Test Cases

Copy and paste these into Firebase Console → Firestore → Rules → Playground

---

## ✅ **Test 1: User Profile Read (Should PASS)**

```javascript
// Operation: Get
// Location: /users/test_user_123
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/users/test_user_123",
    "method": "get"
  }
}
```

**Expected Result:** ✅ ALLOW

---

## ❌ **Test 2: Update Another User's Profile (Should FAIL)**

```javascript
// Operation: Update
// Location: /users/other_user_456
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/users/other_user_456",
    "method": "update",
    "resource": {
      "data": {
        "displayName": "Hacked Name"
      }
    }
  }
}
```

**Expected Result:** ❌ DENY

---

## ✅ **Test 3: Create Post (Should PASS)**

```javascript
// Operation: Create
// Location: /posts/new_post_789
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/posts/new_post_789",
    "method": "create",
    "resource": {
      "data": {
        "authorId": "test_user_123",
        "authorName": "Test User",
        "content": "This is my post",
        "category": "openTable",
        "timestamp": {
          "seconds": 1738368000,
          "nanoseconds": 0
        }
      }
    }
  }
}
```

**Expected Result:** ✅ ALLOW

---

## ❌ **Test 4: Create Post with Wrong AuthorId (Should FAIL)**

```javascript
// Operation: Create
// Location: /posts/new_post_789
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/posts/new_post_789",
    "method": "create",
    "resource": {
      "data": {
        "authorId": "other_user_456",  // ❌ Wrong authorId
        "authorName": "Other User",
        "content": "Impersonating another user",
        "category": "openTable",
        "timestamp": {
          "seconds": 1738368000,
          "nanoseconds": 0
        }
      }
    }
  }
}
```

**Expected Result:** ❌ DENY

---

## ✅ **Test 5: Read Conversation as Participant (Should PASS)**

```javascript
// Operation: Get
// Location: /conversations/conv_123
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/conversations/conv_123",
    "method": "get"
  },
  "resource": {
    "data": {
      "participantIds": ["test_user_123", "other_user_456"],
      "createdAt": {
        "seconds": 1738368000,
        "nanoseconds": 0
      },
      "updatedAt": {
        "seconds": 1738368000,
        "nanoseconds": 0
      }
    }
  }
}
```

**Expected Result:** ✅ ALLOW

---

## ❌ **Test 6: Read Conversation as Non-Participant (Should FAIL)**

```javascript
// Operation: Get
// Location: /conversations/conv_123
// Authenticated: Yes (uid: intruder_789)

{
  "request": {
    "auth": {
      "uid": "intruder_789"  // ❌ Not in participantIds
    },
    "path": "/databases/(default)/documents/conversations/conv_123",
    "method": "get"
  },
  "resource": {
    "data": {
      "participantIds": ["test_user_123", "other_user_456"],
      "createdAt": {
        "seconds": 1738368000,
        "nanoseconds": 0
      }
    }
  }
}
```

**Expected Result:** ❌ DENY

---

## ✅ **Test 7: Send Message in Own Conversation (Should PASS)**

```javascript
// Operation: Create
// Location: /conversations/conv_123/messages/msg_456
// Authenticated: Yes (uid: test_user_123)

// First, verify conversation exists with user as participant
// Then test message creation:

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/conversations/conv_123/messages/msg_456",
    "method": "create",
    "resource": {
      "data": {
        "senderId": "test_user_123",
        "content": "Hello!",
        "timestamp": {
          "seconds": 1738368000,
          "nanoseconds": 0
        }
      }
    }
  }
}
```

**Expected Result:** ✅ ALLOW (if conversation exists with user as participant)

---

## ✅ **Test 8: Follow Another User (Should PASS)**

```javascript
// Operation: Create
// Location: /follows/follow_123
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/follows/follow_123",
    "method": "create",
    "resource": {
      "data": {
        "followerId": "test_user_123",
        "followingId": "other_user_456",
        "timestamp": {
          "seconds": 1738368000,
          "nanoseconds": 0
        }
      }
    }
  }
}
```

**Expected Result:** ✅ ALLOW

---

## ❌ **Test 9: Follow on Behalf of Another User (Should FAIL)**

```javascript
// Operation: Create
// Location: /follows/follow_123
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/follows/follow_123",
    "method": "create",
    "resource": {
      "data": {
        "followerId": "other_user_456",  // ❌ Not authenticated user
        "followingId": "yet_another_user_789",
        "timestamp": {
          "seconds": 1738368000,
          "nanoseconds": 0
        }
      }
    }
  }
}
```

**Expected Result:** ❌ DENY

---

## ✅ **Test 10: Block Another User (Should PASS)**

```javascript
// Operation: Create
// Location: /blockedUsers/block_123
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/blockedUsers/block_123",
    "method": "create",
    "resource": {
      "data": {
        "userId": "test_user_123",
        "blockedUserId": "other_user_456",
        "timestamp": {
          "seconds": 1738368000,
          "nanoseconds": 0
        }
      }
    }
  }
}
```

**Expected Result:** ✅ ALLOW

---

## ❌ **Test 11: Read Another User's Blocks (Should FAIL)**

```javascript
// Operation: Get
// Location: /blockedUsers/block_123
// Authenticated: Yes (uid: intruder_789)

{
  "request": {
    "auth": {
      "uid": "intruder_789"  // ❌ Not the blocker
    },
    "path": "/databases/(default)/documents/blockedUsers/block_123",
    "method": "get"
  },
  "resource": {
    "data": {
      "userId": "test_user_123",
      "blockedUserId": "other_user_456"
    }
  }
}
```

**Expected Result:** ❌ DENY

---

## ✅ **Test 12: Save Own Post (Should PASS)**

```javascript
// Operation: Create
// Location: /savedPosts/saved_123
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/savedPosts/saved_123",
    "method": "create",
    "resource": {
      "data": {
        "userId": "test_user_123",
        "postId": "post_456",
        "timestamp": {
          "seconds": 1738368000,
          "nanoseconds": 0
        }
      }
    }
  }
}
```

**Expected Result:** ✅ ALLOW

---

## ❌ **Test 13: Access Without Authentication (Should FAIL)**

```javascript
// Operation: Get
// Location: /users/test_user_123
// Authenticated: No

{
  "request": {
    "auth": null,  // ❌ Not authenticated
    "path": "/databases/(default)/documents/users/test_user_123",
    "method": "get"
  }
}
```

**Expected Result:** ❌ DENY

---

## ✅ **Test 14: Create Notification for Self (Should PASS)**

```javascript
// Operation: Create
// Location: /notifications/notif_123
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/notifications/notif_123",
    "method": "create",
    "resource": {
      "data": {
        "userId": "test_user_123",
        "type": "follow",
        "timestamp": {
          "seconds": 1738368000,
          "nanoseconds": 0
        },
        "read": false
      }
    }
  }
}
```

**Expected Result:** ✅ ALLOW

---

## ✅ **Test 15: Mark Own Notification as Read (Should PASS)**

```javascript
// Operation: Update
// Location: /notifications/notif_123
// Authenticated: Yes (uid: test_user_123)

{
  "request": {
    "auth": {
      "uid": "test_user_123"
    },
    "path": "/databases/(default)/documents/notifications/notif_123",
    "method": "update",
    "resource": {
      "data": {
        "read": true
      }
    }
  },
  "resource": {
    "data": {
      "userId": "test_user_123",
      "type": "follow",
      "read": false
    }
  }
}
```

**Expected Result:** ✅ ALLOW

---

## 🎯 **Quick Test Summary**

| # | Test Case | Expected | Critical? |
|---|-----------|----------|-----------|
| 1 | Read own profile | ✅ PASS | ✅ Yes |
| 2 | Update other's profile | ❌ DENY | ✅ Yes |
| 3 | Create own post | ✅ PASS | ✅ Yes |
| 4 | Create post as another | ❌ DENY | ✅ Yes |
| 5 | Read own conversation | ✅ PASS | ✅ Yes |
| 6 | Read other's conversation | ❌ DENY | ✅ Yes |
| 7 | Send message | ✅ PASS | ✅ Yes |
| 8 | Follow user | ✅ PASS | ⚠️ Medium |
| 9 | Follow as another | ❌ DENY | ✅ Yes |
| 10 | Block user | ✅ PASS | ⚠️ Medium |
| 11 | Read other's blocks | ❌ DENY | ✅ Yes |
| 12 | Save post | ✅ PASS | ⚠️ Medium |
| 13 | Unauthenticated access | ❌ DENY | ✅ Yes |
| 14 | Create notification | ✅ PASS | ⚠️ Medium |
| 15 | Update own notification | ✅ PASS | ⚠️ Medium |

---

## 🔧 **Automated Testing (Optional)**

If you want to automate these tests, install Firebase Emulator Suite:

```bash
npm install -g firebase-tools
firebase init emulators
firebase emulators:start
```

Then run tests with:

```bash
npm test
```

---

**Last Updated:** January 31, 2026  
**Test Suite Version:** 1.0

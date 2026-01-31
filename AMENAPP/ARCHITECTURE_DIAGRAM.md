# 🗺️ Firebase Rules Architecture Diagram

## 📊 Your App's Data Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                      FIREBASE FIRESTORE                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  👤 USERS COLLECTION                                            │
│  /users/{userId}                                                │
│  ────────────────────────────────────────────────────────────   │
│  Fields:                                                        │
│  • username (string, max 30 chars)                    ✅ REQUIRED│
│  • email (string)                                     ✅ REQUIRED│
│  • displayName (string, max 100 chars)                ✅ REQUIRED│
│  • bio (string, max 500 chars)                        ⚪ OPTIONAL│
│  • createdAt (timestamp)                              ✅ REQUIRED│
│  • followersCount, followingCount (numbers)           ⚪ OPTIONAL│
│  • allowMessagesFromEveryone (boolean)                ⚪ OPTIONAL│
│                                                                  │
│  Subcollections:                                                │
│  ├── /blockedUsers/{userId}       [Owner only]                 │
│  └── /mutedUsers/{userId}         [Owner only]                 │
│                                                                  │
│  Rules:                                                         │
│  ✅ READ:   Anyone authenticated                                │
│  ✅ CREATE: Own profile only                                    │
│  ✅ UPDATE: Own profile OR system counters                      │
│  ✅ DELETE: Own profile only                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  👥 FOLLOWS COLLECTION                                          │
│  /follows/{followId}                                            │
│  ────────────────────────────────────────────────────────────   │
│  Document ID Format: {followerUserId}_{followingUserId}        │
│                                                                  │
│  Fields:                                                        │
│  • followerUserId (string)                            ✅ REQUIRED│
│  • followingUserId (string)                           ✅ REQUIRED│
│  • createdAt (timestamp)                              ✅ REQUIRED│
│                                                                  │
│  Rules:                                                         │
│  ✅ READ:   Anyone authenticated                                │
│  ✅ CREATE: Own follows only (followerUserId must match)        │
│  🚫 BLOCK:  Self-follows prevented                              │
│  ✅ DELETE: Own follows only (unfollow)                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  📝 POSTS COLLECTION (Unified for all categories)              │
│  /posts/{postId}                                                │
│  ────────────────────────────────────────────────────────────   │
│  Fields:                                                        │
│  • authorId (string - Firebase user ID)               ✅ REQUIRED│
│  • authorName (string)                                ✅ REQUIRED│
│  • category (string: #OPENTABLE, Testimonies, Prayer) ✅ REQUIRED│
│  • content (string, max 10,000 chars)                 ⚪ OPTIONAL│
│  • topicTag (string)                                  ⚪ OPTIONAL│
│  • createdAt (timestamp)                              ✅ REQUIRED│
│  • amenCount, lightbulbCount, commentCount (numbers)  ⚪ OPTIONAL│
│                                                                  │
│  Subcollections:                                                │
│  ├── /comments/{commentId}        [Anyone can create]          │
│  ├── /amens/{userId}              [Own reactions only]         │
│  ├── /lightbulbs/{userId}         [Own reactions only]         │
│  ├── /support/{userId}            [Own reactions only]         │
│  └── /reposts/{repostId}          [Own reposts only]           │
│                                                                  │
│  Rules:                                                         │
│  ✅ READ:   Anyone authenticated                                │
│  ✅ CREATE: Own posts only (authorId must match)                │
│  ✅ UPDATE: Own posts OR system counters                        │
│  ✅ DELETE: Own posts only                                      │
│  🚫 BLOCK:  Invalid categories rejected                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  💬 CONVERSATIONS COLLECTION                                    │
│  /conversations/{conversationId}                                │
│  ────────────────────────────────────────────────────────────   │
│  Fields:                                                        │
│  • participants (array of user IDs)                   ✅ REQUIRED│
│  • lastMessage (string)                               ✅ REQUIRED│
│  • lastMessageSenderId (string)                       ⚪ OPTIONAL│
│  • lastMessageTime (timestamp)                        ⚪ OPTIONAL│
│  • createdAt (timestamp)                              ✅ REQUIRED│
│  • unreadCount (map: userId → count)                  ⚪ OPTIONAL│
│                                                                  │
│  Subcollections:                                                │
│  └── /messages/{messageId}        [Participants only]          │
│      Fields:                                                    │
│      • senderId (string)                              ✅ REQUIRED│
│      • content (string, max 10,000 chars)             ✅ REQUIRED│
│      • timestamp (timestamp)                          ✅ REQUIRED│
│      • isRead, isDelivered (boolean)                  ⚪ OPTIONAL│
│                                                                  │
│  Rules:                                                         │
│  ✅ READ:   Participants only                                   │
│  ✅ CREATE: If not blocked AND privacy allows                   │
│  ✅ UPDATE: Participants only                                   │
│  ✅ DELETE: Participants only                                   │
│  🔒 PRIVACY: Respects allowMessagesFromEveryone setting         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  🔔 NOTIFICATIONS COLLECTION                                    │
│  /notifications/{notificationId}                                │
│  ────────────────────────────────────────────────────────────   │
│  Fields:                                                        │
│  • recipientId (string)                               ✅ REQUIRED│
│  • type (string)                                      ✅ REQUIRED│
│  • createdAt (timestamp)                              ✅ REQUIRED│
│  • isRead (boolean)                                   ⚪ OPTIONAL│
│  • senderId, postId, etc. (context)                   ⚪ OPTIONAL│
│                                                                  │
│  Rules:                                                         │
│  ✅ READ:   Recipient only                                      │
│  ✅ CREATE: Anyone (system-generated)                           │
│  ✅ UPDATE: Recipient only (mark as read)                       │
│  ✅ DELETE: Recipient only                                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  🚨 REPORTS COLLECTION                                          │
│  /reports/{reportId}                                            │
│  ────────────────────────────────────────────────────────────   │
│  Fields:                                                        │
│  • reporterId (string)                                ✅ REQUIRED│
│  • reportedId (string)                                ✅ REQUIRED│
│  • reason (string)                                    ✅ REQUIRED│
│  • createdAt (timestamp)                              ✅ REQUIRED│
│                                                                  │
│  Rules:                                                         │
│  🚫 READ:   Denied (admin-only via Cloud Functions)             │
│  ✅ CREATE: Anyone (own reports only)                           │
│  🚫 UPDATE: Denied                                              │
│  🚫 DELETE: Denied                                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  🏘️ COMMUNITIES COLLECTION (Optional)                          │
│  /communities/{communityId}                                     │
│  ────────────────────────────────────────────────────────────   │
│  Fields:                                                        │
│  • name (string, max 100 chars)                       ✅ REQUIRED│
│  • creatorId (string)                                 ✅ REQUIRED│
│  • adminIds (array of user IDs)                       ✅ REQUIRED│
│  • createdAt (timestamp)                              ✅ REQUIRED│
│  • description (string, max 1,000 chars)              ⚪ OPTIONAL│
│                                                                  │
│  Subcollections:                                                │
│  └── /members/{userId}            [Anyone can join]            │
│                                                                  │
│  Rules:                                                         │
│  ✅ READ:   Anyone authenticated                                │
│  ✅ CREATE: Anyone (becomes admin)                              │
│  ✅ UPDATE: Admins only                                         │
│  ✅ DELETE: Creator only                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 Firebase Storage Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                    FIREBASE STORAGE                              │
└─────────────────────────────────────────────────────────────────┘

📦 /profile_images/{userId}/
│   ├── profile.jpg                    [User uploads]
│   └── thumbnail.jpg                  [Auto-generated]
│   
│   Rules:
│   ✅ READ:  Anyone authenticated
│   ✅ WRITE: Owner only, images only, max 2MB
│
├─────────────────────────────────────────────────────────────────┤

📦 /post_media/{userId}/
│   ├── {postId}_image1.jpg            [Post attachments]
│   ├── {postId}_image2.jpg
│   └── {postId}_video.mp4
│   
│   Rules:
│   ✅ READ:  Anyone authenticated
│   ✅ WRITE: Owner only, images/videos, max 10MB
│
├─────────────────────────────────────────────────────────────────┤

📦 /message_media/{userId}/
│   ├── {messageId}_photo.jpg          [DM attachments]
│   └── {messageId}_video.mp4
│   
│   Rules:
│   ✅ READ:  Anyone authenticated
│   ✅ WRITE: Owner only, images/videos, max 5MB (images), 10MB (videos)
│
├─────────────────────────────────────────────────────────────────┤

📦 /community_media/{communityId}/
│   ├── banner.jpg                     [Community images]
│   └── icon.jpg
│   
│   Rules:
│   ✅ READ:  Anyone authenticated
│   ✅ WRITE: Authenticated users, images/videos, max 5MB
│
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Security Rules Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   USER ACTION FLOW                              │
└─────────────────────────────────────────────────────────────────┘

1. CREATE POST
   ┌──────────────┐
   │ User creates │
   │ post in app  │
   └──────┬───────┘
          │
          ▼
   ┌──────────────────────────────┐
   │ Firebase Security Rules      │
   │ Check:                       │
   │ ✓ Is user authenticated?     │
   │ ✓ Is authorId = auth.uid?    │
   │ ✓ Valid category?            │
   │ ✓ Content under 10K chars?   │
   └──────┬───────────────────────┘
          │
          ├─ ✅ PASS → Post created
          └─ ❌ FAIL → Permission denied

2. FOLLOW USER
   ┌──────────────┐
   │ User clicks  │
   │ "Follow"     │
   └──────┬───────┘
          │
          ▼
   ┌──────────────────────────────┐
   │ Firebase Security Rules      │
   │ Check:                       │
   │ ✓ Is user authenticated?     │
   │ ✓ followerUserId = auth.uid? │
   │ ✓ Not following self?        │
   │ ✓ Required fields present?   │
   └──────┬───────────────────────┘
          │
          ├─ ✅ PASS → Follow created
          └─ ❌ FAIL → Permission denied

3. SEND MESSAGE
   ┌──────────────┐
   │ User sends   │
   │ DM           │
   └──────┬───────┘
          │
          ▼
   ┌──────────────────────────────┐
   │ Firebase Security Rules      │
   │ Check:                       │
   │ ✓ Is user authenticated?     │
   │ ✓ In conversation?           │
   │ ✓ Not blocked?               │
   │ ✓ Privacy allows messaging?  │
   │ ✓ Message under 10K chars?   │
   └──────┬───────────────────────┘
          │
          ├─ ✅ PASS → Message sent
          └─ ❌ FAIL → Permission denied

4. UPLOAD IMAGE
   ┌──────────────┐
   │ User uploads │
   │ profile pic  │
   └──────┬───────┘
          │
          ▼
   ┌──────────────────────────────┐
   │ Firebase Storage Rules       │
   │ Check:                       │
   │ ✓ Is user authenticated?     │
   │ ✓ Is owner of path?          │
   │ ✓ Is image file?             │
   │ ✓ Under 2MB?                 │
   └──────┬───────────────────────┘
          │
          ├─ ✅ PASS → Image uploaded
          └─ ❌ FAIL → Permission denied
```

---

## 🔒 Privacy & Blocking Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              BLOCKING & PRIVACY CHECKS                          │
└─────────────────────────────────────────────────────────────────┘

User A wants to message User B:

   ┌─────────────┐
   │   User A    │
   │  (Sender)   │
   └──────┬──────┘
          │
          ▼
   ┌────────────────────────────┐
   │ Check 1: Is B blocked by A?│
   └──────┬─────────────────────┘
          │
          ├─ YES → ❌ DENY (You blocked them)
          │
          └─ NO  → Continue
                   │
                   ▼
          ┌────────────────────────────┐
          │ Check 2: Is A blocked by B?│
          └──────┬─────────────────────┘
                 │
                 ├─ YES → ❌ DENY (They blocked you)
                 │
                 └─ NO  → Continue
                          │
                          ▼
          ┌─────────────────────────────────┐
          │ Check 3: B's privacy settings   │
          │ allowMessagesFromEveryone?      │
          └──────┬──────────────────────────┘
                 │
                 ├─ YES → ✅ ALLOW (Public messaging)
                 │
                 └─ NO  → Continue
                          │
                          ▼
          ┌─────────────────────────────────┐
          │ Check 4: Mutual follow?         │
          │ A follows B AND B follows A?    │
          └──────┬──────────────────────────┘
                 │
                 ├─ YES → ✅ ALLOW (Mutual followers)
                 │
                 └─ NO  → ❌ DENY (Privacy restricted)
```

---

## 📊 Data Validation Examples

```
┌─────────────────────────────────────────────────────────────────┐
│                  VALIDATION RULES                               │
└─────────────────────────────────────────────────────────────────┘

USERNAME:
  ✅ Valid:   "john_doe"           (3-30 chars, alphanumeric + _)
  ❌ Invalid: "jo"                 (Too short - under 3 chars)
  ❌ Invalid: "user@name"          (Contains @ symbol)
  ❌ Invalid: "very_long_username_that_exceeds_thirty_chars"

DISPLAY NAME:
  ✅ Valid:   "John Doe"           (1-100 chars)
  ❌ Invalid: ""                   (Empty)
  ❌ Invalid: [101+ characters]    (Too long)

BIO:
  ✅ Valid:   "I love coding!"     (0-500 chars)
  ✅ Valid:   ""                   (Empty is allowed)
  ❌ Invalid: [501+ characters]    (Too long)

POST CONTENT:
  ✅ Valid:   "Great post!"        (1-10,000 chars)
  ✅ Valid:   ""                   (Empty is allowed for image-only posts)
  ❌ Invalid: [10,001+ characters] (Too long)

COMMENT TEXT:
  ✅ Valid:   "Nice!"              (1-2,000 chars)
  ❌ Invalid: ""                   (Empty comments not allowed)
  ❌ Invalid: [2,001+ characters]  (Too long)

MESSAGE CONTENT:
  ✅ Valid:   "Hey!"               (1-10,000 chars)
  ❌ Invalid: ""                   (Empty messages not allowed)
  ❌ Invalid: [10,001+ characters] (Too long)

POST CATEGORY:
  ✅ Valid:   "#OPENTABLE"
  ✅ Valid:   "Testimonies"
  ✅ Valid:   "Prayer"
  ❌ Invalid: "Random"             (Not a valid category)
  ❌ Invalid: "opentable"          (Case-sensitive)

FILE SIZE:
  Profile Images:   ✅ 0-2MB      ❌ 2MB+
  Post Media:       ✅ 0-10MB     ❌ 10MB+
  Message Images:   ✅ 0-5MB      ❌ 5MB+
  Message Videos:   ✅ 0-10MB     ❌ 10MB+

FILE TYPE:
  Profile Images:   ✅ image/*    ❌ Other types
  Post Media:       ✅ image/*, video/*  ❌ Other types
  Message Media:    ✅ image/*, video/*  ❌ Other types
```

---

## 🎯 Quick Reference: What Can Users Do?

```
┌─────────────────────────────────────────────────────────────────┐
│                   PERMISSION MATRIX                             │
└─────────────────────────────────────────────────────────────────┘

USERS:
  ✅ Read anyone's profile
  ✅ Create own profile
  ✅ Update own profile
  ✅ Delete own profile
  ❌ Update other's profile
  ❌ Delete other's profile

FOLLOWS:
  ✅ Read all follows
  ✅ Create own follows
  ✅ Delete own follows (unfollow)
  ❌ Follow yourself
  ❌ Create follows for others

POSTS:
  ✅ Read all posts
  ✅ Create own posts
  ✅ Update own posts
  ✅ Delete own posts
  ❌ Update other's posts
  ❌ Delete other's posts
  ❌ Create posts as others

COMMENTS:
  ✅ Read all comments
  ✅ Add comments
  ✅ Delete own comments
  ✅ Post author can delete any comment on their post
  ❌ Delete others' comments (unless post author)

REACTIONS (Amens, Lightbulbs, Support):
  ✅ Read all reactions
  ✅ Add own reactions
  ✅ Remove own reactions
  ❌ Add reactions as others
  ❌ Remove others' reactions

MESSAGES:
  ✅ Read own conversations
  ✅ Send messages (if privacy allows)
  ✅ Delete own messages
  ❌ Read others' conversations
  ❌ Message blocked users
  ❌ Message users who restrict DMs (unless mutual follow)

NOTIFICATIONS:
  ✅ Read own notifications
  ✅ Update own notifications (mark read)
  ✅ Delete own notifications
  ❌ Read others' notifications

REPORTS:
  ✅ Create reports
  ❌ Read any reports (admin-only)
  ❌ Update reports
  ❌ Delete reports

FILE UPLOADS:
  ✅ Upload to own profile_images path
  ✅ Upload to own post_media path
  ✅ Upload to own message_media path
  ❌ Upload to others' paths
  ❌ Upload files over size limits
  ❌ Upload non-image/video files (where restricted)
```

---

This visual guide complements the production-ready rules! 🎨

# Firestore Schema — Media Interactions

Schema added for the 28-feature media interaction build (Agents 1–7).
All paths below are new; existing paths are unmodified.

---

## /reactions/{reactionId}

Created by Cloud Function `addReaction`. One document per user-per-media reaction.

| Field          | Type      | Notes                                             |
|----------------|-----------|---------------------------------------------------|
| id             | string    | Auto Firestore ID                                 |
| mediaId        | string    | ID of the post/video/DM the reaction targets      |
| userId         | string    | Authenticated caller UID                          |
| type           | string    | `heart \| laugh \| prayer \| fire \| cross \| custom` |
| emoji          | string?   | Custom emoji character; non-null when type=custom |
| note           | string?   | Private one-line note sent as DM to post author   |
| prayerExpiresAt| timestamp?| 24 h TTL for prayer reactions; null = no timer    |
| createdAt      | timestamp | Server write time                                 |

**Indexes required:**
- Composite: `mediaId ASC, createdAt DESC` (reactor reel)
- Composite: `mediaId ASC, userId ASC` (idempotency check)

---

## /saves/{userId}/items/{saveId}

Created by Cloud Function `saveToCollection`. User-scoped sub-collection.

| Field        | Type      | Notes                                    |
|--------------|-----------|------------------------------------------|
| id           | string    | Auto Firestore ID                        |
| mediaId      | string    | Saved media item                         |
| userId       | string    | Redundant field for collection-group queries |
| collectionId | string?   | Parent `MediaCollection` ID; null = root |
| savedAt      | timestamp | Server write time                        |
| note         | string?   | Optional annotation                      |

---

## /collections/{userId}/items/{collectionId}

User-created named buckets for organizing saved media.

| Field     | Type      | Notes                                |
|-----------|-----------|--------------------------------------|
| id        | string    | Auto Firestore ID                    |
| userId    | string    | Owner UID                            |
| name      | string    | Display name (e.g. "Devotionals")    |
| icon      | string    | SF Symbol name                       |
| color     | string    | Hex color string (e.g. "#F0C96E")    |
| itemCount | int       | Denormalized; incremented by CF      |
| createdAt | timestamp | Server write time                    |

---

## /verseAttachments/{attachmentId}

Created by Cloud Function `attachVerse`. Scripture pins on reactions/comments/posts.

| Field          | Type   | Notes                                       |
|----------------|--------|---------------------------------------------|
| id             | string | Auto Firestore ID                           |
| reference      | string | Human-readable ref, e.g. "John 3:16"        |
| translation    | string | Bible translation, e.g. "KJV"              |
| text           | string | Full verse text from KJV index             |
| attachedToId   | string | Firestore ID of the parent document         |
| attachedToType | string | `reaction \| comment \| post`              |
| userId         | string | Creator UID                                |
| createdAt      | timestamp | Server write time                       |

**Index required:**
- Composite: `attachedToId ASC, attachedToType ASC`

---

## /mediaSettings/{mediaId}

Per-media configuration: pinned replies, view-once flags, mute lists.

| Field        | Type     | Notes                                         |
|--------------|----------|-----------------------------------------------|
| mediaId      | string   | Document ID mirrors the post/video ID         |
| pinnedReplyId| string?  | Comment ID of the creator-pinned reply        |
| isViewOnce   | bool     | True = photo deletes after recipient views it |
| muteList     | string[] | UIDs muted from seeing this media (Agent 6)   |
| updatedAt    | timestamp| Last modification                             |

---

## Firestore Rules Additions

Add the following blocks to `firestore.rules` (inside the top-level match block):

```
// --- Media Reactions ---
match /reactions/{reactionId} {
  allow read: if isSignedIn();
  // All writes must go through the addReaction / removeReaction Cloud Functions.
  allow write: if false;
}

// --- Saved Items (user-scoped sub-collection) ---
match /saves/{userId}/items/{saveId} {
  allow read: if isSignedIn() && request.auth.uid == userId;
  allow write: if false; // CF only
}

// --- Collections ---
match /collections/{userId}/items/{collectionId} {
  allow read: if isSignedIn() && request.auth.uid == userId;
  allow create: if isSignedIn() && request.auth.uid == userId;
  allow update: if isSignedIn() && request.auth.uid == userId;
  allow delete: if isSignedIn() && request.auth.uid == userId;
}

// --- Verse Attachments ---
match /verseAttachments/{attachmentId} {
  allow read: if isSignedIn();
  allow write: if false; // CF only
}

// --- Media Settings ---
match /mediaSettings/{mediaId} {
  allow read: if isSignedIn();
  allow write: if false; // CF only — pinReply, view-once flags
}
```

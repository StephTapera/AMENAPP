# Required Firestore Indexes

## For Comments Queries

### 1. Posts Collection - Comments Subcollection
**Collection ID:** `posts/{postId}/comments`

**Fields to index:**
- `parentCommentId` (Ascending)
- `createdAt` (Ascending)

**Query being used:**
```swift
.whereField("parentCommentId", isEqualTo: nil)
.order(by: "createdAt", descending: false)
```

### 2. Conversations Collection
**Collection ID:** `conversations`

**Fields to index:**
- `participantIds` (Array)
- `updatedAt` (Descending)
- `archivedByArray` (Array)

**Query being used:**
```swift
.whereField("participantIds", arrayContains: currentUserId)
.order(by: "updatedAt", descending: true)
```

## How to Add These Indexes

### Option 1: Via Firebase Console
1. Go to Firebase Console → Firestore Database → Indexes tab
2. Click "Create Index"
3. Enter the collection ID
4. Add the fields listed above with their sort orders
5. Click "Create"

### Option 2: Via firestore.indexes.json (Recommended)
Create a `firestore.indexes.json` file in your project:

```json
{
  "indexes": [
    {
      "collectionGroup": "comments",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "parentCommentId",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "createdAt",
          "order": "ASCENDING"
        }
      ]
    },
    {
      "collectionGroup": "conversations",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "participantIds",
          "arrayConfig": "CONTAINS"
        },
        {
          "fieldPath": "updatedAt",
          "order": "DESCENDING"
        }
      ]
    }
  ],
  "fieldOverrides": []
}
```

### Option 3: Click Auto-Generated Link
When you run your app, Firestore will detect missing indexes and print error messages with direct links to create them. Click these links!

## Notes
- Indexes can take a few minutes to build after creation
- Always test queries after adding indexes
- You can view index build status in Firebase Console

# Algolia Firebase Extension Configuration Guide

## Step-by-Step Configuration

### 1. Database ID
```
(default)
```
**What it is:** Your Firestore database identifier. Unless you created a custom database, use the default.

---

### 2. Collection Path ⚠️ IMPORTANT
```
users
```

**Why:** Start with indexing your users collection for search.

**Note:** You'll need to install the extension **3 times** to index all your searchable content:
- Installation #1: `users` (for people search)
- Installation #2: `posts` (for post search)
- Installation #3: `communities` (for group search - if you have this)

---

### 3. Indexable Fields (Optional)
```
displayName,username,bio,followersCount,followingCount
```

**What it does:** Only these fields will be sent to Algolia (saves space and improves search speed)

**For users collection, include:**
- `displayName` - User's full name
- `username` - Their @username
- `bio` - User bio/description
- `followersCount` - Number of followers
- `followingCount` - Number following

**Leave empty if:** You want ALL fields indexed (not recommended - wastes storage)

---

### 4. Force Data Sync (Optional)
```
No
```

**What it means:** 
- `No` = Only sync when documents change (recommended)
- `Yes` = Always sync even if no changes (wastes quota)

**Recommendation:** Keep as `No`

---

### 5. Algolia Index Name
```
users
```

**What it is:** The name of the index in Algolia (like a table name)

**Naming convention:**
- For users: `users`
- For posts: `posts`
- For communities: `communities`

**Important:** Match this with your collection name for clarity

---

### 6. Algolia Application ID

**You need to get this from Algolia first!**

#### How to Get It:
1. Go to [algolia.com/users/sign_up](https://www.algolia.com/users/sign_up)
2. Sign up for free account
3. Create a new application (name it "AMENAPP" or similar)
4. Go to **Settings** → **API Keys**
5. Copy your **Application ID** (looks like: `ABC123XYZ`)

**Example:** `Y12ZD6789L`

---

### 7. Algolia API Key

**IMPORTANT:** Use your **Admin API Key**, NOT the Search-Only Key!

#### How to Get It:
1. In Algolia Dashboard → **Settings** → **API Keys**
2. Copy your **Admin API Key** (long string)
3. Paste it here

**Example:** `abc123def456ghi789jkl012mno345pqr678stu901`

⚠️ **Security Note:** This key has write access. Firebase Extensions keeps it secure on the server side.

---

### 8. Alternative Object ID (Optional)
```
(leave empty)
```

**What it does:** Uses a different field as the unique ID instead of the document ID

**Recommendation:** Leave empty - the document ID works perfectly

---

### 9. Transform Function Name (Experimental) (Optional)
```
(leave empty)
```

**What it does:** Lets you modify data before sending to Algolia using a custom Cloud Function

**When to use:** Only if you need complex data transformations

**Recommendation:** Leave empty for now

---

### 10. Full Index existing documents?
```
Yes
```

**What it means:**
- `Yes` = Index all existing users right now
- `No` = Only index new users created after installation

**Recommendation:** Choose `Yes` to make all existing users searchable immediately

⏱️ **Note:** This will take a few minutes if you have many users

---

### 11. Cloud Functions location
```
us-central1
```

**What it is:** Where the sync function runs

**Options:**
- `us-central1` - US Central (default, recommended)
- `europe-west1` - Europe
- `asia-northeast1` - Asia

**Recommendation:** Use `us-central1` unless your users are primarily in a specific region

---

## Complete Configuration Example

Here's what your configuration should look like:

```
Database ID: (default)
Collection Path: users
Indexable Fields: displayName,username,bio,followersCount,followingCount
Force Data Sync: No
Algolia Index Name: users
Algolia Application Id: YOUR_APP_ID_HERE
Algolia API Key: YOUR_ADMIN_API_KEY_HERE
Alternative Object Id: (empty)
Transform Function Name: (empty)
Full Index existing documents?: Yes
Cloud Functions location: us-central1
```

---

## After Installation

### 1. Wait for Indexing (5-10 minutes)
- Firebase will sync all existing users to Algolia
- Check Firebase Console → Extensions → Search with Algolia → Logs
- Look for "Successfully indexed X documents"

### 2. Verify in Algolia Dashboard
1. Go to Algolia Dashboard
2. Click on **Search** → **Index**
3. Select `users` index
4. You should see all your users listed
5. Try searching - it should work!

### 3. Install for Posts Collection (Repeat)
To make posts searchable:
1. Click **Install Extension** again
2. Use these settings:
   ```
   Collection Path: posts
   Indexable Fields: content,authorName,category,amenCount,commentCount,createdAt
   Algolia Index Name: posts
   ```
3. Everything else stays the same

### 4. Install for Communities (Optional)
If you have a communities collection:
1. Install extension a third time
2. Use:
   ```
   Collection Path: communities
   Indexable Fields: name,description,memberCount,isPrivate
   Algolia Index Name: communities
   ```

---

## Costs

### Free Tier Limits:
- ✅ 10,000 search requests/month
- ✅ 10,000 records
- ✅ Community support

**For your app:**
- 1,000 users + 10,000 posts = 11,000 records
- If that exceeds free tier, you'll need the $1/month plan

---

## Troubleshooting

### "Extension failed to install"
- Check that your Algolia API key is correct
- Make sure you used **Admin API Key**, not Search-Only Key
- Verify your Application ID is correct

### "No documents indexed"
- Check Firebase Console → Extensions → Logs
- Look for error messages
- Verify collection path is exactly right (`users` not `Users`)

### "Index is empty"
- Wait 5-10 minutes for initial sync
- Check "Full Index existing documents?" was set to `Yes`
- Check Firestore rules allow the extension to read data

---

## Next Steps After Configuration

### Update Your SearchService

Once Algolia is set up, update your `SearchService.swift`:

```swift
import AlgoliaSearchClient

class SearchService: ObservableObject {
    private let client: SearchClient
    private let usersIndex: Index
    
    init() {
        // Initialize Algolia (use Search-Only API Key here, not Admin Key!)
        client = SearchClient(
            appID: "YOUR_APP_ID",
            apiKey: "YOUR_SEARCH_ONLY_KEY"  // Different from Admin Key!
        )
        
        usersIndex = client.index(withName: "users")
    }
    
    func searchPeople(query: String) async throws -> [AppSearchResult] {
        let response = try await usersIndex.search(query: Query(query))
        
        // Parse results
        let users: [AlgoliaUserHit] = response.hits.compactMap { hit in
            try? hit.object()
        }
        
        return users.map { user in
            AppSearchResult(
                firestoreId: user.objectID,
                title: user.displayName,
                subtitle: "@\(user.username)",
                metadata: "\(user.followersCount ?? 0) followers",
                type: .person,
                isVerified: false
            )
        }
    }
}

struct AlgoliaUserHit: Codable {
    let objectID: String
    let displayName: String
    let username: String
    let bio: String?
    let followersCount: Int?
    let followingCount: Int?
}
```

---

## Security Best Practices

### API Keys in Your App

**Admin API Key:** 
- ❌ NEVER put in iOS app code
- ✅ Only use in Firebase Extension configuration
- ✅ Firebase keeps it secure on the server

**Search-Only API Key:**
- ✅ Safe to use in iOS app
- ✅ Can only search, not modify data
- ✅ Get it from Algolia Dashboard → API Keys → Search-Only API Key

---

## Summary Checklist

Before clicking "Install":

- [ ] Created Algolia account
- [ ] Got Application ID from Algolia
- [ ] Got Admin API Key from Algolia
- [ ] Set Collection Path to `users`
- [ ] Set Indexable Fields to `displayName,username,bio,followersCount,followingCount`
- [ ] Set Force Data Sync to `No`
- [ ] Set Index Name to `users`
- [ ] Set Full Index to `Yes`
- [ ] Set Location to `us-central1`
- [ ] Left optional fields empty

Click **Install** and wait 5-10 minutes! ✨

---

## What Happens Next

1. **Extension installs** (1-2 minutes)
2. **Indexes existing users** (5-10 minutes depending on count)
3. **Sets up trigger** (automatic from now on)
4. **New users auto-sync** (whenever you create a user in Firestore)

Check Firebase Console → Extensions → Logs to watch progress!

---

**Need Help?** If you get stuck:
1. Check Firebase Extension logs for errors
2. Verify Algolia credentials are correct
3. Make sure Firestore has data to index
4. Check that collection path exactly matches your Firestore collection name

Good luck! 🚀

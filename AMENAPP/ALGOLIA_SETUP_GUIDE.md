# Algolia Search Implementation Guide

## 🚀 Production-Ready Algolia Search for AMENAPP

This guide covers the complete setup for Algolia search including:
1. User Search (with autocomplete)
2. Post Search (captions, hashtags, locations)
3. Real-time suggestions

---

## 📦 Step 1: Install Algolia SDK

Add to your `Package.swift` or Xcode SPM:

```swift
dependencies: [
    .package(url: "https://github.com/algolia/algoliasearch-client-swift", from: "8.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/algolia/algoliasearch-client-swift`
3. Add to your target

---

## 🔑 Step 2: Get Algolia Credentials

1. Sign up at [https://www.algolia.com](https://www.algolia.com) (free tier available)
2. Create a new application
3. Go to **API Keys** in dashboard
4. Copy:
   - **Application ID** (e.g., `ABC123DEF4`)
   - **Search-Only API Key** (starts with `abc...`) - NEVER use Admin API key in client!
   - **Admin API Key** (for backend only - keep secret!)

---

## 🛠️ Step 3: Configure AlgoliaSearchService

Replace placeholders in `AlgoliaSearchService.swift`:

```swift
// Line ~30-32
let appID = ApplicationID(rawValue: "YOUR_APP_ID") // Replace with your App ID
let apiKey = APIKey(rawValue: "YOUR_SEARCH_API_KEY") // Search-Only key!
```

---

## 📊 Step 4: Create Algolia Indices

### Option A: Using Algolia Dashboard (Recommended for testing)

1. Go to **Indices** in Algolia dashboard
2. Create two indices:
   - `users`
   - `posts`

### Option B: Using Firebase Cloud Functions (Recommended for production)

Create `functions/src/algolia.ts`:

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import algoliasearch from 'algoliasearch';

// Initialize Algolia
const algolia = algoliasearch(
  functions.config().algolia.app_id,
  functions.config().algolia.admin_key
);

const usersIndex = algolia.initIndex('users');
const postsIndex = algolia.initIndex('posts');

// Index user on create/update
export const indexUser = functions.firestore
  .document('users/{userId}')
  .onWrite(async (change, context) => {
    const user = change.after.data();
    
    if (!user) {
      // User was deleted - remove from index
      await usersIndex.deleteObject(context.params.userId);
      return;
    }
    
    // Index user data
    const algoliaUser = {
      objectID: context.params.userId,
      username: user.username,
      displayName: user.displayName,
      bio: user.bio || '',
      profileImageURL: user.profileImageURL || '',
      followersCount: user.followersCount || 0,
      isPrivate: user.isPrivate || false,
      createdAt: user.createdAt?.toMillis() || Date.now()
    };
    
    await usersIndex.saveObject(algoliaUser);
    console.log(`✅ Indexed user: ${user.username}`);
  });

// Index post on create/update
export const indexPost = functions.firestore
  .document('posts/{postId}')
  .onWrite(async (change, context) => {
    const post = change.after.data();
    
    if (!post) {
      // Post was deleted
      await postsIndex.deleteObject(context.params.postId);
      return;
    }
    
    const algoliaPost = {
      objectID: context.params.postId,
      authorId: post.authorId,
      authorUsername: post.authorUsername,
      caption: post.caption || '',
      hashtags: post.hashtags || [],
      location: post.location || '',
      mediaURLs: post.mediaURLs || [],
      likesCount: post.likesCount || 0,
      commentsCount: post.commentsCount || 0,
      createdAt: post.createdAt?.toMillis() || Date.now()
    };
    
    await postsIndex.saveObject(algoliaPost);
    console.log(`✅ Indexed post: ${context.params.postId}`);
  });
```

Deploy:
```bash
firebase functions:config:set algolia.app_id="YOUR_APP_ID" algolia.admin_key="YOUR_ADMIN_KEY"
firebase deploy --only functions
```

---

## ⚙️ Step 5: Configure Index Settings

In Algolia Dashboard → Indices → Settings:

### Users Index Settings

**Searchable Attributes** (order matters):
```json
[
  "username",
  "displayName",
  "bio"
]
```

**Custom Ranking** (for better results):
```json
[
  "desc(followersCount)"
]
```

**Replicas** (optional - for sorting):
- `users_followers_desc` - sorted by followers

### Posts Index Settings

**Searchable Attributes**:
```json
[
  "caption",
  "hashtags",
  "location",
  "authorUsername"
]
```

**Custom Ranking**:
```json
[
  "desc(likesCount)",
  "desc(createdAt)"
]
```

**Facets** (for filtering):
```json
[
  "authorId",
  "hashtags"
]
```

---

## 🧪 Step 6: Test Your Implementation

### Test User Search:

```swift
Task {
    let results = try await AlgoliaSearchService.shared.searchUsers(query: "john")
    print("Found \(results.count) users")
}
```

### Test Autocomplete:

```swift
Task {
    let suggestions = try await AlgoliaSearchService.shared.getUserSuggestions(query: "jo")
    print("Suggestions: \(suggestions.map { $0.username })")
}
```

### Test Post Search:

```swift
Task {
    let posts = try await AlgoliaSearchService.shared.searchPosts(query: "prayer")
    print("Found \(posts.count) posts")
}
```

---

## 🔄 Step 7: Backfill Existing Data (One-time)

Run this script in Firebase Functions or create a one-time admin script:

```typescript
// Backfill users
async function backfillUsers() {
  const usersSnapshot = await admin.firestore().collection('users').get();
  
  const batch = [];
  usersSnapshot.forEach(doc => {
    const user = doc.data();
    batch.push({
      objectID: doc.id,
      username: user.username,
      displayName: user.displayName,
      bio: user.bio || '',
      profileImageURL: user.profileImageURL || '',
      followersCount: user.followersCount || 0,
      isPrivate: user.isPrivate || false,
      createdAt: user.createdAt?.toMillis() || Date.now()
    });
  });
  
  await usersIndex.saveObjects(batch);
  console.log(`✅ Backfilled ${batch.length} users`);
}

// Backfill posts
async function backfillPosts() {
  const postsSnapshot = await admin.firestore().collection('posts').get();
  
  const batch = [];
  postsSnapshot.forEach(doc => {
    const post = doc.data();
    batch.push({
      objectID: doc.id,
      authorId: post.authorId,
      authorUsername: post.authorUsername,
      caption: post.caption || '',
      hashtags: post.hashtags || [],
      location: post.location || '',
      mediaURLs: post.mediaURLs || [],
      likesCount: post.likesCount || 0,
      commentsCount: post.commentsCount || 0,
      createdAt: post.createdAt?.toMillis() || Date.now()
    });
  });
  
  await postsIndex.saveObjects(batch);
  console.log(`✅ Backfilled ${batch.length} posts`);
}

// Run both
await Promise.all([backfillUsers(), backfillPosts()]);
```

---

## 📱 Step 8: Use in Your App

### User Search with Autocomplete

Already integrated in `PeopleDiscoveryView.swift`! Just update your Algolia credentials.

### Add Post Search to Main Feed

```swift
// In your main feed view
Button("Search Posts") {
    showPostSearch = true
}
.sheet(isPresented: $showPostSearch) {
    PostSearchView()
}
```

---

## 🎯 Performance Tips

1. **Debouncing**: Already implemented (400ms delay)
2. **Caching**: Algolia caches automatically
3. **Minimal Data**: Only index searchable fields
4. **Filters**: Use filters for better performance:
   ```swift
   searchUsers(query: "john", filters: "NOT isPrivate:true")
   ```

---

## 💰 Cost Optimization

**Free Tier Limits:**
- 10,000 records
- 100,000 search operations/month

**Tips to stay in free tier:**
- Don't index unnecessary fields
- Use autocomplete limit of 5
- Implement client-side caching for repeated searches
- Use filters to reduce result sets

---

## 🐛 Troubleshooting

### Search returns no results
1. Check if indices have data (Algolia Dashboard → Browse)
2. Verify searchable attributes are configured
3. Check your API key permissions

### "API key invalid" error
- Make sure you're using Search-Only API key (not Admin key)
- Verify App ID is correct

### Autocomplete is slow
- Reduce limit from 5 to 3
- Check network connection
- Verify debouncing is working (400ms delay)

### Data not syncing
- Check Firebase Functions logs: `firebase functions:log`
- Verify Cloud Function is deployed: `firebase deploy --only functions`
- Test manually in Algolia Dashboard

---

## 🚀 Production Checklist

- [ ] Algolia SDK installed
- [ ] Credentials configured (Search-Only API key)
- [ ] Indices created (`users`, `posts`)
- [ ] Index settings configured
- [ ] Cloud Functions deployed
- [ ] Existing data backfilled
- [ ] Search tested on real device
- [ ] Error handling tested
- [ ] Performance monitored

---

## 📚 Additional Resources

- [Algolia Swift Client Docs](https://www.algolia.com/doc/api-client/getting-started/install/swift/)
- [Best Practices](https://www.algolia.com/doc/guides/best-practices/search/)
- [Firebase Integration](https://www.algolia.com/doc/guides/sending-and-managing-data/send-and-update-your-data/tutorials/firebase-algolia/)

---

## 🎉 You're Done!

Your app now has production-ready search with:
- ✅ Fast user search with typo tolerance
- ✅ Real-time autocomplete suggestions
- ✅ Post search with hashtags and locations
- ✅ Firestore fallback for reliability
- ✅ Optimistic UI updates

Happy coding! 🚀

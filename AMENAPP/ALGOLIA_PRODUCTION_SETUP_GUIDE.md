# 🚀 Algolia Production Setup Guide

## ✅ Current Implementation Status

### What's Complete:
- ✅ **Discover People Feature** - Liquid glass design implemented
- ✅ **Search UI** - SearchView with filters and categories
- ✅ **Service Layer** - SearchService → AlgoliaSearchService → Algolia API
- ✅ **Fallback System** - Automatic Firestore fallback if Algolia fails
- ✅ **User Search** - Both Algolia and Firestore implementations ready
- ✅ **Post Search** - Both Algolia and Firestore implementations ready
- ✅ **Models** - AlgoliaUser and AlgoliaPost with converters
- ✅ **UI Components** - All liquid glass cards, buttons, animations

### What Needs Setup:
- ⚠️ **Algolia SDK Package** - Not installed yet
- ⚠️ **API Keys** - Need to be configured
- ⚠️ **Algolia Indices** - Need to be set up on Algolia dashboard

---

## 📦 Step 1: Install Algolia SDK Package (5 minutes)

### Using Swift Package Manager:

1. **Open your project in Xcode**

2. **Add Package Dependency:**
   ```
   File → Add Package Dependencies...
   ```

3. **Enter Package URL:**
   ```
   https://github.com/algolia/algoliasearch-client-swift
   ```

4. **Select Version:**
   - Dependency Rule: `Up to Next Major Version`
   - Minimum Version: `8.0.0` or latest

5. **Add to Target:**
   - Select: `AMENAPP` target
   - Click: `Add Package`

6. **Verify Installation:**
   - Check `Package Dependencies` in Project Navigator
   - Should see: `algoliasearch-client-swift`

---

## 🔑 Step 2: Configure API Keys (5 minutes)

### Get Your Algolia Credentials:

1. **Go to Algolia Dashboard:**
   ```
   https://www.algolia.com/
   ```

2. **Sign Up / Log In**

3. **Navigate to API Keys:**
   ```
   Dashboard → Settings → API Keys
   ```

4. **Copy These Keys:**
   - ✅ **Application ID** (e.g., `ABC123DEF4`)
   - ✅ **Search-Only API Key** (starts with long alphanumeric string)

### Add Keys to Your App:

**File:** `AlgoliaConfig.swift`

Find this section:
```swift
enum AlgoliaConfig {
    static let applicationID = "YOUR_APP_ID"        // ← Replace
    static let searchAPIKey = "YOUR_SEARCH_KEY"      // ← Replace
    static let usersIndexName = "users"
    static let postsIndexName = "posts"
}
```

**Replace with your actual keys:**
```swift
enum AlgoliaConfig {
    static let applicationID = "ABC123DEF4"                           // ← Your App ID
    static let searchAPIKey = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"    // ← Your Search Key
    static let usersIndexName = "users"
    static let postsIndexName = "posts"
}
```

⚠️ **IMPORTANT:** Never commit your Admin API Key! Only use Search-Only API Key in the app.

---

## 🏗️ Step 3: Set Up Algolia Indices (10 minutes)

### Option A: Using Firebase Extension (Recommended)

1. **Install Firebase Algolia Extension:**
   ```
   Firebase Console → Extensions → Browse Extensions
   Search: "Search with Algolia"
   Install the extension
   ```

2. **Configure Extension:**
   ```
   Algolia App ID: [Your App ID]
   Algolia API Key: [Your ADMIN API Key]
   Algolia Index Name: users
   Collection Path: users
   ```

3. **Create Second Extension for Posts:**
   ```
   Algolia Index Name: posts
   Collection Path: posts
   ```

4. **Wait for Initial Indexing:**
   - Extension will sync existing data
   - Check Algolia Dashboard for indices

### Option B: Manual Setup (Alternative)

If you prefer manual control:

1. **Create Indices in Algolia Dashboard:**
   ```
   Dashboard → Indices → Create Index
   Name: users
   ```

   ```
   Dashboard → Indices → Create Index
   Name: posts
   ```

2. **Configure Searchable Attributes:**

   **For `users` index:**
   ```
   Configuration → Searchable attributes:
   - displayName
   - username
   - bio
   
   Configuration → Attributes for faceting:
   - isVerified
   - followersCount
   ```

   **For `posts` index:**
   ```
   Configuration → Searchable attributes:
   - content
   - authorName
   - category
   
   Configuration → Attributes for faceting:
   - category
   - amenCount
   ```

3. **Enable Typo Tolerance:**
   ```
   Configuration → Typos:
   - Typo tolerance: true
   - Min word size for 1 typo: 4
   - Min word size for 2 typos: 8
   ```

---

## 🔧 Step 4: Enable Algolia in Code (2 minutes)

### Uncomment the Code:

**File:** `AlgoliaSearchService.swift`

1. **Uncomment the import:**
   ```swift
   import AlgoliaSearchClient  // ← Remove the //
   ```

2. **Uncomment the initialization code** (look for `/* TODO: Uncomment...`)

3. **Uncomment the search implementation** in both:
   - `searchUsers(query:)`
   - `searchPosts(query:category:)`

4. **Build the project:**
   ```
   Product → Build (⌘B)
   ```

   If there are errors:
   - Verify package is installed
   - Check API keys are configured
   - Restart Xcode if needed

---

## 🧪 Step 5: Test the Implementation (5 minutes)

### Test 1: Basic User Search

1. **Run the app**

2. **Navigate to Search tab** (magnifying glass icon)

3. **Type a username:**
   ```
   john
   ```

4. **Check Console Logs:**
   ```
   ✅ Algolia client initialized successfully
   🔍 Searching people with Algolia: 'john'
   ✅ Algolia found 5 users for 'john'
   ```

### Test 2: Typo Tolerance

1. **Type with typo:**
   ```
   jhon  (missing 'h')
   ```

2. **Should still find "john":**
   ```
   ✅ Algolia found 3 users for 'jhon'
   ```

### Test 3: Substring Search

1. **Type partial name:**
   ```
   smit
   ```

2. **Should find "Smith":**
   ```
   ✅ Found: John Smith, Jane Smith, Bob Smitty
   ```

### Test 4: Firestore Fallback

1. **Turn off WiFi**

2. **Search:**
   ```
   john
   ```

3. **Should auto-fallback:**
   ```
   ⚠️ Algolia search failed, falling back to Firestore
   ✅ Found 3 users via Firestore
   ```

---

## 🎨 Current Features

### Discover People Section:
- ✅ "Let's Stay Connected" header with gradient
- ✅ Horizontal scrolling user cards
- ✅ Liquid glass design with blur effects
- ✅ Online status indicators
- ✅ Verification badges
- ✅ Follow/Unfollow buttons
- ✅ Skeleton loading states
- ✅ "Discover More" full-screen view

### Search Features:
- ✅ Real-time search as you type
- ✅ Debounced search (300ms delay)
- ✅ Category filters (All, People, Groups, Posts, Events)
- ✅ Sort options (Relevance, Recent, Popular)
- ✅ Recent searches with clear function
- ✅ Trending topics
- ✅ Empty states
- ✅ Loading states

### Backend:
- ✅ Algolia primary search
- ✅ Firestore fallback
- ✅ UserSearchService integration
- ✅ Real-time user suggestions
- ✅ Production-ready error handling

---

## 📊 Performance Expectations

### With Algolia Enabled:
- ⚡ **Search Speed:** < 50ms
- 🎯 **Typo Tolerance:** Up to 2 typos
- 🔍 **Results:** Instant as you type
- 📱 **User Experience:** Smooth, instant feedback

### With Firestore Fallback:
- 🐢 **Search Speed:** 200-500ms
- ❌ **Typo Tolerance:** None (exact match only)
- 🔍 **Results:** Delayed
- 📱 **User Experience:** Noticeable lag

---

## 🐛 Troubleshooting

### Issue: "Module 'AlgoliaSearchClient' not found"
**Solution:**
1. Verify package is added in Project Navigator
2. Clean Build Folder (⌘⇧K)
3. Rebuild (⌘B)
4. Restart Xcode

### Issue: "401 Unauthorized"
**Solution:**
1. Check API keys in `AlgoliaConfig.swift`
2. Verify keys are from Algolia Dashboard
3. Use Search-Only API Key (not Admin Key)

### Issue: "Index does not exist"
**Solution:**
1. Check Algolia Dashboard → Indices
2. Verify index names match:
   - `users` (lowercase)
   - `posts` (lowercase)
3. Wait for Firebase Extension to sync data

### Issue: No search results
**Solution:**
1. Check if indices have data (Algolia Dashboard)
2. Verify Firebase Extension is running
3. Check Console logs for errors
4. Try fallback search (should work with Firestore)

### Issue: Firestore fallback not working
**Solution:**
1. Check Firebase rules allow read access
2. Verify `usernameLowercase` field exists in Firestore
3. Check Console for specific Firestore errors

---

## 🚀 Production Checklist

Before going live:

- [ ] Algolia SDK package installed
- [ ] API keys configured in `AlgoliaConfig.swift`
- [ ] Code uncommented in `AlgoliaSearchService.swift`
- [ ] Indices created (`users` and `posts`)
- [ ] Firebase Extension installed and syncing
- [ ] Tested basic search
- [ ] Tested typo tolerance
- [ ] Tested Firestore fallback
- [ ] Verified search speed (< 100ms)
- [ ] Tested on real device
- [ ] Checked console logs (no errors)
- [ ] Verified UI responsiveness
- [ ] Tested with poor network connection

---

## 📝 Current Search Flow

```
User Types in Search Bar
    ↓
SearchView (UI Layer)
    ↓
SearchService.search(query, filter)
    ↓
Filter = .people?
    ↓
SearchService.searchPeople(query)
    ↓
AlgoliaSearchService.searchUsers(query)
    ↓
Try Algolia API
    ↓
Success? → Return AlgoliaUser[]
    ↓
Fail? → Firestore Fallback
    ↓
Convert to AppSearchResult[]
    ↓
Display in SearchView
```

---

## 🎯 Summary

### ✅ What's Working NOW:
1. **UI**: Discover People + Search fully implemented
2. **Fallback**: Firestore search working perfectly
3. **Flow**: Complete search chain ready

### ⚠️ To Enable Algolia (15 minutes):
1. Add Algolia package (5 min)
2. Configure API keys (5 min)
3. Uncomment code (2 min)
4. Test (3 min)

### 🚀 After Setup:
- ⚡ Instant, typo-tolerant search
- 🎯 Professional-grade user discovery
- 📱 Production-ready performance

---

## 💡 Next Steps

1. **Install Package:**
   ```
   File → Add Package Dependencies
   URL: https://github.com/algolia/algoliasearch-client-swift
   ```

2. **Get API Keys:**
   ```
   https://www.algolia.com/account/api-keys
   ```

3. **Update Config:**
   ```swift
   // AlgoliaConfig.swift
   static let applicationID = "YOUR_ACTUAL_APP_ID"
   static let searchAPIKey = "YOUR_ACTUAL_SEARCH_KEY"
   ```

4. **Uncomment Code:**
   ```swift
   // AlgoliaSearchService.swift
   import AlgoliaSearchClient  // ← Remove //
   // Uncomment all /* */ blocks
   ```

5. **Build & Test!** 🎉

---

**Need Help?** Check console logs - they'll tell you exactly what's working and what needs attention! 🔍

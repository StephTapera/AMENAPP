# Algolia Search - Troubleshooting Guide

## 🔍 Common Issues & Solutions

### Build & Compilation Issues

#### ❌ "No such module 'AlgoliaSearchClient'"

**Cause:** Package not installed or not properly linked

**Solutions:**
1. Clean build folder: **⌘ + Shift + K**
2. Delete derived data:
   ```
   ~/Library/Developer/Xcode/DerivedData
   ```
3. Restart Xcode
4. Re-add package:
   ```
   File → Add Package Dependencies
   https://github.com/algolia/algoliasearch-client-swift
   ```
5. Rebuild project: **⌘ + B**

#### ❌ "Type 'AlgoliaUserSuggestion' cannot conform to 'Identifiable'"

**Cause:** Struct definition issue

**Solution:** Ensure struct has `id` property:
```swift
struct AlgoliaUserSuggestion: Identifiable {
    let id: String  // ← Must be present
    // ...
}
```

#### ❌ "'async' call in a function that does not support concurrency"

**Cause:** Calling async function from non-async context

**Solution:** Wrap in Task:
```swift
// ❌ Wrong
await searchUsers(query: "john")

// ✅ Correct
Task {
    await searchUsers(query: "john")
}
```

---

### Runtime Errors

#### ❌ "API key is invalid"

**Causes & Solutions:**

1. **Using Admin API Key in client**
   - ✅ Solution: Use Search-Only API Key
   - Get it from: Algolia Dashboard → API Keys → Search-Only API Key

2. **Typo in credentials**
   ```swift
   // Double check these values
   let appID = ApplicationID(rawValue: "YOUR_APP_ID")
   let apiKey = APIKey(rawValue: "YOUR_SEARCH_KEY")
   ```

3. **API key restrictions**
   - Check Algolia Dashboard → API Keys → Restrictions
   - Ensure iOS bundle ID is allowed

#### ❌ Search returns 0 results (but should return results)

**Debugging Steps:**

1. **Check index has data**
   - Go to Algolia Dashboard → Browse
   - Select `users` or `posts` index
   - Verify records exist

2. **Check searchable attributes**
   - Dashboard → Configuration → Searchable attributes
   - Should include: `username`, `displayName`, `bio`

3. **Test in dashboard**
   - Dashboard → Search → Test search
   - Try same query you're using in app

4. **Check filters**
   ```swift
   // Remove filters temporarily to test
   let results = try await searchUsers(query: "john", filters: nil)
   ```

5. **Enable debug logging**
   ```swift
   #if DEBUG
   print("🔍 Searching for: \(query)")
   print("📦 Results: \(results.count)")
   print("📝 First result: \(results.first?.username ?? "none")")
   #endif
   ```

#### ❌ "Task was cancelled"

**Cause:** Debounce task cancelled by new input

**Expected Behavior:** This is normal and intentional!

**If unwanted:**
```swift
// In .onChange(of: searchText)
searchTask?.cancel()  // ← Remove this line
```

---

### Performance Issues

#### ⚠️ Search is slow (>500ms)

**Possible Causes:**

1. **Network latency**
   - Check internet connection
   - Try on different network
   - Use Algolia's status page: https://status.algolia.com

2. **Too many results**
   - Reduce limit:
   ```swift
   searchUsers(query: query, limit: 10)  // Instead of 20
   ```

3. **Complex queries**
   - Simplify filters
   - Use faceting instead of filters

4. **Not using CDN**
   - Algolia should auto-select nearest server
   - Check in Network Inspector (Xcode)

**Performance Checklist:**
- [ ] Debouncing enabled (400ms)
- [ ] Limit set to reasonable number (10-20)
- [ ] Only indexing necessary fields
- [ ] Using Search-Only API key (not Admin)

#### ⚠️ Autocomplete feels laggy

**Solutions:**

1. **Reduce limit**
   ```swift
   getUserSuggestions(query: query, limit: 3)  // Instead of 5
   ```

2. **Increase debounce delay**
   ```swift
   try await Task.sleep(nanoseconds: 600_000_000)  // 600ms instead of 400ms
   ```

3. **Add minimum character requirement**
   ```swift
   guard query.count >= 3 else { return [] }  // Wait for 3 chars
   ```

---

### Data Sync Issues

#### ❌ New users not appearing in search

**Cause:** Data not syncing to Algolia

**Debugging:**

1. **Check Cloud Functions are deployed**
   ```bash
   firebase functions:log --only indexUser
   ```

2. **Manually trigger indexing**
   ```swift
   // In admin/testing code only
   try await AlgoliaSearchService.shared.indexUser(user)
   ```

3. **Check Firestore triggers**
   - Firebase Console → Functions
   - Verify `indexUser` function exists
   - Check error logs

4. **Backfill data** (one-time)
   - See `ALGOLIA_SETUP_GUIDE.md` → Step 7

#### ❌ Deleted users still in search results

**Cause:** Index not updated on deletion

**Solution:** Ensure Cloud Function handles deletions:
```typescript
// In Cloud Functions
export const indexUser = functions.firestore
  .document('users/{userId}')
  .onWrite(async (change, context) => {
    // If deleted
    if (!change.after.exists) {
      await usersIndex.deleteObject(context.params.userId);
      return;
    }
    // ... rest of indexing logic
  });
```

---

### UI Issues

#### ❌ Suggestions dropdown doesn't show

**Debugging:**

1. **Check state**
   ```swift
   print("showSuggestions: \(showSuggestions)")
   print("suggestions.count: \(suggestions.count)")
   ```

2. **Verify animation**
   ```swift
   .transition(.move(edge: .top).combined(with: .opacity))
   ```

3. **Check z-index**
   - Ensure dropdown is in correct VStack order
   - Should be after search bar

4. **Test without animation**
   ```swift
   // Temporarily remove
   // .animation(...)
   ```

#### ❌ Search bar doesn't clear

**Check:**
```swift
if !searchText.isEmpty {
    Button(action: {
        searchTask?.cancel()
        searchText = ""  // ← This line
        suggestions = []
        showSuggestions = false
    })
}
```

#### ❌ Loading spinner stuck

**Causes:**
1. Network timeout
2. Uncaught error
3. Forgot to set `isLoading = false`

**Solution:** Always use `defer`:
```swift
func searchUsers() async {
    isLoading = true
    defer { isLoading = false }  // ← Always runs
    
    // ... search logic
}
```

---

### Firestore Fallback Issues

#### ❌ Fallback never triggers

**Check error handling:**
```swift
do {
    users = try await AlgoliaSearchService.shared.searchUsers(query: query)
} catch {
    // ✅ This should catch Algolia errors
    print("Algolia failed: \(error)")
    users = try await performFirestoreSearch(query: query)
}
```

#### ❌ "Not authenticated" error in fallback

**Cause:** User not signed in

**Solution:**
```swift
guard let currentUserId = Auth.auth().currentUser?.uid else {
    throw PeopleDiscoveryError.notAuthenticated
}
```

**Check in UI:**
```swift
.task {
    if Auth.auth().currentUser == nil {
        error = "Please sign in to search"
        return
    }
    await viewModel.loadUsers(filter: selectedFilter)
}
```

---

### Testing Issues

#### ❌ "No results" in production but works in dev

**Possible Causes:**

1. **Different Algolia environments**
   - Dev app ID vs Prod app ID
   - Use environment variables:
   ```swift
   #if DEBUG
   let appID = "DEV_APP_ID"
   #else
   let appID = "PROD_APP_ID"
   #endif
   ```

2. **Data not in production index**
   - Backfill production data
   - Check index name matches

3. **API key restrictions**
   - Production API key has different restrictions
   - Check allowed domains/IPs

---

### Edge Cases

#### ❌ Special characters in search break results

**Solution:** Sanitize input:
```swift
let sanitized = query
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .folding(options: .diacriticInsensitive, locale: .current)
```

#### ❌ Emoji in search causes issues

**Solution:** Algolia handles emoji by default
If issues persist:
```swift
let cleaned = query.unicodeScalars
    .filter { !$0.properties.isEmoji }
    .reduce("") { $0 + String($1) }
```

#### ❌ Very long search queries

**Solution:** Limit query length:
```swift
guard query.count <= 100 else {
    error = "Search query too long"
    return
}
```

---

## 🔧 Debug Mode

### Enable verbose logging:

```swift
// In AlgoliaSearchService.swift init()
#if DEBUG
self.client = SearchClient(
    appID: appID,
    apiKey: apiKey,
    requestOptions: RequestOptions(
        logLevel: .all  // ← Add this
    )
)
#endif
```

### Add network monitoring:

```swift
// In searchUsers()
#if DEBUG
let start = Date()
defer {
    let elapsed = Date().timeIntervalSince(start)
    print("⏱️ Search took: \(elapsed * 1000)ms")
}
#endif
```

---

## 📊 Performance Monitoring

### Track search metrics:

```swift
func searchUsers(query: String) async throws -> [AlgoliaUser] {
    let start = Date()
    
    do {
        let results = try await usersIndex.search(query: Query(query))
        
        #if DEBUG
        let duration = Date().timeIntervalSince(start)
        print("""
        📊 Search Metrics:
           Query: \(query)
           Results: \(results.hits.count)
           Duration: \(Int(duration * 1000))ms
           Processing: \(results.processingTimeMS ?? 0)ms
        """)
        #endif
        
        return results.hits.compactMap { AlgoliaUser(json: $0.object.value as? [String: Any] ?? [:]) }
    } catch {
        #if DEBUG
        print("❌ Search failed after \(Int(Date().timeIntervalSince(start) * 1000))ms")
        #endif
        throw error
    }
}
```

---

## 🆘 Still Stuck?

### 1. Check Logs

**Xcode Console:**
- Look for prints with ✅ (success) or ❌ (error)

**Firebase Functions:**
```bash
firebase functions:log
```

**Algolia Dashboard:**
- Go to Monitoring → Logs
- Filter by failed requests

### 2. Verify Configuration

Run this test in your app:
```swift
#if DEBUG
func testAlgoliaConfig() async {
    print("🧪 Testing Algolia Configuration...")
    
    do {
        let results = try await AlgoliaSearchService.shared.searchUsers(query: "test", limit: 1)
        print("✅ Algolia working! Found \(results.count) results")
    } catch {
        print("❌ Algolia failed: \(error)")
    }
}
#endif
```

### 3. Check Algolia Status

Visit: https://status.algolia.com

### 4. Review Documentation

- **Setup Guide**: `ALGOLIA_SETUP_GUIDE.md`
- **Quick Reference**: `ALGOLIA_QUICK_REFERENCE.md`
- **Architecture**: `ARCHITECTURE_DIAGRAM.md`

### 5. Contact Support

**Algolia Support:**
- Community: https://discourse.algolia.com
- Email: support@algolia.com
- Dashboard: Click "?" icon

**Include in support request:**
- App ID (not API key!)
- Index name
- Example query that fails
- Error message
- iOS version / device

---

## ✅ Prevention Checklist

Before deploying:
- [ ] All API keys correct (Search-Only in client)
- [ ] Indices exist and have data
- [ ] Cloud Functions deployed
- [ ] Searchable attributes configured
- [ ] Test on real device
- [ ] Test with poor network
- [ ] Test error states
- [ ] Monitor first 24 hours

---

**Last Updated:** February 5, 2026
**Need Help?** Check `ALGOLIA_SETUP_GUIDE.md` or create an issue

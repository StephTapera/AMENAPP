# Fix: Algolia Package Installation - Complete Guide

## 🔧 Solution: Add Algolia Manually Without Package Manager

Since the remote repository can't be accessed, let's use **CocoaPods** or install it manually.

---

## ✅ Option 1: Install via CocoaPods (Recommended)

### Step 1: Install CocoaPods (if not installed)

Open Terminal and run:
```bash
sudo gem install cocoapods
```

### Step 2: Navigate to Your Project

```bash
cd /path/to/your/AMENAPP
```

### Step 3: Create Podfile

```bash
pod init
```

### Step 4: Edit Podfile

Open the `Podfile` that was created and add:

```ruby
platform :ios, '15.0'

target 'AMENAPP' do
  use_frameworks!

  # Firebase (you probably already have these)
  pod 'Firebase/Core'
  pod 'Firebase/Auth'
  pod 'Firebase/Firestore'
  
  # ✅ ADD ALGOLIA
  pod 'AlgoliaSearchClient', '~> 8.0'
  
end
```

### Step 5: Install Pods

```bash
pod install
```

### Step 6: Open .xcworkspace File

**IMPORTANT:** From now on, always open `AMENAPP.xcworkspace` NOT `AMENAPP.xcodeproj`

```bash
open AMENAPP.xcworkspace
```

### Step 7: Build Project

In Xcode: **Product** → **Build** (Cmd+B)

The import error should be gone! ✅

---

## ✅ Option 2: Manual Installation (If CocoaPods Doesn't Work)

### Step 1: Download Algolia Source

1. Go to: https://github.com/algolia/algoliasearch-client-swift
2. Click **Code** → **Download ZIP**
3. Extract the ZIP file

### Step 2: Add to Xcode

1. In Xcode, right-click your project in Navigator
2. Select **"Add Files to AMENAPP..."**
3. Navigate to the extracted folder
4. Select the `Sources` folder
5. Check **"Copy items if needed"**
6. Click **Add**

### Step 3: Build

**Product** → **Build** (Cmd+B)

---

## ✅ Option 3: Use Different Package URL

Sometimes the GitHub URL is blocked. Try these alternatives:

### Try HTTPS URL:
```
https://github.com/algolia/algoliasearch-client-swift.git
```

### Try SSH URL (if you have SSH key):
```
git@github.com:algolia/algoliasearch-client-swift.git
```

### Try with specific version:
```
https://github.com/algolia/algoliasearch-client-swift
Version: Exactly 8.20.0
```

---

## ✅ Option 4: Fix Network/Firewall Issues

### Check if GitHub is accessible:

Open Terminal:
```bash
ping github.com
```

If it times out, you have network issues.

### Try with VPN:
If you're in a restricted network, try:
1. Connect to a VPN
2. Try adding package again in Xcode

### Check Xcode Network Settings:
1. Xcode → **Preferences** → **Accounts**
2. Make sure you're signed in with Apple ID
3. Try again

---

## ✅ Option 5: Use Pre-Built Binary (Fastest)

### Download Pre-Built Framework:

1. Go to: https://github.com/algolia/algoliasearch-client-swift/releases
2. Download the latest `.xcframework` file
3. Drag it into your Xcode project
4. In target settings → **General** → **Frameworks, Libraries, and Embedded Content**
5. Make sure it's set to **"Embed & Sign"**

---

## 🎯 My Recommended Solution: CocoaPods

**Why:** Most reliable, works offline after first install, easy to update.

### Quick Install (Copy/Paste):

```bash
# 1. Install CocoaPods
sudo gem install cocoapods

# 2. Navigate to project
cd /path/to/your/AMENAPP

# 3. Create Podfile
pod init

# 4. Add Algolia to Podfile (manual edit needed)
# Open Podfile and add: pod 'AlgoliaSearchClient', '~> 8.0'

# 5. Install
pod install

# 6. Open workspace
open AMENAPP.xcworkspace
```

---

## 🧪 After Installation: Test It

Add this to any Swift file:

```swift
import AlgoliaSearchClient

// Test in a function
func testAlgolia() {
    let client = SearchClient(appID: "test", apiKey: "test")
    print("✅ Algolia imported successfully!")
}
```

If it compiles, you're good! ✅

---

## 🆘 Still Having Issues?

### Alternative: Use Firestore Search Only (Skip Algolia)

If you absolutely can't get Algolia working, your app already has **Firestore fallback**!

#### In `SearchService.swift`:

The code already falls back to Firestore:
```swift
func searchPeople(query: String) async throws -> [AppSearchResult] {
    do {
        // Try Algolia first
        let algoliaUsers = try await AlgoliaSearchService.shared.searchUsers(query: query)
        return algoliaUsers.map { $0.toSearchResult() }
    } catch {
        // ✅ Automatically falls back to Firestore
        return try await searchPeopleFirestore(query: query)
    }
}
```

#### To Use Firestore Only (Temporary):

Comment out Algolia code in `AlgoliaSearchService.swift`:

```swift
// Temporarily disable Algolia
func searchUsers(query: String) async throws -> [AlgoliaUser] {
    throw NSError(domain: "Algolia", code: 1, userInfo: [NSLocalizedDescriptionKey: "Algolia disabled"])
}
```

Your search will automatically use Firestore! It won't have typo-tolerance, but it will work.

---

## 📋 Troubleshooting Checklist

- [ ] Check internet connection
- [ ] Try with VPN if behind firewall
- [ ] Try CocoaPods instead of SPM
- [ ] Try downloading .xcframework manually
- [ ] Try different GitHub URL format
- [ ] Check Xcode is signed in with Apple ID
- [ ] Restart Xcode
- [ ] Restart Mac (sometimes helps with Xcode issues)

---

## 🎉 Expected Result After Fix

### Console logs:
```
✅ Algolia client initialized
🔍 Searching people with Algolia: 'john'
✅ Found 12 people via Algolia
```

### Search features:
- ✅ Typo-tolerant search works
- ✅ Substring search works
- ✅ Multi-word search works
- ✅ Instant results

---

## 💡 Best Solution For You

Based on the "Remote repository could not be accessed" error, I recommend:

### Try This Order:

1. **First:** Try CocoaPods (most reliable)
   ```bash
   pod 'AlgoliaSearchClient', '~> 8.0'
   ```

2. **If that fails:** Download .xcframework manually
   - Go to GitHub releases
   - Download pre-built binary
   - Drag into Xcode

3. **If all fails:** Use Firestore-only search (already implemented as fallback)

---

## 🔑 Key Files You Need Working

For search to work, you need:
- ✅ `SearchService.swift` (already has Firestore fallback)
- ✅ `AlgoliaConfig.swift` (has your API keys)
- ⚠️ `AlgoliaSearchService.swift` (needs Algolia SDK)

**Without Algolia SDK:**
- Search still works via Firestore ✅
- No typo-tolerance ❌
- Must spell exactly correct ❌

**With Algolia SDK:**
- Search works even better ✅
- Typo-tolerance ✅
- Professional search experience ✅

---

## 🎯 Quick Decision Guide

**Need search ASAP?**
→ Skip Algolia, use Firestore fallback (already works)

**Want professional search?**
→ Install via CocoaPods (20 minutes)

**Can't access GitHub at all?**
→ Download .xcframework manually (10 minutes)

**Want to try later?**
→ App works with Firestore search now, add Algolia later!

---

Let me know which option you want to try! 🚀

# Algolia Import Error - Fix Instructions

## ❌ Error: "Unable to find module dependency: 'AlgoliaSearchClient'"

This means the Algolia package wasn't properly added to your Xcode project.

---

## 🔧 Fix: Add Algolia Package Properly

### Step 1: Clean Build Folder
1. In Xcode: **Product** → **Clean Build Folder** (Shift+Cmd+K)
2. Wait for it to complete

---

### Step 2: Add Package Dependency (Again)
1. **File** → **Add Package Dependencies...**
2. Paste URL: `https://github.com/algolia/algoliasearch-client-swift`
3. Dependency Rule: **"Up to Next Major Version"** starting from `8.0.0`
4. Click **"Add Package"**
5. **Select Target:** Make sure `AlgoliaSearchClient` is checked
6. Click **"Add Package"**

---

### Step 3: Verify Package Was Added

#### Check Package.swift or Project Settings:
1. In Xcode Navigator, expand your project
2. Look for **"Package Dependencies"** section
3. Should see: `algoliasearch-client-swift`

#### Or check manually:
1. Click on your project name in Navigator (top)
2. Select your app target
3. Go to **"Frameworks, Libraries, and Embedded Content"**
4. Look for `AlgoliaSearchClient`

---

### Step 4: Restart Xcode (If Needed)
1. Quit Xcode completely
2. Reopen your project
3. Let it index and resolve packages

---

### Step 5: Build Again
1. **Product** → **Build** (Cmd+B)
2. Error should be gone! ✅

---

## 🔍 Alternative: Check if Package Resolved

### In Terminal (from your project directory):
```bash
# Check Package.resolved file
cat AMENApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# Should show AlgoliaSearchClient
```

---

## 🆘 Still Not Working?

### Try Manual Package Addition:

1. **Create Package.swift** (if you don't have one)

2. **Add this to dependencies:**
```swift
dependencies: [
    .package(url: "https://github.com/algolia/algoliasearch-client-swift", from: "8.0.0")
]
```

3. **In your target dependencies:**
```swift
.target(
    name: "AMENAPP",
    dependencies: [
        .product(name: "AlgoliaSearchClient", package: "algoliasearch-client-swift")
    ]
)
```

---

## 📦 Verify Package is Downloaded

### Check Derived Data:
1. Xcode → **Preferences** → **Locations**
2. Click arrow next to **Derived Data** path
3. Navigate to: `SourcePackages/checkouts`
4. Should see: `algoliasearch-client-swift` folder

If folder is missing, the package didn't download properly.

---

## 🎯 Quick Checklist

- [ ] Clean build folder (Shift+Cmd+K)
- [ ] Add package via File → Add Package Dependencies
- [ ] Verify package appears in Project Navigator
- [ ] Restart Xcode
- [ ] Build project (Cmd+B)
- [ ] Error gone! ✅

---

## 🔄 If All Else Fails: Nuclear Option

1. **Remove package:**
   - Right-click on package in Navigator
   - Select "Remove Package"

2. **Delete Derived Data:**
   - Xcode → Preferences → Locations
   - Click arrow next to Derived Data
   - Delete the entire folder for your project

3. **Quit Xcode**

4. **Reopen project**

5. **Add package again** (Step 2 above)

6. **Build**

---

## ✅ After Fix: Test Imports

Try building with these imports:

```swift
import AlgoliaSearchClient

// Test that it works
let client = SearchClient(appID: "test", apiKey: "test")
```

If that compiles, you're good to go! 🚀

---

## 🎉 Once Fixed

Your search will work with Algolia! You'll see in console:
```
🔍 Algolia searching users: 'john'
✅ Algolia client initialized
✅ Found 12 people via Algolia
```

---

**Note:** The Algolia package is large (~30MB). Download may take a minute on first add.

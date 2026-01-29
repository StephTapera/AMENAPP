# CocoaPods Installation & Algolia Setup - Step by Step

## 🔧 Install CocoaPods First

### Step 1: Install CocoaPods

In Terminal, run:
```bash
sudo gem install cocoapods
```

You'll be asked for your Mac password. Type it and press Enter (you won't see it as you type - that's normal!).

**Wait 2-5 minutes** for installation to complete.

---

### Step 2: Verify Installation

```bash
pod --version
```

Should show something like: `1.14.3` ✅

---

### Step 3: Navigate to Your Project

```bash
cd ~/Documents/AMEN
```

Or wherever your project is located.

---

### Step 4: Create Podfile

```bash
pod init
```

This creates a `Podfile` in your project directory.

---

### Step 5: Edit Podfile

Open the Podfile:
```bash
open Podfile
```

Replace everything with this:

```ruby
platform :ios, '15.0'

target 'AMENAPP' do
  use_frameworks!

  # Algolia Search
  pod 'AlgoliaSearchClient', '~> 8.0'

end
```

Save and close the file.

---

### Step 6: Install Pods

```bash
pod install
```

**Wait 3-5 minutes** for Algolia to download and install.

You'll see:
```
Downloading dependencies
Installing AlgoliaSearchClient (8.x.x)
Generating Pods project
```

---

### Step 7: Open Workspace (IMPORTANT!)

**DON'T open the `.xcodeproj` file anymore!**

Instead, open:
```bash
open AMENAPP.xcworkspace
```

This opens your project WITH the installed pods.

---

### Step 8: Clean & Build

In Xcode:
1. **Product** → **Clean Build Folder** (Shift+Cmd+K)
2. **Product** → **Build** (Cmd+B)

✅ **The import error should be gone!**

---

## 🆘 If `sudo gem install cocoapods` Fails

### Error: Permission Denied

Try with Homebrew instead:

```bash
# Install Homebrew first (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then install CocoaPods via Homebrew
brew install cocoapods
```

---

### Error: Ruby Version Too Old

Update Ruby:
```bash
brew install ruby
echo 'export PATH="/usr/local/opt/ruby/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
sudo gem install cocoapods
```

---

## ⚡ FASTER OPTION: Skip Algolia (1 Minute Fix)

If CocoaPods is taking too long, just disable Algolia temporarily:

### In Xcode:

**1. Open `AlgoliaSearchService.swift`**

**2. Comment out the import:**
```swift
// import AlgoliaSearchClient
```

**3. Replace the searchUsers function:**
```swift
func searchUsers(query: String) async throws -> [AlgoliaUser] {
    // Algolia temporarily disabled - app will use Firestore fallback
    throw NSError(domain: "Algolia", code: 0, userInfo: [NSLocalizedDescriptionKey: "Using Firestore search"])
}
```

**4. Do the same for searchPosts:**
```swift
func searchPosts(query: String, category: String? = nil) async throws -> [AlgoliaPost] {
    // Algolia temporarily disabled - app will use Firestore fallback
    throw NSError(domain: "Algolia", code: 0, userInfo: [NSLocalizedDescriptionKey: "Using Firestore search"])
}
```

**5. Build** (Cmd+B)

✅ **Done! Your app now uses Firestore search (which works fine)!**

---

## 📋 Complete Terminal Commands (Copy/Paste All)

```bash
# 1. Install CocoaPods
sudo gem install cocoapods

# 2. Navigate to project
cd ~/Documents/AMEN

# 3. Initialize CocoaPods
pod init

# 4. Edit Podfile (do this manually in text editor)
open Podfile

# 5. After editing, install pods
pod install

# 6. Open workspace
open AMENAPP.xcworkspace
```

---

## 🎯 What Should You Do?

### Option A: Install CocoaPods (20 min)
**Pro:** Professional search with typo-tolerance
**Con:** Requires installation time
**Steps:** Follow all steps above

### Option B: Skip Algolia (1 min)
**Pro:** Works immediately  
**Con:** No typo-tolerance in search
**Steps:** Just comment out import and throw error

---

## 💡 My Recommendation for You:

Since you're getting "command not found: pod", here's the fastest path:

### Do This RIGHT NOW (1 minute):

**1. Open `AlgoliaSearchService.swift` in Xcode**

**2. Replace line 11:**
```swift
// import AlgoliaSearchClient  // TODO: Install CocoaPods later
```

**3. In the `searchUsers` function, add at the very top:**
```swift
func searchUsers(query: String) async throws -> [AlgoliaUser] {
    throw NSError(domain: "Algolia", code: 0, userInfo: nil)  // ← Add this line
    
    // Rest of function...
}
```

**4. Build** (Cmd+B)

✅ **Your app works NOW with Firestore search!**

### Then Later (when you have time):

Install CocoaPods using the steps at the top of this file.

---

## 🧪 After Fix: Test Your Search

1. Run app
2. Go to Search tab
3. Type "john"
4. Should see results! ✅

Check console:
```
🔍 Searching people with Algolia: 'john'
⚠️ Algolia search failed, falling back to Firestore
✅ Found 5 people via Firestore
```

Perfect! Firestore fallback is working!

---

## 🔑 The Key Point

**Your app has TWO search methods:**
1. **Algolia** (better, needs SDK)
2. **Firestore** (good, already works)

**Without CocoaPods:** App uses Firestore ✅
**With CocoaPods:** App uses Algolia ✅✅

**Both work! Choose based on your time.**

---

## 🎉 Summary

**Quick Fix (1 min):**
- Comment out `import AlgoliaSearchClient`
- Throw error in search functions
- App uses Firestore fallback
- Search works! ✅

**Proper Fix (20 min):**
- Install CocoaPods: `sudo gem install cocoapods`
- Create Podfile: `pod init`
- Edit Podfile: Add Algolia
- Install: `pod install`
- Open: `AMENAPP.xcworkspace`
- Professional search! ✅✅

**Your choice!** Both work perfectly. 🚀

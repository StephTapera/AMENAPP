# Quick Code Changes for TestFlight

## 🚀 Make These Changes Before Uploading

### 1. Remove DEBUG Mock Responses

**File:** `BereanAIAssistantView.swift`

**Find this code** (around line 1255):

```swift
} catch {
    // ✅ Don't show error if cancelled
    guard !Task.isCancelled else { return }
    
    print("❌ Unexpected error during streaming: \(error.localizedDescription)")
    await MainActor.run {
        onError(error)
    }
    
    // Fall back to mock response only in development
    #if DEBUG
    print("🔄 Using mock fallback response (DEBUG mode only)")
    let fallbackMessage = generateMockResponse(for: query)
    await MainActor.run {
        onComplete(fallbackMessage)
    }
    #endif
}
```

**Replace with:**

```swift
} catch {
    // ✅ Don't show error if cancelled
    guard !Task.isCancelled else { return }
    
    print("❌ Unexpected error during streaming: \(error.localizedDescription)")
    await MainActor.run {
        onError(error)
    }
    
    // ✅ REMOVED: Mock responses for production
    // Error will be shown to user via error banner
}
```

**Do the same for the other catch block** (around line 1235):

```swift
} catch let error as GenkitError {
    // ✅ Don't show error if cancelled
    guard !Task.isCancelled else { return }
    
    print("❌ Genkit error: \(error.localizedDescription)")
    await MainActor.run {
        onError(error)
    }
    
    // ✅ REMOVED: Mock fallback for production
}
```

---

### 2. Enable Firebase Offline Persistence

**File:** `AMENAPPApp.swift` (or your main app file)

**Find your app initialization:**

```swift
@main
struct AMENAPPApp: App {
    
    init() {
        // Configure Firebase
        FirebaseApp.configure()
        
        // ✅ ADD THESE LINES:
        
        // Enable offline persistence
        Database.database().isPersistenceEnabled = true
        
        // Set cache size (50MB)
        Database.database().persistenceCacheSizeBytes = 50 * 1024 * 1024
        
        print("✅ Firebase configured with offline persistence")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

### 3. Verify Production Endpoint

**File:** `Info.plist`

Make sure this is set correctly:

```xml
<key>GENKIT_ENDPOINT</key>
<string>https://genkit-amen-78278013543.us-central1.run.app</string>
```

**If this key doesn't exist,** add it to your Info.plist file:

1. Right-click `Info.plist` in Xcode
2. Open As → Source Code
3. Add the key inside the `<dict>` tag

---

### 4. Update BereanDataManager Network Checks

**File:** `BereanDataManager.swift`

These changes were already made! Just verify they're in place:

```swift
// In shareToFeed function
func shareToFeed(...) async throws {
    // Check network first
    guard NetworkMonitor.shared.isConnected else {
        print("❌ Cannot share to feed - no network connection")
        throw BereanError.networkUnavailable
    }
    // ... rest of function
}

// In reportIssue function  
func reportIssue(...) async throws {
    // Check network connectivity first
    guard NetworkMonitor.shared.isConnected else {
        print("❌ Cannot report issue - no network connection")
        throw BereanError.networkUnavailable
    }
    // ... rest of function
}
```

---

### 5. Update PostCard Save Toggle

**File:** `PostCard.swift`

This change was already made! Just verify it's in place:

```swift
private func toggleSave() {
    guard let post = post else { return }
    
    // ✅ Check network first
    guard NetworkMonitor.shared.isConnected else {
        print("📱 Offline - cannot save/unsave posts")
        errorMessage = "You're offline. Please check your connection and try again."
        showErrorAlert = true
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        return
    }
    
    // ... rest of function
}
```

---

### 6. Add Loading State Improvements (Optional but Recommended)

**File:** `BereanAIAssistantView.swift`

Add timeout indicator for slow responses:

```swift
// Add to BereanAIAssistantView struct
@State private var responseTimeoutWarning = false
@State private var responseTimer: Task<Void, Never>?

// In sendMessage, after starting the request:
// Start timeout warning timer (15 seconds)
responseTimer?.cancel()
responseTimer = Task {
    try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
    
    if !Task.isCancelled && isGenerating {
        await MainActor.run {
            responseTimeoutWarning = true
        }
    }
}

// In onComplete and onError callbacks:
// Cancel timer
responseTimer?.cancel()
responseTimeoutWarning = false

// Add to the UI (in the thinking indicator area):
if responseTimeoutWarning {
    Text("This is taking longer than usual...")
        .font(.custom("OpenSans-Regular", size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.top, 8)
}
```

---

## 🧪 Test These Scenarios Before Uploading

### Scenario 1: Basic AI Query
```
1. Open Berean AI
2. Type: "What does John 3:16 mean?"
3. Verify: Response appears and makes sense
4. Verify: No errors in console
```

### Scenario 2: Offline Mode
```
1. Enable Airplane Mode
2. Open Berean AI
3. Try to send a message
4. Verify: Shows "You're offline" error banner
5. Disable Airplane Mode
6. Verify: Can send messages again
```

### Scenario 3: Stop Generation
```
1. Send a long query
2. Tap stop button immediately
3. Verify: Generation stops
4. Verify: No crash
5. Send another message
6. Verify: Works normally
```

### Scenario 4: Share to Feed
```
1. Get an AI response
2. Tap share button
3. Add personal note
4. Share to feed
5. Verify: Appears in OpenTable feed
```

### Scenario 5: Network Recovery
```
1. Start sending a message
2. Disable WiFi mid-request
3. Verify: Shows error
4. Enable WiFi
5. Tap retry
6. Verify: Works
```

---

## 📋 Pre-Upload Checklist

Copy this and check off each item:

```
Infrastructure:
- [ ] Genkit server is deployed to Cloud Run
- [ ] Test endpoint with curl (see TESTFLIGHT_DEPLOYMENT_GUIDE.md)
- [ ] Endpoint URL is in Info.plist
- [ ] API key configured (optional but recommended)

Code Changes:
- [ ] Removed #if DEBUG mock fallbacks from BereanAIAssistantView
- [ ] Enabled Firebase offline persistence in app initialization
- [ ] Network checks in place for all Firebase operations
- [ ] Error messages are user-friendly (no technical jargon)

Testing:
- [ ] Tested on real device (not simulator)
- [ ] Tested with WiFi
- [ ] Tested with cellular
- [ ] Tested offline mode
- [ ] Tested error recovery
- [ ] Tested all AI features
- [ ] No crashes in basic flows

Xcode Configuration:
- [ ] Build configuration set to Release
- [ ] Version number updated
- [ ] Build number incremented
- [ ] Code signing configured
- [ ] Info.plist is correct

Documentation:
- [ ] What's New notes prepared
- [ ] Troubleshooting guide ready
- [ ] Known issues documented
```

---

## 🚀 Upload Process

Once all items are checked:

### Step 1: Clean Build
```
Xcode → Product → Clean Build Folder
(Shift + Cmd + K)
```

### Step 2: Archive
```
Xcode → Product → Archive
Wait for completion (2-5 minutes)
```

### Step 3: Validate
```
Organizer → Select Archive → Validate App
Fix any warnings/errors
```

### Step 4: Upload
```
Organizer → Select Archive → Distribute App
Choose: App Store Connect
Upload to TestFlight
Wait for processing (10-30 minutes)
```

### Step 5: Configure in App Store Connect
```
1. Go to appstoreconnect.apple.com
2. Select your app → TestFlight
3. Select the new build
4. Complete export compliance
5. Fill "What to Test" field
6. Save and submit for review
```

---

## 🎉 You're Ready!

Once these changes are made and tested, you can confidently upload to TestFlight.

**Questions?** Check `TESTFLIGHT_DEPLOYMENT_GUIDE.md` for detailed instructions.

**Issues?** See troubleshooting section in the deployment guide.

**Good luck! 🚀**

# Quick Fix Guide for Current Errors

## Errors You're Seeing

1. ✅ **App Check Warning** - Safe to ignore on simulator
2. ❌ **Firebase Offline Errors** - Need to fix
3. ❌ **Empty AI Response** - Need to fix  
4. ⚠️ **Font Weight Warning** - Minor issue

---

## Fix 1: App Check Warning (IGNORE THIS - IT'S NORMAL)

```
Error getting App Check token; using placeholder token instead.
Error: The attestation provider DeviceCheckProvider is not supported on current platform and OS version.
```

**This is expected behavior on simulator.** DeviceCheck only works on real devices. Firebase automatically uses a placeholder token, so everything still works. You can safely ignore this warning.

### Optional: Suppress the Warning

If you want to suppress it, add this to your Firebase configuration:

```swift
// In your app initialization (AppDelegate or main App file)
#if targetEnvironment(simulator)
// Don't configure App Check on simulator
#else
AppCheck.appCheck().activate(
    with: AppCheckProviderFactory()
)
#endif
```

---

## Fix 2: Firebase Offline Errors (CRITICAL)

### Problem

```
❌ ProfileView: Error loading profile - Unable to get latest value for query FQuerySpec 
(path: /user_posts/91JpG4qFreVaSWrhXgwFxHlJk942, params: {})
```

This happens when:
- App tries to query Firebase while offline
- No cached data available
- No active real-time listener

### Solution A: Enable Firebase Offline Persistence (RECOMMENDED)

**Add this to your app's entry point:**

```swift
// AMENAPPApp.swift (or AppDelegate.swift)
import SwiftUI
import FirebaseCore
import FirebaseDatabase

@main
struct AMENAPPApp: App {
    
    init() {
        // Configure Firebase
        FirebaseApp.configure()
        
        // ✅ CRITICAL: Enable offline persistence
        Database.database().isPersistenceEnabled = true
        
        // ✅ Set cache size (optional, default is 10MB)
        Database.database().persistenceCacheSizeBytes = 50 * 1024 * 1024 // 50MB
        
        print("✅ Firebase offline persistence enabled")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Solution B: Fix ProfileView Loading

Find where ProfileView loads user posts and add network checks:

```swift
// In ProfileView.swift (or similar)
func loadUserPosts() async {
    guard let userId = userId else { return }
    
    // ✅ Check network first
    guard NetworkMonitor.shared.isConnected else {
        print("📱 Offline - cannot load user posts")
        // Show cached posts or offline message
        return
    }
    
    do {
        let posts = try await fetchUserPosts(userId: userId)
        // Update UI
    } catch {
        print("❌ Failed to load posts: \(error)")
        // Show error to user
    }
}
```

### Solution C: Add Global Error Handler

Create a centralized error handler for Firebase errors:

```swift
// FirebaseErrorHandler.swift
import Foundation
import FirebaseDatabase

class FirebaseErrorHandler {
    static let shared = FirebaseErrorHandler()
    
    func handle(_ error: Error, context: String) {
        print("❌ Firebase Error [\(context)]: \(error.localizedDescription)")
        
        // Check if it's a network/offline error
        if let dbError = error as NSError?, 
           dbError.domain == "com.firebase.core",
           dbError.code == 1 {
            print("📱 Firebase offline error - check network connection")
            
            // Notify UI to show offline state
            NotificationCenter.default.post(
                name: Notification.Name("FirebaseOfflineError"),
                object: nil,
                userInfo: ["context": context]
            )
        }
    }
}
```

---

## Fix 3: Empty AI Response (CRITICAL)

### Problem

```
❌ Received empty response from AI
❌ Error generating response: AI returned empty response
🔄 Using mock fallback response (DEBUG mode only)
```

### Root Cause

Your BereanGenkitService is trying to connect to:
```
https://genkit-amen-78278013543.us-central1.run.app
```

The server might be:
1. Not deployed yet
2. Returning empty responses
3. Timing out
4. Not configured properly

### Solution A: Check Genkit Server Status

**Test the endpoint manually:**

```bash
# Test if server is running
curl https://genkit-amen-78278013543.us-central1.run.app/health

# Test the bibleChat flow
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{"message":"What does John 3:16 mean?","history":[]}'
```

If these return errors, the server needs to be deployed.

### Solution B: Use Local Development Server

For development, run Genkit locally:

```bash
# In your genkit-flows directory
npm run dev

# Or
genkit start -- npm run dev
```

Then update your Info.plist:

```xml
<key>GENKIT_ENDPOINT</key>
<string>http://localhost:3400</string>
```

### Solution C: Deploy Genkit to Cloud Run

If you haven't deployed yet:

```bash
# Navigate to your genkit-flows directory
cd genkit-flows

# Deploy to Cloud Run
npm run deploy

# Or manually
gcloud run deploy genkit-amen \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

### Solution D: Add Better Error Handling

Update `BereanGenkitService.swift` to provide more detailed errors:

```swift
// In callGenkitFlow function
guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    print("❌ Failed to parse JSON response")
    if let responseText = String(data: data, encoding: .utf8) {
        print("   Raw response: \(responseText)")
    }
    
    // ✅ Throw a more helpful error
    throw NSError(
        domain: "BereanGenkitService",
        code: -2,
        userInfo: [
            NSLocalizedDescriptionKey: "Server returned invalid response. Check if Genkit server is running.",
            NSLocalizedRecoverySuggestionErrorKey: "Try restarting the Genkit development server or check Cloud Run deployment."
        ]
    )
}

// ✅ Check if response is empty
if json.isEmpty || json["response"] == nil {
    print("⚠️ Server returned empty response")
    throw NSError(
        domain: "BereanGenkitService",
        code: -3,
        userInfo: [
            NSLocalizedDescriptionKey: "Server returned empty response",
            NSLocalizedRecoverySuggestionErrorKey: "The AI server processed the request but returned no content. This might indicate a server configuration issue."
        ]
    )
}
```

### Solution E: Enable Mock Mode for Development

Add a flag to use mock responses when server is unavailable:

```swift
// In BereanGenkitService.swift

// Add this property
var useMockData: Bool {
    #if DEBUG
    // In debug builds, use mock data if server is unreachable
    return !isServerReachable
    #else
    // In production, never use mock data
    return false
    #endif
}

// Add server reachability check
private var isServerReachable: Bool = true

// Update sendMessage to use mocks when needed
func sendMessage(_ message: String, conversationHistory: [BereanMessage] = []) -> AsyncThrowingStream<String, Error> {
    // ✅ Use mock data if in debug mode and server is unreachable
    if useMockData {
        return mockResponse(for: message)
    }
    
    // ... rest of normal implementation
}
```

---

## Fix 4: Font Weight Warning (MINOR)

### Problem

```
Unable to update Font Descriptor's weight to Weight(value: 0.0)
```

### Cause

You're using `.fontWeight(.light)` or similar with a custom font that doesn't support dynamic weight.

### Solution

Use explicit fonts instead of modifiers:

```swift
// ❌ Don't do this
Text("Berean")
    .font(.custom("Georgia", size: 22))
    .fontWeight(.light)  // This causes the warning

// ✅ Do this instead
Text("Berean")
    .font(.custom("Georgia-Light", size: 22))

// Or use system fonts with weights
Text("Berean")
    .font(.system(size: 22, weight: .light))
```

---

## Quick Testing Checklist

### 1. Test Offline Mode

```swift
// Enable airplane mode and check:
- [ ] Posts load from cache
- [ ] No error dialogs appear
- [ ] Offline banner shows
- [ ] Save/unsave actions show offline message
```

### 2. Test Berean AI

```swift
// Check if Genkit server is running:
curl https://genkit-amen-78278013543.us-central1.run.app/health

// Test in app:
- [ ] Send a message to Berean AI
- [ ] Verify response is not empty
- [ ] Check logs for errors
- [ ] Verify mock fallback works in debug
```

### 3. Test Firebase

```swift
// In AMENAPPApp.swift init():
- [ ] Added Firebase.configure()
- [ ] Added Database.database().isPersistenceEnabled = true
- [ ] Relaunch app and check logs for "Firebase offline persistence enabled"
```

---

## Priority Order

1. **CRITICAL - Fix Firebase Offline** → Enable persistence (5 minutes)
2. **CRITICAL - Fix Empty AI** → Check/deploy Genkit server (30 minutes)
3. **MINOR - Fix Font Warning** → Update font declarations (5 minutes)
4. **IGNORE - App Check Warning** → Expected on simulator (0 minutes)

---

## Need More Help?

Check these files in your project:
- `FIREBASE_OFFLINE_FIX_GUIDE.md` - Comprehensive Firebase offline guide
- `FirebaseOfflineHelper.swift` - Helper utility for offline queries
- `GENKIT_HOSTING_PRODUCTION_GUIDE.md` - Genkit deployment guide
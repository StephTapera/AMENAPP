# FCM Token Storage - Quick Setup Guide

## ✅ What You Already Have

Your app is **90% ready** for push notifications! You have:

- ✅ `PushNotificationManager.swift` with FCM token handling
- ✅ `AppDelegate+Messaging.swift` with messaging setup
- ✅ `CompositeNotificationDelegate` for notification handling
- ✅ Cloud Functions for sending notifications
- ✅ Firestore security rules allowing token updates

## 🎯 What You Need to Add (3 Simple Steps)

### Step 1: Add FCM Setup After Login

Find your **login success handler** (probably in `SignInView.swift` or similar) and add:

```swift
// After successful login:
let granted = await PushNotificationManager.shared.requestNotificationPermissions()
if granted {
    PushNotificationManager.shared.setupFCMToken()
    await PushNotificationManager.shared.scheduleDailyReminders() // Optional
}
```

**Example:**

```swift
// In your SignInView.swift or wherever you handle login
func handleLogin() async {
    do {
        // Your existing login code
        try await Auth.auth().signIn(withEmail: email, password: password)
        
        // ✅ ADD THIS:
        let granted = await PushNotificationManager.shared.requestNotificationPermissions()
        if granted {
            PushNotificationManager.shared.setupFCMToken()
        }
        
        // Continue with your navigation
    } catch {
        // Handle error
    }
}
```

---

### Step 2: Add FCM Setup on App Launch (For Already Logged-In Users)

In your `ContentView.swift` (or root view), add to `.onAppear`:

```swift
.onAppear {
    // Your existing code...
    
    // ✅ ADD THIS:
    if Auth.auth().currentUser != nil {
        Task {
            let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
            if hasPermission {
                PushNotificationManager.shared.setupFCMToken()
            }
        }
    }
}
```

---

### Step 3: Remove Token on Logout

In your **logout function**, add:

```swift
func logout() async {
    // ✅ ADD THIS FIRST:
    await PushNotificationManager.shared.removeFCMTokenFromFirestore()
    PushNotificationManager.shared.clearBadge()
    
    // Then your existing sign out code:
    try? Auth.auth().signOut()
}
```

---

## 🧪 How to Test

### 1. Check Console Logs

Run your app and look for these messages:

```
✅ Notification permission granted
🔑 FCM Token: [long token string]
✅ FCM token saved to Firestore for user: [userId]
```

### 2. Check Firestore

1. Open Firebase Console → Firestore Database
2. Navigate to `users/{your-userId}`
3. Check for these fields:
   - `fcmToken`: (string) Your device token
   - `fcmTokenUpdatedAt`: (timestamp) When it was updated
   - `platform`: (string) "ios"

### 3. Test a Real Notification

#### Option A: Test from Firebase Console
1. Firebase Console → Cloud Messaging
2. Click "Send test message"
3. Paste your FCM token (from console logs)
4. Send notification

#### Option B: Test by Following Someone
1. Have another user follow you
2. Your Cloud Function should trigger
3. You should receive a push notification

---

## 📱 Simulator vs Real Device

⚠️ **Important:** FCM tokens **do not work on iOS Simulator**. You'll see this message:

```
⚠️ Skipping FCM setup on simulator (APNS not available)
```

This is **normal**. To test push notifications:
- Use a **real iOS device**
- Connect to Xcode
- Run the app on the device
- Check console for FCM token

---

## 🐛 Common Issues & Solutions

### Issue: "No FCM token for user" in Cloud Functions

**Solution:** User hasn't granted notification permission or token hasn't synced yet.

```swift
// Make sure you call this after login:
await PushNotificationManager.shared.requestNotificationPermissions()
```

---

### Issue: Token not saving to Firestore

**Check:**
1. User is authenticated: `Auth.auth().currentUser != nil`
2. Internet connection is active
3. Firestore rules allow token updates (they do! ✅)

**Debug:**
```swift
// Add this after login to verify:
Task {
    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
    
    let db = Firestore.firestore()
    let doc = try? await db.collection("users")
        .document(Auth.auth().currentUser!.uid)
        .getDocument()
    
    if let token = doc?.data()?["fcmToken"] as? String {
        print("✅ Token verified in Firestore: \(token)")
    } else {
        print("❌ Token not found in Firestore")
    }
}
```

---

### Issue: Notifications not appearing

**Checklist:**
- [ ] Running on real device (not simulator)
- [ ] Notification permission granted
- [ ] FCM token saved to Firestore
- [ ] Cloud Functions deployed
- [ ] App is in background (foreground notifications use banner)

---

## 📝 Complete Code Examples

### Example 1: Sign In View

```swift
import SwiftUI
import FirebaseAuth

struct SignInView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            TextField("Email", text: $email)
            SecureField("Password", text: $password)
            
            Button("Sign In") {
                Task { await handleLogin() }
            }
        }
    }
    
    func handleLogin() async {
        isLoading = true
        
        do {
            // Sign in
            try await Auth.auth().signIn(withEmail: email, password: password)
            
            // ✅ Setup FCM
            let granted = await PushNotificationManager.shared.requestNotificationPermissions()
            if granted {
                PushNotificationManager.shared.setupFCMToken()
            }
            
            isLoading = false
        } catch {
            print("Login error: \(error)")
            isLoading = false
        }
    }
}
```

---

### Example 2: Content View

```swift
import SwiftUI
import FirebaseAuth

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
            MessagesView()
            NotificationsView()
            ProfileView()
        }
        .onAppear {
            setupFCMIfLoggedIn()
        }
    }
    
    func setupFCMIfLoggedIn() {
        guard Auth.auth().currentUser != nil else { return }
        
        Task {
            let hasPermission = await PushNotificationManager.shared.checkNotificationPermissions()
            if hasPermission {
                PushNotificationManager.shared.setupFCMToken()
            }
        }
    }
}
```

---

### Example 3: Settings View (Logout)

```swift
import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    var body: some View {
        Button("Sign Out") {
            Task { await handleLogout() }
        }
    }
    
    func handleLogout() async {
        // ✅ Remove FCM token first
        await PushNotificationManager.shared.removeFCMTokenFromFirestore()
        PushNotificationManager.shared.clearBadge()
        
        // Sign out
        try? Auth.auth().signOut()
    }
}
```

---

## 🎉 Summary

You already have **all the infrastructure** for push notifications! Just add these 3 function calls:

1. **After login:** `PushNotificationManager.shared.requestNotificationPermissions()`
2. **On app launch:** `PushNotificationManager.shared.setupFCMToken()`  
3. **Before logout:** `PushNotificationManager.shared.removeFCMTokenFromFirestore()`

That's it! Your Cloud Functions will automatically send push notifications when users:
- Follow you
- Comment on your posts
- Send you messages
- Accept your follow request

---

## 🚀 Next Steps

1. Add the 3 code snippets above to your app
2. Run on a real iOS device
3. Test following someone
4. Receive your first push notification! 🎉

Your existing Cloud Functions (`index.js` and `pushNotifications.js`) already handle everything else automatically.

---

## 📚 Additional Resources

- [Firebase Cloud Messaging Docs](https://firebase.google.com/docs/cloud-messaging/ios/client)
- [Apple Push Notification Service](https://developer.apple.com/documentation/usernotifications)
- Your existing files:
  - `PushNotificationManager.swift` - Full implementation
  - `AppDelegate+Messaging.swift` - Configuration
  - `FCM_TOKEN_INTEGRATION_GUIDE.swift` - Detailed examples

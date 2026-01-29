//
//  FIREBASE_SETUP_GUIDE.md
//  AMENAPP
//
//  Complete Firebase Integration Guide
//

# Firebase Setup Guide for AMENAPP Messaging

## ✅ Step 1: Add Firebase to Your Xcode Project

### 1.1 Install Firebase SDK

1. **In Xcode**, go to: `File` → `Add Package Dependencies...`
2. **Paste this URL**: `https://github.com/firebase/firebase-ios-sdk`
3. **Select these packages**:
   - ✅ FirebaseAuth
   - ✅ FirebaseFirestore
   - ✅ FirebaseStorage
4. Click **Add Package**

### 1.2 Register Your App with Firebase

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **Add Project** or select existing project
3. Name it: "AMENAPP" or your preferred name
4. Click **Add App** → **iOS**
5. Enter your **Bundle ID** (found in Xcode: Target → General → Bundle Identifier)
6. Download `GoogleService-Info.plist`
7. **Drag the file into your Xcode project** (make sure "Copy items if needed" is checked)

---

## ✅ Step 2: Initialize Firebase in Your App

Create or update your main App file:

```swift
import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct AMENAPPApp: App {
    
    // Initialize Firebase
    init() {
        FirebaseApp.configure()
        
        // Optional: Sign in anonymously for testing
        // signInAnonymously()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    // MARK: - Anonymous Authentication (for testing)
    
    private func signInAnonymously() {
        Auth.auth().signInAnonymously { result, error in
            if let error = error {
                print("Error signing in anonymously: \(error)")
            } else {
                print("Signed in anonymously with UID: \(result?.user.uid ?? "")")
            }
        }
    }
}
```

---

## ✅ Step 3: Configure Firestore Database

### 3.1 Enable Firestore

1. In [Firebase Console](https://console.firebase.google.com/), select your project
2. Click **Build** → **Firestore Database**
3. Click **Create Database**
4. Choose **Start in test mode** (for now - we'll secure it later)
5. Select a location (choose closest to your users)
6. Click **Enable**

### 3.2 Set Up Firestore Security Rules

Go to **Firestore Database** → **Rules** tab and paste:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isSignedIn() {
      return request.auth != null;
    }
    
    // Helper function to check if user is participant in conversation
    function isParticipant(conversationId) {
      return request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
    }
    
    // Conversations
    match /conversations/{conversationId} {
      // Users can read conversations they're part of
      allow read: if isSignedIn() && isParticipant(conversationId);
      
      // Users can create conversations
      allow create: if isSignedIn() && request.auth.uid in request.resource.data.participantIds;
      
      // Participants can update conversation (for last message, etc.)
      allow update: if isSignedIn() && isParticipant(conversationId);
      
      // Only participants can delete
      allow delete: if isSignedIn() && isParticipant(conversationId);
      
      // Messages subcollection
      match /messages/{messageId} {
        // Participants can read messages
        allow read: if isSignedIn() && isParticipant(conversationId);
        
        // Participants can create messages
        allow create: if isSignedIn() && isParticipant(conversationId);
        
        // Only message sender can update/delete
        allow update, delete: if isSignedIn() && request.auth.uid == resource.data.senderId;
      }
      
      // Typing indicators
      match /typing/{userId} {
        allow read: if isSignedIn() && isParticipant(conversationId);
        allow write: if isSignedIn() && request.auth.uid == userId;
      }
    }
    
    // Users collection
    match /users/{userId} {
      // Anyone can read user profiles
      allow read: if isSignedIn();
      
      // Users can only write their own profile
      allow write: if isSignedIn() && request.auth.uid == userId;
    }
  }
}
```

### 3.3 Create Firestore Indexes

Go to **Firestore Database** → **Indexes** tab and create these composite indexes:

1. **Conversations Index**:
   - Collection: `conversations`
   - Fields: 
     - `participantIds` (Arrays)
     - `updatedAt` (Descending)
   - Query scope: Collection

2. **Messages Index**:
   - Collection group: `messages`
   - Fields:
     - `conversationId` (Ascending)
     - `timestamp` (Ascending)
   - Query scope: Collection group

Firebase will also auto-generate indexes when you run queries. Watch the Xcode console for index creation links.

---

## ✅ Step 4: Enable Firebase Storage

### 4.1 Enable Storage

1. Go to **Build** → **Storage**
2. Click **Get Started**
3. Choose **Start in test mode**
4. Click **Done**

### 4.2 Set Up Storage Security Rules

Go to **Storage** → **Rules** tab:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    
    // Messages attachments
    match /messages/{conversationId}/{filename} {
      // Only authenticated users can read
      allow read: if request.auth != null;
      
      // Only authenticated users can upload
      allow write: if request.auth != null
                   && request.resource.size < 10 * 1024 * 1024  // Max 10MB
                   && request.resource.contentType.matches('image/.*');  // Only images
    }
  }
}
```

---

## ✅ Step 5: Set Up Firebase Authentication

### 5.1 Enable Authentication Methods

1. Go to **Build** → **Authentication**
2. Click **Get Started**
3. Go to **Sign-in method** tab
4. Enable these providers:
   - ✅ **Email/Password**
   - ✅ **Anonymous** (for testing)
   - ✅ **Google** (optional)
   - ✅ **Apple** (recommended for iOS)

### 5.2 Configure Apple Sign-In (Recommended)

1. In Firebase Console, enable **Apple** provider
2. In Xcode:
   - Go to your target → **Signing & Capabilities**
   - Click **+ Capability** → Add **Sign in with Apple**

---

## ✅ Step 6: Create Sample Data (For Testing)

### Option A: Use Firebase Console

1. Go to **Firestore Database** → **Data** tab
2. **Create a `users` collection**:
   ```
   Collection: users
   Document ID: [Your Auth UID]
   Fields:
     - name: "Your Name"
     - email: "your@email.com"
     - avatarUrl: null
     - isOnline: true
     - nameKeywords: ["your", "name"]
   ```

3. **Create a `conversations` collection**:
   ```
   Collection: conversations
   Document ID: [Auto ID]
   Fields:
     - participantIds: [array] ["user1_id", "user2_id"]
     - participantNames: [map] { "user1_id": "User 1", "user2_id": "User 2" }
     - isGroup: false
     - groupName: null
     - lastMessageText: "Hey there!"
     - lastMessageTimestamp: [timestamp] (Click "Add field" → "Timestamp" → "Now")
     - unreadCounts: [map] {}
     - createdAt: [timestamp]
     - updatedAt: [timestamp]
   ```

4. **Add messages subcollection**:
   - Select the conversation document
   - Click **Start collection**
   - Collection ID: `messages`
   - Add document:
     ```
     Fields:
       - conversationId: "[conversation_id]"
       - senderId: "[user_id]"
       - senderName: "User Name"
       - text: "Hello! This is a test message 👋"
       - attachments: [array] []
       - reactions: [array] []
       - replyTo: null
       - timestamp: [timestamp]
       - readBy: [array] ["user_id"]
     ```

### Option B: Use This Swift Function

Add this to your app for testing (call it once):

```swift
func createSampleConversation() async {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return }
    
    let db = Firestore.firestore()
    
    // Create a conversation
    let conversationRef = db.collection("conversations").document()
    
    let conversation: [String: Any] = [
        "participantIds": [currentUserId],
        "participantNames": [currentUserId: Auth.auth().currentUser?.displayName ?? "Me"],
        "isGroup": false,
        "lastMessageText": "Welcome to AMENAPP!",
        "lastMessageTimestamp": Timestamp(date: Date()),
        "unreadCounts": [:],
        "createdAt": Timestamp(date: Date()),
        "updatedAt": Timestamp(date: Date())
    ]
    
    try? await conversationRef.setData(conversation)
    
    // Add a welcome message
    let messageRef = conversationRef.collection("messages").document()
    let message: [String: Any] = [
        "conversationId": conversationRef.documentID,
        "senderId": "system",
        "senderName": "AMENAPP",
        "text": "Welcome! Start chatting with your faith community 🙏",
        "attachments": [],
        "reactions": [],
        "timestamp": Timestamp(date: Date()),
        "readBy": [currentUserId]
    ]
    
    try? await messageRef.setData(message)
    
    print("✅ Sample conversation created!")
}
```

---

## ✅ Step 7: Test the Integration

### 7.1 Build and Run

1. **Clean Build Folder**: `Shift + Cmd + K`
2. **Build**: `Cmd + B`
3. **Run**: `Cmd + R`

### 7.2 What to Test

- ✅ Open the Messages tab
- ✅ Conversations should load from Firestore
- ✅ Tap a conversation to open chat
- ✅ Send a message (it should appear in Firestore)
- ✅ Try sending a photo
- ✅ Try adding reactions
- ✅ Try replying to messages
- ✅ Open the same conversation on another device (messages should sync!)

### 7.3 Debug Console Messages

Watch for these success messages:
```
✅ Firebase configured successfully
✅ Signed in with UID: [user_id]
✅ Listening to conversations
✅ Loaded X conversations
✅ Listening to messages for conversation: [id]
```

---

## ✅ Step 8: Firestore Data Structure

Here's what your Firestore database will look like:

```
📁 conversations (collection)
  📄 [conversation_id] (document)
    - participantIds: [array of user IDs]
    - participantNames: {userId: "Name", ...}
    - isGroup: boolean
    - groupName: string? (optional)
    - lastMessageText: string
    - lastMessageTimestamp: timestamp
    - unreadCounts: {userId: number, ...}
    - createdAt: timestamp
    - updatedAt: timestamp
    
    📁 messages (subcollection)
      📄 [message_id] (document)
        - conversationId: string
        - senderId: string
        - senderName: string
        - text: string
        - attachments: [array]
        - reactions: [array]
        - replyTo: object? (optional)
        - timestamp: timestamp
        - readBy: [array of user IDs]
    
    📁 typing (subcollection)
      📄 [user_id] (document)
        - userId: string
        - userName: string
        - timestamp: timestamp

📁 users (collection)
  📄 [user_id] (document)
    - name: string
    - email: string
    - avatarUrl: string?
    - isOnline: boolean
    - nameKeywords: [array for search]
```

---

## ✅ Step 9: Common Issues & Solutions

### Issue: "Firebase is not configured"

**Solution**: Make sure `FirebaseApp.configure()` is called in your App's `init()` and `GoogleService-Info.plist` is in your project.

### Issue: "Permission denied" errors

**Solution**: Check your Firestore Security Rules. For testing, you can temporarily use:
```javascript
allow read, write: if request.auth != null;
```

### Issue: Conversations not loading

**Solution**: 
1. Check if user is authenticated: `print(Auth.auth().currentUser?.uid)`
2. Verify user ID is in `participantIds` array
3. Check Firestore console to see if data exists

### Issue: Images not uploading

**Solution**:
1. Check Firebase Storage rules
2. Verify Storage is enabled in Firebase Console
3. Check file size (max 10MB by default)

### Issue: "Missing or insufficient permissions"

**Solution**: Your Firestore Security Rules are too restrictive. Update them to match Step 3.2.

---

## ✅ Step 10: Production Considerations

Before launching to production:

### 10.1 Security
- ✅ Remove anonymous authentication
- ✅ Implement proper user authentication (Email, Apple Sign-In)
- ✅ Review and tighten security rules
- ✅ Enable App Check to prevent abuse

### 10.2 Performance
- ✅ Implement pagination for messages (load 50 at a time)
- ✅ Add offline persistence: 
  ```swift
  let settings = Firestore.firestore().settings
  settings.isPersistenceEnabled = true
  ```
- ✅ Optimize queries with proper indexes

### 10.3 Features to Add
- ✅ Push notifications for new messages
- ✅ Online/offline status
- ✅ Message delivery receipts
- ✅ Voice messages
- ✅ Video calls
- ✅ Message search
- ✅ Archived conversations

### 10.4 Monitoring
- ✅ Enable Firebase Analytics
- ✅ Set up Firebase Crashlytics
- ✅ Monitor Firestore usage in console

---

## 🎉 You're Done!

Your messaging system is now connected to Firebase! Messages will:
- ✅ Sync in real-time across devices
- ✅ Persist in the cloud
- ✅ Support photos and attachments
- ✅ Work offline and sync when online

## 📚 Additional Resources

- [Firebase iOS Documentation](https://firebase.google.com/docs/ios/setup)
- [Firestore Security Rules Guide](https://firebase.google.com/docs/firestore/security/get-started)
- [Firebase Storage Guide](https://firebase.google.com/docs/storage/ios/start)
- [Firebase Auth Guide](https://firebase.google.com/docs/auth/ios/start)

## 💡 Need Help?

Common commands for debugging:
```swift
// Check if Firebase is configured
print("Firebase configured: \(FirebaseApp.app() != nil)")

// Check current user
print("Current user: \(Auth.auth().currentUser?.uid ?? "Not signed in")")

// Enable Firestore logging
FirebaseConfiguration.shared.setLoggerLevel(.debug)
```

---

**Questions or issues? Check the Firebase Console for error messages and quota limits!**

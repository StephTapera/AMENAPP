# User Search Setup Guide

## Quick Start: Enable User Search in Your App

### Step 1: Update User Registration

When a user signs up, create their document in Firestore with search keywords:

```swift
import FirebaseFirestore
import FirebaseAuth

func createUserProfile(name: String, email: String) async throws {
    guard let userId = Auth.auth().currentUser?.uid else { return }
    
    // Generate search keywords from name
    let keywords = generateSearchKeywords(from: name)
    
    let userData: [String: Any] = [
        "id": userId,
        "name": name,
        "email": email,
        "avatarUrl": nil,
        "isOnline": true,
        "nameKeywords": keywords,
        "createdAt": Timestamp(date: Date()),
        "updatedAt": Timestamp(date: Date())
    ]
    
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .setData(userData)
}

// Helper function to generate search keywords
func generateSearchKeywords(from name: String) -> [String] {
    let lowercased = name.lowercased()
    
    // Split into words
    let words = lowercased.split(separator: " ").map { String($0) }
    
    // Add full name
    var keywords = [lowercased]
    
    // Add individual words
    keywords.append(contentsOf: words)
    
    // Add prefixes for autocomplete
    for word in words {
        for i in 1...word.count {
            let prefix = String(word.prefix(i))
            if !keywords.contains(prefix) {
                keywords.append(prefix)
            }
        }
    }
    
    return keywords
}
```

### Step 2: Firestore Security Rules

Add these rules to your `firestore.rules` file:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users collection - readable by authenticated users
    match /users/{userId} {
      // Anyone authenticated can read user profiles
      allow read: if request.auth != null;
      
      // Users can only write their own profile
      allow write: if request.auth.uid == userId;
    }
    
    // Conversations - only participants can access
    match /conversations/{conversationId} {
      allow read: if request.auth != null && 
        request.auth.uid in resource.data.participantIds;
      
      allow create: if request.auth != null && 
        request.auth.uid in request.resource.data.participantIds;
      
      allow update: if request.auth != null && 
        request.auth.uid in resource.data.participantIds;
      
      // Messages subcollection
      match /messages/{messageId} {
        allow read, write: if request.auth != null && 
          request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
      }
    }
  }
}
```

### Step 3: Create Firestore Indexes

The search query requires an index. Create it via Firebase Console or add to `firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "users",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "nameKeywords",
          "arrayConfig": "CONTAINS"
        },
        {
          "fieldPath": "name",
          "order": "ASCENDING"
        }
      ]
    }
  ]
}
```

Or Firebase will prompt you with a link when you first try to search.

### Step 4: Test User Search

Add some test users to your Firestore database:

```swift
// Run this once to add test users
func addTestUsers() async {
    let db = Firestore.firestore()
    
    let testUsers: [[String: Any]] = [
        [
            "id": "test1",
            "name": "Sarah Chen",
            "email": "sarah@test.com",
            "avatarUrl": nil,
            "isOnline": true,
            "nameKeywords": ["sarah", "chen", "s", "sa", "sar", "sara", "sarah", "c", "ch", "che", "chen"]
        ],
        [
            "id": "test2",
            "name": "Michael Thompson",
            "email": "michael@test.com",
            "avatarUrl": nil,
            "isOnline": false,
            "nameKeywords": ["michael", "thompson", "m", "mi", "mic", "mich", "micha", "michae", "michael", "t", "th", "tho", "thom", "thomp", "thomps", "thompso", "thompson"]
        ],
        [
            "id": "test3",
            "name": "Emily Rodriguez",
            "email": "emily@test.com",
            "avatarUrl": nil,
            "isOnline": true,
            "nameKeywords": ["emily", "rodriguez", "e", "em", "emi", "emil", "emily", "r", "ro", "rod", "rodr", "rodri", "rodrig", "rodrigu", "rodrigue", "rodriguez"]
        ]
    ]
    
    for user in testUsers {
        try? await db.collection("users").document(user["id"] as! String).setData(user)
    }
    
    print("Test users added!")
}
```

### Step 5: Update User Profile on Name Change

If users can change their name, update the keywords:

```swift
func updateUserName(newName: String) async throws {
    guard let userId = Auth.auth().currentUser?.uid else { return }
    
    let keywords = generateSearchKeywords(from: newName)
    
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .updateData([
            "name": newName,
            "nameKeywords": keywords,
            "updatedAt": Timestamp(date: Date())
        ])
}
```

### Step 6: Add Online Presence (Optional)

For real-time online status:

```swift
import FirebaseDatabase

class PresenceManager {
    static let shared = PresenceManager()
    private let rtdb = Database.database().reference()
    
    func setOnline() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Set user as online in Realtime Database
        rtdb.child("presence").child(userId).setValue([
            "online": true,
            "lastSeen": ServerValue.timestamp()
        ])
        
        // Set to offline on disconnect
        rtdb.child("presence").child(userId).onDisconnectSetValue([
            "online": false,
            "lastSeen": ServerValue.timestamp()
        ])
        
        // Also update Firestore
        Task {
            try? await Firestore.firestore()
                .collection("users")
                .document(userId)
                .updateData(["isOnline": true])
        }
    }
    
    func setOffline() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            try? await Firestore.firestore()
                .collection("users")
                .document(userId)
                .updateData(["isOnline": false])
        }
    }
}
```

Call in your app delegate or main view:

```swift
struct AMENAPPApp: App {
    init() {
        // Setup Firebase
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    PresenceManager.shared.setOnline()
                }
                .onDisappear {
                    PresenceManager.shared.setOffline()
                }
        }
    }
}
```

### Step 7: Verify Everything Works

1. **Add test users** to Firestore (Step 4)
2. **Open your app** and go to Messages
3. **Tap "New Message"** button
4. **Type a name** (e.g., "Sarah")
5. **See results** appear!

### Common Issues

**"No users found"**
- Check that users exist in Firestore `/users` collection
- Verify `nameKeywords` field exists and is an array
- Check Firebase security rules allow reading users

**"Missing index" error**
- Click the link in the error message to create the index
- Or add the index manually in Firebase Console

**Search is slow**
- Add composite index (see Step 3)
- Consider limiting results (already set to 20)
- Use debouncing (already implemented)

**Users can't see each other**
- Check Firestore security rules
- Verify user is authenticated (`Auth.auth().currentUser`)

### Advanced: Add Username Search

Update your user model to include username:

```swift
struct ContactUser: Codable, Identifiable {
    @DocumentID var id: String?
    let name: String
    let username: String?  // Add this
    let email: String
    let avatarUrl: String?
    let isOnline: Bool
    let nameKeywords: [String]
    let usernameKeywords: [String]?  // Add this
}
```

Then update search to check both:

```swift
// In FirebaseMessagingService
func searchUsers(query: String) async throws -> [ContactUser] {
    guard !query.isEmpty else { return [] }
    
    let lowerQuery = query.lowercased()
    
    // Search by name
    let nameResults = try await db.collection("users")
        .whereField("nameKeywords", arrayContains: lowerQuery)
        .limit(to: 10)
        .getDocuments()
    
    // Search by username
    let usernameResults = try await db.collection("users")
        .whereField("usernameKeywords", arrayContains: lowerQuery)
        .limit(to: 10)
        .getDocuments()
    
    // Combine and deduplicate
    var users: [ContactUser] = []
    var userIds = Set<String>()
    
    for doc in nameResults.documents + usernameResults.documents {
        if let user = try? doc.data(as: ContactUser.self),
           let userId = user.id,
           !userIds.contains(userId) {
            users.append(user)
            userIds.insert(userId)
        }
    }
    
    return Array(users.prefix(20))
}
```

## You're Done! 🎉

Your users can now search for each other and start conversations!

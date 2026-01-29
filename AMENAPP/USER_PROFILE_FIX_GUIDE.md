# User Profile View - Error Fix Guide 🔧

## Issue: "Something went wrong. Please try again"

### Problem
When clicking on other users' profiles from anywhere in the app (posts, comments, search results, etc.), the profile view shows the error "Something went wrong. Please try again."

---

## Root Causes Identified

### 1. **Missing or Incomplete User Data in Firestore**
- User documents may not have all required fields
- Some users may have been created before certain fields were added
- Fields like `displayName`, `username`, or `bio` might be missing

### 2. **Firestore Permission Issues**
- Security rules may be blocking access to user documents
- Current user may not have read permissions for other users' profiles

### 3. **Network/Connection Issues**
- User may have poor internet connection
- Firestore request may be timing out

### 4. **Parallel Fetch Failures**
- One of the async tasks (posts, replies, reposts, follow status) may be failing
- Error in any task causes the entire profile load to fail

---

## What Was Fixed

### ✅ Enhanced Error Logging
Added comprehensive logging throughout `loadProfileData()`:

```swift
@MainActor
private func loadProfileData() async {
    isLoading = true
    errorMessage = ""
    
    do {
        print("👤 Loading profile data for user ID: \(userId)")
        
        // Fetch user profile directly from Firestore
        let db = Firestore.firestore()
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        guard userDoc.exists else {
            print("❌ User document does not exist for ID: \(userId)")
            throw NSError(domain: "UserProfileView", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "User not found"
            ])
        }
        
        guard let data = userDoc.data() else {
            print("❌ User document exists but has no data for ID: \(userId)")
            throw NSError(domain: "UserProfileView", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "User data could not be loaded"
            ])
        }
        
        print("✅ Found user document with data: \(data.keys)")
        print("📋 User data extracted:")
        print("   - displayName: \(displayName)")
        print("   - username: \(username)")
        print("   - followersCount: \(followersCount)")
        
        // ... rest of function
    } catch {
        print("❌ Error in loadProfileData:")
        print("   - Error type: \(type(of: error))")
        print("   - Error description: \(error.localizedDescription)")
        
        errorMessage = handleError(error)
        showErrorAlert = true
    }
    
    isLoading = false
}
```

### ✅ Improved Error Handling
Enhanced `handleError()` to provide specific error messages:

```swift
private func handleError(_ error: Error) -> String {
    // Handle Firestore errors
    if let firestoreError = error as NSError? {
        if firestoreError.domain == "FIRFirestoreErrorDomain" {
            switch firestoreError.code {
            case 7: // Permission denied
                return "You don't have permission to view this profile."
            case 5: // Not found
                return "User not found."
            case 14: // Unavailable (network)
                return "Unable to connect to server. Please check your connection."
            default:
                break
            }
        }
    }
    
    // Handle network errors
    if let networkError = error as? URLError {
        switch networkError.code {
        case .notConnectedToInternet:
            return "No internet connection."
        case .timedOut:
            return "Request timed out. Please try again."
        default:
            return "Network error occurred."
        }
    }
    
    // Show actual error in development
    return "Unable to load profile. Please try again.\n\n(\(error.localizedDescription))"
}
```

---

## How to Debug

### Step 1: Check Console Logs
When you try to open a user's profile, check Xcode console for these logs:

**Successful Load:**
```
👤 Loading profile data for user ID: abc123xyz
✅ Found user document with data: ["displayName", "username", "bio", ...]
📋 User data extracted:
   - displayName: John Doe
   - username: johndoe
   - bio length: 50
   - followersCount: 123
   - followingCount: 45
✅ Fetched user: John Doe (@johndoe)
✅ Profile data converted successfully
📥 Starting parallel fetch for posts, replies, reposts, and follow status...
✅ Parallel fetch completed:
   - Posts: 5
   - Replies: 3
   - Reposts: 2
   - Following: false
```

**Failed Load (User Not Found):**
```
👤 Loading profile data for user ID: abc123xyz
❌ User document does not exist for ID: abc123xyz
❌ Error in loadProfileData:
   - Error type: NSError
   - Error description: User not found
```

**Failed Load (Missing Data):**
```
👤 Loading profile data for user ID: abc123xyz
❌ User document exists but has no data for ID: abc123xyz
❌ Error in loadProfileData:
   - Error type: NSError
   - Error description: User data could not be loaded
```

**Failed Load (Permission Denied):**
```
👤 Loading profile data for user ID: abc123xyz
❌ Error in loadProfileData:
   - Error type: NSError
   - Error description: Permission denied
   - Error code: 7
   - Error domain: FIRFirestoreErrorDomain
```

### Step 2: Check Firestore Console
1. Open Firebase Console → Firestore Database
2. Navigate to `users` collection
3. Find the problematic user by their ID
4. Verify these fields exist:
   - ✅ `displayName` (string)
   - ✅ `username` (string)
   - ✅ `bio` (string, can be empty)
   - ✅ `followersCount` (number)
   - ✅ `followingCount` (number)

### Step 3: Check Firestore Security Rules
Verify your security rules allow reading other users' profiles:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection - anyone can read, only owner can write
    match /users/{userId} {
      allow read: if request.auth != null;  // ✅ Any authenticated user can read
      allow write: if request.auth.uid == userId;  // Only owner can write
    }
  }
}
```

If your rules look different, that might be the issue!

---

## Common Scenarios & Solutions

### Scenario 1: "User not found"
**Cause:** User ID doesn't exist in Firestore

**Solutions:**
1. Verify the user ID being passed is correct
2. Check if user was deleted
3. Verify navigation is passing correct `userId` parameter

**How to check:**
```swift
// In the view that navigates to UserProfileView
print("🔗 Navigating to profile with userId: \(userId)")
```

### Scenario 2: "You don't have permission to view this profile"
**Cause:** Firestore security rules denying access

**Solutions:**
1. Update Firestore rules to allow authenticated users to read profiles
2. Ensure user is authenticated before viewing profiles

**Firestore Rules Fix:**
```javascript
match /users/{userId} {
  allow read: if request.auth != null;
}
```

### Scenario 3: "Unable to connect to server"
**Cause:** Network connection issue or Firestore unavailable

**Solutions:**
1. Check device internet connection
2. Try again later
3. Check Firebase Console for any outages

### Scenario 4: Profile loads but shows "Unknown User"
**Cause:** Missing `displayName` field in Firestore

**Solutions:**
1. Run a migration to add default displayName for users missing it
2. Update user creation code to always set displayName

**Migration Script:**
```swift
// Run this once to fix existing users
func fixMissingDisplayNames() async {
    let db = Firestore.firestore()
    let users = try await db.collection("users").getDocuments()
    
    for doc in users.documents {
        if doc.data()["displayName"] == nil {
            try await doc.reference.updateData([
                "displayName": "User \(doc.documentID.prefix(6))"
            ])
            print("✅ Fixed displayName for user: \(doc.documentID)")
        }
    }
}
```

---

## Testing Checklist

### ✅ Test Loading Different Users
- [ ] Open a user profile from a post
- [ ] Open a user profile from search results
- [ ] Open a user profile from followers list
- [ ] Open a user profile from following list
- [ ] Open a user profile from comments
- [ ] Try opening your own profile
- [ ] Try opening a non-existent user (should show "User not found")

### ✅ Test Error States
- [ ] Turn on Airplane Mode → Try loading profile (should show network error)
- [ ] Load a user with missing data (should show specific error)
- [ ] Load a deleted user (should show "User not found")

### ✅ Test Recovery
- [ ] After error, tap "Retry" button (should reload)
- [ ] After error, pull to refresh (should reload)
- [ ] After error, navigate away and come back (should reload)

---

## Prevention (For Future)

### 1. **Ensure User Document Creation**
Always create complete user documents:

```swift
func createNewUser(userId: String, email: String, name: String) async throws {
    let db = Firestore.firestore()
    
    let userData: [String: Any] = [
        "id": userId,
        "email": email,
        "displayName": name,
        "username": generateUsername(from: name),
        "bio": "",
        "followersCount": 0,
        "followingCount": 0,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp()
    ]
    
    try await db.collection("users").document(userId).setData(userData)
    print("✅ Created complete user document for: \(userId)")
}
```

### 2. **Handle Missing Fields Gracefully**
Use default values for optional fields:

```swift
let displayName = data["displayName"] as? String ?? "User \(userId.prefix(6))"
let username = data["username"] as? String ?? "user\(userId.prefix(6))"
let bio = data["bio"] as? String ?? "No bio yet"
```

### 3. **Add Data Validation**
Validate user data before saving:

```swift
func validateUserData(_ data: [String: Any]) -> Bool {
    guard let _ = data["displayName"] as? String else {
        print("❌ Missing displayName")
        return false
    }
    
    guard let _ = data["username"] as? String else {
        print("❌ Missing username")
        return false
    }
    
    return true
}
```

### 4. **Use Transactions for User Creation**
Ensure atomic user creation:

```swift
try await db.runTransaction { transaction, errorPointer in
    // Create user document
    let userRef = db.collection("users").document(userId)
    transaction.setData(userData, forDocument: userRef)
    
    // Create user search index
    let searchRef = db.collection("userSearch").document(userId)
    transaction.setData(searchData, forDocument: searchRef)
    
    return nil
}
```

---

## Quick Fix Checklist

If profiles are failing to load:

1. ✅ Check Xcode console for error logs
2. ✅ Verify user exists in Firestore Console
3. ✅ Check Firestore security rules allow reading users
4. ✅ Verify all required fields exist in user document
5. ✅ Test network connection
6. ✅ Try loading different users
7. ✅ Check if issue is specific to certain users or all users

---

## Summary

**What Changed:**
- ✅ Added detailed logging to `loadProfileData()`
- ✅ Enhanced error handling with specific messages
- ✅ Better separation of concerns (user exists vs has data vs permission denied)
- ✅ More helpful error messages for users

**What To Do Next:**
1. Run the app and try loading different user profiles
2. Check console logs to see exactly where it's failing
3. Based on the logs, apply the appropriate solution from above
4. If still stuck, share the console logs for further debugging

**Expected Outcome:**
- Profiles should load successfully ✅
- If they fail, you'll see a specific, helpful error message ✅
- Console logs will tell you exactly what went wrong ✅

---

## Need Help?

If you're still seeing errors after this fix:

1. **Share the console logs** - Copy the error logs from Xcode console
2. **Share the user ID** - What's the userId that's failing to load?
3. **Share Firestore data** - Screenshot of the user document in Firestore Console
4. **Share security rules** - Copy your Firestore security rules

This will help pinpoint the exact issue! 🚀

# Authentication Cloud Functions - Quick Start Guide

**Date:** February 20, 2026
**Status:** Production Deployed ✅

---

## Available Functions

### 1. `reserveUsername` - Reserve a Username (Required for Signup)
### 2. `checkUsernameAvailability` - Check Username Availability (UI Validation)
### 3. `onUserDeleted` - Auto Cascade Delete (Automatic Trigger)
### 4. `manualCascadeDelete` - Manual Cascade Delete (Admin/Testing)

---

## 1. Reserve Username (REQUIRED for Signup)

### Purpose
Atomically claim a username using Firestore transactions. Prevents race conditions where two users try to register the same username simultaneously.

### When to Call
**BEFORE** creating the user document during signup.

### Swift Example
```swift
import FirebaseFunctions

func signUp(email: String, password: String, displayName: String, username: String) async throws {
    // 1. Create Firebase Auth account first
    let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
    let userId = authResult.user.uid

    do {
        // 2. Reserve username (server-side transaction)
        let functions = Functions.functions()
        let reserveFunction = functions.httpsCallable("reserveUsername")

        let result = try await reserveFunction.call([
            "username": username,
            "userId": userId
        ])

        print("✅ Username reserved:", result.data)

        // 3. Create user document in Firestore
        try await createUserDocument(
            userId: userId,
            email: email,
            displayName: displayName,
            username: username
        )

        print("✅ User account created successfully")

    } catch {
        // Username reservation failed - delete the auth account
        try? await authResult.user.delete()

        // Parse error
        if let error = error as NSError? {
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)

                if code == .alreadyExists {
                    throw AuthError.usernameTaken(username)
                } else if code == .invalidArgument {
                    throw AuthError.invalidUsername
                } else if code == .permissionDenied {
                    throw AuthError.permissionDenied
                }
            }
        }

        throw error
    }
}

enum AuthError: LocalizedError {
    case usernameTaken(String)
    case invalidUsername
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .usernameTaken(let username):
            return "Username '\(username)' is already taken"
        case .invalidUsername:
            return "Username must be 3-20 characters (letters, numbers, underscores only)"
        case .permissionDenied:
            return "Permission denied"
        }
    }
}
```

### Parameters
- `username` (String): Desired username (will be lowercased and validated)
- `userId` (String): Firebase Auth user ID

### Returns
```json
{
  "success": true,
  "username": "johndoe"
}
```

### Errors
- `already-exists`: Username is already taken
- `invalid-argument`: Invalid username format (must be 3-20 chars, lowercase letters, numbers, underscores)
- `permission-denied`: User trying to reserve username for someone else
- `unauthenticated`: User not signed in

### Validation Rules
- 3-20 characters
- Lowercase letters, numbers, underscores only
- No spaces, special characters, emojis
- Regex: `^[a-z0-9_]{3,20}$`

---

## 2. Check Username Availability (UI Validation)

### Purpose
Real-time username availability checking for UI feedback during signup.

### When to Call
As user types in the username field (debounced 500ms).

### Swift Example
```swift
import FirebaseFunctions

class SignUpViewModel: ObservableObject {
    @Published var username = ""
    @Published var usernameAvailable: Bool? = nil
    @Published var checkingUsername = false

    private var checkTask: Task<Void, Never>?

    init() {
        // Debounced username availability check
        $username
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] newValue in
                self?.checkUsernameAvailability(newValue)
            }
            .store(in: &cancellables)
    }

    func checkUsernameAvailability(_ username: String) {
        // Cancel previous check
        checkTask?.cancel()

        guard !username.isEmpty else {
            usernameAvailable = nil
            return
        }

        checkingUsername = true
        usernameAvailable = nil

        checkTask = Task {
            do {
                let functions = Functions.functions()
                let checkFunction = functions.httpsCallable("checkUsernameAvailability")

                let result = try await checkFunction.call(["username": username])

                if let data = result.data as? [String: Any],
                   let available = data["available"] as? Bool {
                    await MainActor.run {
                        self.usernameAvailable = available
                        self.checkingUsername = false
                    }
                }
            } catch {
                print("❌ Username check error:", error)
                await MainActor.run {
                    self.checkingUsername = false
                }
            }
        }
    }
}

// UI Example
struct SignUpView: View {
    @StateObject private var viewModel = SignUpViewModel()

    var body: some View {
        VStack {
            HStack {
                TextField("Username", text: $viewModel.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if viewModel.checkingUsername {
                    ProgressView()
                        .padding(.leading, 8)
                } else if let available = viewModel.usernameAvailable {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(available ? .green : .red)
                        .padding(.leading, 8)
                }
            }

            if let available = viewModel.usernameAvailable, !available {
                Text("Username is already taken")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}
```

### Parameters
- `username` (String): Username to check

### Returns
```json
// Available
{
  "available": true,
  "username": "johndoe"
}

// Taken
{
  "available": false,
  "username": "johndoe"
}

// Invalid format
{
  "available": false,
  "reason": "invalid_format",
  "message": "Username must be 3-20 characters (letters, numbers, underscores only)"
}
```

### Errors
- `invalid-argument`: Missing username parameter

---

## 3. Auto Cascade Delete (Automatic Trigger)

### Purpose
Automatically triggered when a user document is deleted from Firestore. Deletes all associated user data across the entire system.

### When Triggered
Automatically runs when `users/{userId}` document is deleted.

### What Gets Deleted
1. ✅ All posts by user (`posts` collection)
2. ✅ All comments by user (Realtime Database `postInteractions`)
3. ✅ All follow relationships (`follows` collection)
4. ✅ 1-on-1 conversations (group convos: user removed from participants)
5. ✅ All notifications sent by user (other users' subcollections)
6. ✅ All notifications received by user (`users/{userId}/notifications`)
7. ✅ Saved posts (`users/{userId}/savedPosts`)
8. ✅ Prayer requests (`prayers` collection)
9. ✅ Church notes (`churchNotes` collection)
10. ✅ Profile images (Firebase Storage `profile_images/{userId}.*`)
11. ✅ Username reservation (`usernames/{username}`)

### Swift Example (Account Deletion)
```swift
func deleteAccount() async throws {
    guard let user = Auth.auth().currentUser else {
        throw AuthError.notAuthenticated
    }

    let userId = user.uid

    do {
        // 1. Delete user document from Firestore
        // This automatically triggers onUserDeleted Cloud Function
        try await Firestore.firestore()
            .collection("users")
            .document(userId)
            .delete()

        print("✅ User document deleted - cascade delete triggered")

        // 2. Wait a moment for cascade delete to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // 3. Delete Firebase Auth account
        try await user.delete()

        print("✅ Firebase Auth account deleted")

        // Cloud Function is now running in background to clean up all data

    } catch {
        print("❌ Account deletion error:", error)
        throw error
    }
}
```

### Monitoring
Check Cloud Function logs to verify cascade delete completed:
```bash
firebase functions:log --only onUserDeleted
```

Expected output:
```
🗑️ User deleted: abc123
1️⃣ Deleting posts...
✅ Deleted 15 posts
2️⃣ Deleting comments from Realtime Database...
✅ Deleted 42 comments
3️⃣ Deleting follow relationships...
✅ Deleted 28 follow relationships
4️⃣ Handling conversations...
✅ Handled 3 conversations
5️⃣ Deleting notifications sent by user...
✅ Deleted 67 notifications sent by user
6️⃣ Deleting notifications received by user...
✅ Deleted 45 notifications received by user
7️⃣ Deleting saved posts...
✅ Deleted 8 saved posts
8️⃣ Deleting prayer requests...
✅ Deleted 3 prayer requests
9️⃣ Deleting church notes...
✅ Deleted 5 church notes
🔟 Deleting profile images from Storage...
   Deleted: profile_images/abc123.jpg
✅ Storage cleanup complete
✅✅✅ CASCADE DELETE COMPLETE for user abc123 ✅✅✅
```

### Performance
- Execution time: 1-5 seconds (depending on data volume)
- Runs asynchronously (user sees instant "Account Deleted" message)
- Automatically retries if timeout occurs

---

## 4. Manual Cascade Delete (Admin/Testing)

### Purpose
Manually trigger cascade delete without deleting user document. Useful for:
- Testing the cascade delete logic
- Cleaning up orphaned data
- Admin data cleanup

### When to Call
Only in development/testing, or for admin cleanup operations.

### Swift Example
```swift
func manualCascadeDelete(userId: String) async throws {
    let functions = Functions.functions()
    let deleteFunction = functions.httpsCallable("manualCascadeDelete")

    do {
        let result = try await deleteFunction.call([
            "userId": userId
        ])

        if let data = result.data as? [String: Any],
           let success = data["success"] as? Bool,
           success {
            print("✅ Manual cascade delete completed")
        }
    } catch {
        print("❌ Manual cascade delete error:", error)
        throw error
    }
}
```

### Parameters
- `userId` (String): The user ID to delete data for

### Returns
```json
{
  "success": true,
  "message": "User data cascade delete completed successfully"
}
```

### Errors
- `permission-denied`: Can only delete your own data (unless admin)
- `invalid-argument`: Missing userId parameter
- `unauthenticated`: User not signed in

### Security
Current implementation only allows users to delete their own data:
```javascript
if (requesterId !== userId) {
  throw new HttpsError("permission-denied", "You can only delete your own data");
}
```

For admin use, update the Cloud Function to check for admin role.

---

## Firestore Security Rules

### Add Username Collection Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Username reservations (read-only for clients)
    match /usernames/{username} {
      // Allow anyone to check username availability
      allow read: if request.auth != null;

      // Only Cloud Functions can write
      allow write: if false;
    }

    // Existing user rules
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
  }
}
```

Deploy rules:
```bash
firebase deploy --only firestore:rules
```

---

## Testing Checklist

### Test 1: Username Uniqueness
```swift
// Scenario: Two users try to register with same username
// Expected: Second user gets "already-exists" error

// User 1
try await signUp(email: "user1@test.com", password: "test123", username: "testuser")
// ✅ SUCCESS

// User 2
try await signUp(email: "user2@test.com", password: "test123", username: "testuser")
// ❌ ERROR: "Username 'testuser' is already taken"
```

### Test 2: Username Availability Check
```swift
// Available username
let result1 = try await checkUsernameAvailability("newuser123")
// Returns: {available: true}

// Taken username
let result2 = try await checkUsernameAvailability("testuser")
// Returns: {available: false}

// Invalid format
let result3 = try await checkUsernameAvailability("ab") // Too short
// Returns: {available: false, reason: "invalid_format"}
```

### Test 3: Cascade Delete
```swift
// 1. Create test account
try await signUp(email: "delete@test.com", password: "test123", username: "deleteme")

// 2. Create test data
try await createPost(text: "Test post")
try await followUser("someOtherUserId")
try await createPrayerRequest(text: "Test prayer")

// 3. Delete account
try await deleteAccount()

// 4. Verify data deleted (check Firebase Console)
// - No posts for userId
// - No follows for userId
// - No prayers for userId
// - Username "deleteme" released (available again)
```

---

## Error Handling Best Practices

### Complete Error Handling Example
```swift
func signUp(email: String, password: String, displayName: String, username: String) async throws {
    // Validate inputs first
    guard isValidEmail(email) else {
        throw AuthError.invalidEmail
    }

    guard isValidPassword(password) else {
        throw AuthError.weakPassword
    }

    guard isValidUsername(username) else {
        throw AuthError.invalidUsername
    }

    do {
        // 1. Create Firebase Auth account
        let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
        let userId = authResult.user.uid

        // 2. Reserve username
        let functions = Functions.functions()
        let reserveFunction = functions.httpsCallable("reserveUsername")

        let result = try await reserveFunction.call([
            "username": username,
            "userId": userId
        ])

        // 3. Create user document
        try await createUserDocument(
            userId: userId,
            email: email,
            displayName: displayName,
            username: username
        )

        print("✅ Sign up successful")

    } catch let error as NSError {
        // Handle Cloud Function errors
        if error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code)

            switch code {
            case .alreadyExists:
                throw AuthError.usernameTaken(username)
            case .invalidArgument:
                throw AuthError.invalidUsername
            case .permissionDenied:
                throw AuthError.permissionDenied
            case .unauthenticated:
                throw AuthError.notAuthenticated
            default:
                throw AuthError.unknown(error.localizedDescription)
            }
        }

        // Handle Firebase Auth errors
        if let authErrorCode = AuthErrorCode(rawValue: error.code) {
            switch authErrorCode {
            case .emailAlreadyInUse:
                throw AuthError.emailAlreadyInUse
            case .weakPassword:
                throw AuthError.weakPassword
            case .invalidEmail:
                throw AuthError.invalidEmail
            default:
                throw AuthError.unknown(error.localizedDescription)
            }
        }

        throw error
    }
}
```

---

## Performance Optimization

### Username Availability Debouncing
```swift
import Combine

class SignUpViewModel: ObservableObject {
    @Published var username = ""
    @Published var usernameAvailable: Bool? = nil

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Debounce 500ms - only check after user stops typing
        $username
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newValue in
                guard !newValue.isEmpty else {
                    self?.usernameAvailable = nil
                    return
                }

                Task {
                    await self?.checkUsernameAvailability(newValue)
                }
            }
            .store(in: &cancellables)
    }

    func checkUsernameAvailability(_ username: String) async {
        // Check username availability...
    }
}
```

### Caching Username Checks (Optional)
```swift
class UsernameCache {
    private static var cache: [String: Bool] = [:]
    private static let cacheExpiry: TimeInterval = 300 // 5 minutes

    static func getCached(_ username: String) -> Bool? {
        return cache[username]
    }

    static func setCached(_ username: String, available: Bool) {
        cache[username] = available

        // Clear cache after 5 minutes
        Task {
            try? await Task.sleep(nanoseconds: UInt64(cacheExpiry * 1_000_000_000))
            cache.removeValue(forKey: username)
        }
    }
}

// Usage
if let cached = UsernameCache.getCached(username) {
    usernameAvailable = cached
    return
}

let result = try await checkUsernameAvailability(username)
UsernameCache.setCached(username, available: result.available)
```

---

## Monitoring & Alerts

### Firebase Console
1. Navigate to **Functions** tab
2. Click on function name (`reserveUsername`, etc.)
3. View:
   - Execution count
   - Execution time
   - Error rate
   - Logs

### Set Up Alerts
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Set up alerts for function errors
firebase functions:config:set alerts.email="admin@amenapp.com"
```

### Logging Best Practices
```javascript
// In Cloud Functions, log important events
console.log(`✅ Username reserved: ${username} for user ${userId}`);
console.error(`❌ Username reservation failed: ${error.message}`);

// Query logs
firebase functions:log --only reserveUsername --limit 50
```

---

## Cost Estimation

### Monthly Cost (1000 new signups)
- `reserveUsername`: 1000 calls × $0.0000004 = **$0.0004**
- `checkUsernameAvailability`: 5000 calls × $0.0000004 = **$0.002**
- `onUserDeleted`: 10 calls × $0.0000004 × 5s = **$0.00002**

**Total:** ~$0.003/month = **$0.036/year**

✅ **Essentially free** for the security guarantees provided.

---

## Troubleshooting

### "Username already taken" but it's available
**Cause:** Username exists in `usernames` collection but user was deleted without cleanup.

**Fix:**
```bash
# Manually delete orphaned username
firebase firestore:delete usernames/{username}
```

**Prevention:** `onUserDeleted` function now automatically cleans up usernames.

---

### Cloud Function timeout during cascade delete
**Cause:** User has >10,000 posts/comments.

**Fix:** Cloud Function automatically retries. Check logs:
```bash
firebase functions:log --only onUserDeleted
```

**Long-term solution:** Implement batched deletion for very large datasets.

---

### "Permission denied" error
**Cause:** User trying to reserve username for someone else.

**Fix:** Ensure `userId` parameter matches authenticated user's ID:
```swift
let userId = Auth.auth().currentUser!.uid // Use actual user ID
```

---

## Summary

✅ **4 Cloud Functions deployed and operational**
✅ **Username uniqueness guaranteed via transactions**
✅ **Complete account deletion cascade**
✅ **Real-time availability checking**
✅ **Production-ready with error handling**

**Integration Steps:**
1. Update `SignUpView` to call `reserveUsername` before creating user
2. Add debounced `checkUsernameAvailability` to username field
3. Update Firestore security rules for `usernames` collection
4. Test with the provided test cases
5. Monitor Cloud Function logs for first 24 hours

**Ready to ship! 🚀**

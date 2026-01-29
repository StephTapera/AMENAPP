# Firebase Database Testing Guide

## 🔥 Overview

This guide explains how to verify that Firebase/Firestore is working correctly and that usernames and display names are being saved to the backend.

## ✅ What Was Fixed

### 1. AppDelegate Registration
**Problem**: AppDelegate wasn't being registered with the SwiftUI app.

**Fixed in `AMENAPPApp.swift`**:
```swift
@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

This ensures:
- ✅ Firebase is configured on app launch
- ✅ Push notifications work properly
- ✅ Firebase Messaging is initialized

### 2. Firebase Configuration Flow

**Proper initialization order**:
1. `AppDelegate.application(didFinishLaunchingWithOptions)` → Calls `FirebaseApp.configure()`
2. `AMENAPPApp.init()` → Configures Firestore settings
3. App launches with Firebase fully configured

## 🧪 Testing Tools Created

### 1. FirebaseDebugger.swift
A comprehensive testing utility that can:
- ✅ Test Firebase connection
- ✅ Verify current user data in Firestore
- ✅ Check if username exists
- ✅ Test write permissions
- ✅ List all usernames in database
- ✅ Run full diagnostics

### 2. FirebaseDebugView.swift
A beautiful SwiftUI interface to access the debugger:
- 🔥 Quick test buttons for each function
- 📝 Username availability checker
- 🧪 Full diagnostics runner
- 📊 Results displayed in-app

## 📱 How to Access Debug Tools

### Method 1: Via App Settings (EASIEST)

1. **Build and run the app**
2. **Sign in** (or sign up)
3. **Tap Profile tab** (bottom-right)
4. **Tap menu icon** (three horizontal lines, top-right)
5. **Scroll down to "DEVELOPER TOOLS"**
6. **Tap "Firebase Database Debug"** 🔥
7. **Run tests!**

### Method 2: Via Console (Advanced)

Add this code anywhere in your app:
```swift
Task {
    await FirebaseDebugger.shared.runFullDiagnostics()
}
```

## 🔍 What Each Test Does

### Test 1: Firebase Connection
**Checks**:
- Is Firebase configured?
- Is user authenticated?
- Can we access Firestore?

**Success Output**:
```
✅ Firebase app is configured
✅ User is authenticated: xyz789abc
   Email: test@example.com
✅ Firestore is accessible
```

**Failure Output**:
```
❌ Firebase app not configured!
```

---

### Test 2: Verify Current User Data
**Checks**:
- Does user document exist in Firestore?
- Does it have a username?
- Does it have a displayName?
- What other data is stored?

**Success Output**:
```
✅ User document exists in Firestore
📄 User document data:
   ✅ username: @johndoe
   ✅ displayName: John Doe
   ✅ email: john@example.com
   📊 followersCount: 0
   📊 followingCount: 0
   📊 postsCount: 0
   📅 createdAt: 2026-01-20 15:30:00
```

**Failure Output**:
```
❌ User document does NOT exist in Firestore
   Expected path: users/xyz789abc
```

Or:
```
✅ User document exists in Firestore
   ❌ username: MISSING
   ❌ displayName: MISSING
```

---

### Test 3: Write Permissions
**Checks**:
- Can we write to the user's document?
- Are Firestore security rules correct?

**Success Output**:
```
✅ Firestore write successful!
```

**Failure Output**:
```
❌ Firestore write failed: PERMISSION_DENIED
   🔒 This is a PERMISSIONS ERROR
   📋 Check your Firestore Security Rules:
   
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{userId} {
         allow create: if request.auth != null && request.auth.uid == userId;
         allow read, update: if request.auth != null;
       }
     }
   }
```

---

### Test 4: List All Usernames
**Shows**:
- All users in the database
- Their usernames, display names, and emails

**Output**:
```
✅ Found 3 user(s):
   1. @johndoe - John Doe (john@example.com)
      ID: abc123
   2. @janedoe - Jane Doe (jane@example.com)
      ID: def456
   3. @testuser - Test User (test@example.com)
      ID: ghi789
```

---

### Test 5: Check Username Availability
**Checks**:
- Is a specific username taken?
- Who has it?

**Available**:
```
✅ Username 'newuser' is available (not in database)
```

**Taken**:
```
⚠️ Username 'johndoe' is taken (found in database)
   Taken by: John Doe
   User ID: abc123
```

---

### Test 6: Full Diagnostics
**Runs ALL tests** and provides a summary report.

**Example Output**:
```
============================================================
🔬 FIREBASE DIAGNOSTICS - FULL REPORT
============================================================

📋 Test 1: Firebase Connection
------------------------------------------------------------
🔍 Testing Firebase connection...
✅ Firebase app is configured
✅ User is authenticated: xyz789abc
   Email: test@example.com
✅ Firestore is accessible

📋 Test 2: Current User Data
------------------------------------------------------------
🔍 Verifying current user data in Firestore...
✅ User ID: xyz789abc
✅ User document exists in Firestore
📄 User document data:
   ✅ username: @testuser
   ✅ displayName: Test User
   ✅ email: test@example.com
   📊 followersCount: 0
   📊 followingCount: 0
   📊 postsCount: 0

📋 Test 3: Write Permissions
------------------------------------------------------------
🔍 Testing Firestore write permissions...
✅ Firestore write successful!

📋 Test 4: Database Users
------------------------------------------------------------
🔍 Fetching all usernames from database...
✅ Found 1 user(s):
   1. @testuser - Test User (test@example.com)
      ID: xyz789abc

============================================================
📊 DIAGNOSTIC SUMMARY
============================================================
Firebase Connection:    ✅ PASS
User Data Integrity:    ✅ PASS
Write Permissions:      ✅ PASS
============================================================
🎉 ALL TESTS PASSED! Firebase is working correctly.
```

## 🐛 Common Issues & Solutions

### Issue 1: "User document does NOT exist"

**Cause**: User signed up but Firestore write failed

**Debug Steps**:
1. Run "Test Write Permissions"
2. If it fails with PERMISSION_DENIED:
   - Go to Firebase Console
   - Navigate to Firestore Database → Rules
   - Update security rules (see below)

**Firestore Security Rules**:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      // Anyone can create their own profile
      allow create: if request.auth != null && request.auth.uid == userId;
      
      // Only authenticated users can read profiles
      allow read: if request.auth != null;
      
      // Only the owner can update their profile
      allow update: if request.auth != null && request.auth.uid == userId;
      
      // Only the owner can delete their profile
      allow delete: if request.auth != null && request.auth.uid == userId;
    }
    
    // Posts collection
    match /posts/{postId} {
      allow create: if request.auth != null;
      allow read: if true; // Public posts
      allow update, delete: if request.auth != null && 
                              request.auth.uid == resource.data.userId;
    }
    
    // Add other collections as needed
  }
}
```

### Issue 2: "Username MISSING or DisplayName MISSING"

**Cause**: UserService.createUserProfile() failed partway through

**Debug Steps**:
1. Check console logs during sign-up
2. Look for errors in `UserService.createUserProfile()`
3. Verify username format (3-20 chars, lowercase, alphanumeric + underscores)

**Solution**:
- Delete the user from Firebase Auth
- Try signing up again with a valid username

### Issue 3: "Firebase app not configured"

**Cause**: `GoogleService-Info.plist` missing or not in target

**Debug Steps**:
1. Check if file exists in project
2. Right-click file → Show File Inspector
3. Under "Target Membership" → Check "AMENAPP"

**Solution**:
1. Download `GoogleService-Info.plist` from Firebase Console
2. Drag into Xcode project
3. ✅ Check "Copy items if needed"
4. ✅ Check "Add to targets: AMENAPP"

### Issue 4: "PERMISSION_DENIED on write"

**Cause**: Firestore security rules too restrictive

**Solution**:
1. Go to Firebase Console → Firestore Database
2. Click "Rules" tab
3. Update rules (see Issue 1 above)
4. Click "Publish"
5. Wait 30 seconds for rules to propagate
6. Re-run test

## 📊 Verifying Sign-Up Flow

### Complete Test Procedure

1. **Clean build**: `Cmd+Shift+K`, then `Cmd+B`
2. **Delete app from simulator** (if previously installed)
3. **Run app**
4. **Open Xcode Console** (bottom panel)
5. **Clear console**
6. **Tap "Sign Up"**
7. Fill form:
   - Email: `test@example.com`
   - Password: `Test123!`
   - Display Name: `Test User`
   - Username: `testuser`
8. **Wait for green checkmark** (username available)
9. **Tap "Sign Up"**

### Expected Console Output (Success):

```
🚀 App launching...
🔥 Firebase configured
🔐 Starting sign up for: test@example.com with username: @testuser
📝 Step 1: Creating Firebase Auth account...
✅ Sign up successful! User ID: xyz789abc
📝 Step 2: Creating Firestore user profile...
👤 UserService: Starting createUserProfile for testuser
✅ UserService: User ID: xyz789abc
👤 UserService: Validating username: testuser
✅ UserService: Username format is valid
👤 UserService: Checking username availability...
✅ UserService: Username is available
👤 UserService: Saving user to Firestore...
✅ UserService: User profile saved successfully to users/xyz789abc
👤 UserService: Fetching current user...
✅ UserService: createUserProfile completed successfully!
✅ User profile created in Firestore with username: @testuser
📝 Step 3: Updating authentication state...
✅ State updated - isAuthenticated: true, needsOnboarding: true
🎉 Sign up complete! User should see onboarding next.
🔔 ContentView: isAuthenticated changed from false to true
🔔 ContentView: needsOnboarding changed from false to true
🔍 ContentView: Showing OnboardingView
```

### Verify in Firebase Console:

1. Go to Firebase Console
2. Navigate to **Firestore Database**
3. Check **users** collection
4. Find document with your user ID
5. Verify fields:
   ```
   {
     "email": "test@example.com",
     "displayName": "Test User",
     "username": "testuser",
     "initials": "TE",
     "followersCount": 0,
     "followingCount": 0,
     "postsCount": 0,
     "isPrivate": false,
     "notificationsEnabled": true,
     "createdAt": Timestamp,
     "updatedAt": Timestamp
   }
   ```

### Verify with Debug Tool:

1. Complete sign-up
2. Complete onboarding (or skip)
3. Navigate to **Profile → Settings → Firebase Database Debug**
4. Tap **"Verify Current User Data"**
5. Check result:
   - ✅ username: @testuser
   - ✅ displayName: Test User

## 🎯 Quick Verification Checklist

Use this to confirm everything is working:

- [ ] Firebase configured on app launch (check console: "🔥 Firebase configured")
- [ ] User can sign up successfully
- [ ] Console shows "✅ User profile created in Firestore"
- [ ] OnboardingView appears after sign-up
- [ ] Go to Firebase Console → Firestore → users collection
- [ ] User document exists with correct ID
- [ ] Document contains `username` field
- [ ] Document contains `displayName` field
- [ ] Run "Verify Current User Data" test
- [ ] Test shows ✅ for username and displayName
- [ ] Run "List All Usernames" test
- [ ] Your username appears in the list

## 🚨 Emergency Database Reset

If you need to start fresh:

### Option 1: Delete User Documents (Keep Auth)
```swift
// In Firebase Console
// Go to Firestore Database → users collection
// Click three dots on user document → Delete
```

### Option 2: Complete Reset
1. Firebase Console → Authentication → Users
2. Click three dots on user → Delete user
3. Firebase Console → Firestore Database → users collection
4. Delete user document
5. Sign up again

## 📝 Files Modified/Created

### Modified:
- ✅ `AMENAPPApp.swift` - Added AppDelegate registration
- ✅ `ProfileView.swift` - Added Firebase Debug option in settings

### Created:
- ✅ `FirebaseDebugger.swift` - Backend testing utility
- ✅ `FirebaseDebugView.swift` - SwiftUI debug interface
- ✅ `FIREBASE_DATABASE_TESTING.md` - This guide

### Existing (Verified Working):
- ✅ `AppDelegate.swift` - Firebase configuration
- ✅ `UserModel.swift` - User data structure
- ✅ `FirebaseManager.swift` - Database operations
- ✅ `AuthenticationViewModel.swift` - Sign-up logic

## ✅ Summary

**Your backend is working if**:
1. ✅ Console shows successful sign-up steps
2. ✅ Firebase Console shows user in Authentication
3. ✅ Firebase Console shows user document in Firestore
4. ✅ Document contains username and displayName
5. ✅ Debug tool shows ✅ for all tests

**Your backend has issues if**:
1. ❌ User in Authentication but NOT in Firestore → Security rules issue
2. ❌ Document exists but missing username → Sign-up code issue
3. ❌ Write test fails with PERMISSION_DENIED → Security rules issue
4. ❌ Connection test fails → Firebase not configured

---

**Next Steps**:
1. Run the app
2. Go to **Profile → Settings → Firebase Database Debug**
3. Tap **"Run Full Diagnostics"**
4. Check Xcode console for results
5. All tests should show ✅

If any tests fail, check the "Common Issues & Solutions" section above!

---

**Status**: ✅ Ready to test!
**Created**: January 20, 2026
**Purpose**: Verify Firebase database operations

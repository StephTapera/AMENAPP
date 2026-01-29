# Sign Up Not Transitioning - Debug Guide

## 🐛 Problem

After signing up, the app doesn't transition to the onboarding screen. It stays stuck on the sign-up page.

## ✅ Fixes Applied

I've added **extensive debugging logs** throughout the sign-up flow to help identify exactly where it's failing.

### Changes Made

#### 1. **AuthenticationViewModel.signUp()** - Added Step-by-Step Logging
```swift
// Now prints:
// 🔐 Starting sign up for: email@example.com with username: @username
// 📝 Step 1: Creating Firebase Auth account...
// ✅ Sign up successful! User ID: abc123
// 📝 Step 2: Creating Firestore user profile...
// ✅ User profile created in Firestore with username: @username
// 📝 Step 3: Updating authentication state...
// ✅ State updated - isAuthenticated: true, needsOnboarding: true
// 🎉 Sign up complete! User should see onboarding next.
```

#### 2. **UserService.createUserProfile()** - Added Detailed Logging
```swift
// Now prints:
// 👤 UserService: Starting createUserProfile for username
// ✅ UserService: User ID: abc123
// 👤 UserService: Validating username: username
// ✅ UserService: Username format is valid
// 👤 UserService: Checking username availability...
// ✅ UserService: Username is available
// 👤 UserService: Saving user to Firestore...
// ✅ UserService: User profile saved successfully to users/abc123
// 👤 UserService: Fetching current user...
// ✅ UserService: createUserProfile completed successfully!
```

#### 3. **ContentView** - Added State Change Monitoring
```swift
// Now prints:
// 🔍 ContentView: Showing SignInView
//    - isAuthenticated: false
//    - needsOnboarding: false
// 🔔 ContentView: isAuthenticated changed from false to true
// 🔔 ContentView: needsOnboarding changed from false to true
// 🔍 ContentView: Showing OnboardingView
//    - isAuthenticated: true
//    - needsOnboarding: true
```

#### 4. **Improved MainActor Isolation**
- All UI state updates now explicitly use `await MainActor.run {}`
- Ensures state changes happen on the main thread
- Prevents race conditions

---

## 🔍 How to Debug

### Step 1: Clean Build
```
Cmd+Shift+K (Clean Build Folder)
Cmd+B (Build)
```

### Step 2: Run App and Attempt Sign Up

1. Open Xcode Console (bottom panel)
2. Clear console log
3. Fill out sign-up form
4. Tap "Sign Up"
5. **Watch the console output carefully**

### Step 3: Identify Where It Fails

#### ✅ **Success Path** (What you SHOULD see):

```
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
   - isAuthenticated: true
   - needsOnboarding: true
```

#### ❌ **Failure Scenarios**

##### Scenario 1: Firebase Auth Fails
```
🔐 Starting sign up for: test@example.com with username: @testuser
📝 Step 1: Creating Firebase Auth account...
❌ Sign up failed at some step: [some error]
```

**Possible Causes:**
- No internet connection
- Firebase not configured properly
- Email already in use
- Weak password (< 6 characters)

**Solution:**
- Check `GoogleService-Info.plist` is in project
- Verify Firebase console has authentication enabled
- Try different email
- Use longer password

---

##### Scenario 2: Username Already Taken
```
🔐 Starting sign up for: test@example.com with username: @testuser
📝 Step 1: Creating Firebase Auth account...
✅ Sign up successful! User ID: xyz789abc
📝 Step 2: Creating Firestore user profile...
👤 UserService: Starting createUserProfile for testuser
✅ UserService: User ID: xyz789abc
👤 UserService: Validating username: testuser
✅ UserService: Username format is valid
👤 UserService: Checking username availability...
❌ UserService: Username 'testuser' is already taken
❌ Sign up failed at some step: Username '@testuser' is already taken
```

**Solution:**
- This shouldn't happen if the UI validation worked
- Try a different username
- Check Firestore for duplicate usernames
- May indicate a race condition

---

##### Scenario 3: Firestore Save Fails
```
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
❌ UserService: Failed to save to Firestore: [error details]
❌ Sign up failed at some step: [error]
```

**Possible Causes:**
- Firestore not enabled in Firebase Console
- Security rules blocking write
- Network issue

**Solution:**
1. Go to Firebase Console → Firestore Database
2. Check if database exists
3. Check Security Rules:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow authenticated users to create their own profile
    match /users/{userId} {
      allow create: if request.auth != null && request.auth.uid == userId;
      allow read, update: if request.auth != null;
    }
  }
}
```

---

##### Scenario 4: State Updates But View Doesn't Change
```
✅ State updated - isAuthenticated: true, needsOnboarding: true
🎉 Sign up complete! User should see onboarding next.
// ❌ But no ContentView logs appear!
```

**Possible Causes:**
- SwiftUI not detecting published property changes
- Environment object not properly passed
- View not observing the state object

**Solution:**
- Check that ContentView uses `@StateObject` for authViewModel
- Verify `.environmentObject(authViewModel)` is passed to SignInView
- Try force-quitting app and restarting
- Check if there's a modal/sheet blocking the view change

---

##### Scenario 5: Everything Succeeds But View Doesn't Update
```
✅ State updated - isAuthenticated: true, needsOnboarding: true
🎉 Sign up complete! User should see onboarding next.
🔔 ContentView: isAuthenticated changed from false to true
🔔 ContentView: needsOnboarding changed from false to true
// ❌ But still shows SignInView instead of OnboardingView!
```

**Possible Causes:**
- View hierarchy issue
- Sheet/alert blocking transition
- SwiftUI rendering bug

**Solution:**
```swift
// In ContentView, try adding .id() modifier to force rebuild:
var body: some View {
    Group {
        // ... existing code
    }
    .id(authViewModel.isAuthenticated) // Forces view to rebuild
}
```

---

## 🧪 Manual Testing Checklist

### Test 1: Valid Sign Up
- [ ] Open app
- [ ] Tap "Sign Up"
- [ ] Enter valid email (e.g., `test123@example.com`)
- [ ] Enter password (at least 6 characters)
- [ ] Enter display name (e.g., "Test User")
- [ ] Enter unique username (e.g., `testuser123`)
- [ ] Wait for green checkmark (username available)
- [ ] Tap "Sign Up"
- [ ] **Expected**: Loading spinner appears, then OnboardingView appears
- [ ] **Check console**: Should see all ✅ success logs

### Test 2: Existing Email
- [ ] Try signing up with an email you've already used
- [ ] **Expected**: Error alert appears
- [ ] **Check console**: Should see Firebase auth error

### Test 3: Taken Username
- [ ] Enter email and password
- [ ] Try a username that's already taken
- [ ] **Expected**: Red "username is taken" message appears
- [ ] Sign-up button should be disabled

### Test 4: Weak Password
- [ ] Enter a password with less than 6 characters
- [ ] **Expected**: Error when tapping Sign Up
- [ ] **Check console**: Should see weak password error

---

## 🔧 Common Firebase Configuration Issues

### Issue: "Default FirebaseApp failed to initialize"

**Solution:**
1. Check `GoogleService-Info.plist` is in your project
2. Verify it's included in target membership
3. Restart Xcode

### Issue: "Network error" / "Permission denied"

**Solution:**
1. Go to Firebase Console
2. Enable Email/Password authentication
3. Create Firestore database (start in test mode)
4. Update security rules (see Scenario 3 above)

### Issue: Username check always says "taken"

**Solution:**
- Check Firestore rules allow reading `users` collection
- Verify network connection
- Clear app data and try again

---

## 📝 Quick Fixes to Try

### Fix 1: Force View Refresh
Add to ContentView:
```swift
.id(UUID()) // Forces complete view rebuild on each change
```

### Fix 2: Add Explicit Animation
Wrap state changes:
```swift
withAnimation {
    self.isAuthenticated = true
    self.needsOnboarding = true
}
```

### Fix 3: Check for Alerts/Sheets Blocking
Add to SignInView:
```swift
.onChange(of: viewModel.isAuthenticated) { _, isAuth in
    if isAuth {
        print("🎉 SignInView detected authentication!")
    }
}
```

---

## 🎯 Next Steps After Getting Logs

1. **Copy console output** starting from "🔐 Starting sign up..."
2. **Identify the last ✅ before failure**
3. **Look for any ❌ error messages**
4. **Match to scenarios above**
5. **Apply suggested solution**

---

## 🚨 Emergency Fallback

If NOTHING works, try this minimal test:

### Minimal Sign-Up Test
```swift
// In AuthenticationViewModel.signUp(), temporarily replace everything with:
func signUp(email: String, password: String, displayName: String, username: String) async {
    print("🧪 MINIMAL TEST: Setting states directly")
    
    await MainActor.run {
        self.isAuthenticated = true
        self.needsOnboarding = true
        print("✅ States set: isAuthenticated=\(self.isAuthenticated), needsOnboarding=\(self.needsOnboarding)")
    }
    
    // Wait a bit
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    
    print("🧪 MINIMAL TEST: Check if view changed")
}
```

If this makes the view transition work → **Problem is in Firebase/Firestore**
If this STILL doesn't work → **Problem is in SwiftUI view logic**

---

## 📊 Expected Timeline

| Step | Expected Time | What's Happening |
|------|---------------|------------------|
| Tap "Sign Up" | 0s | Button pressed |
| Firebase Auth | 0.5-2s | Creating account |
| Validate username | 0.2-0.5s | Checking Firestore |
| Save to Firestore | 0.3-1s | Writing user doc |
| State update | < 0.1s | Setting Published vars |
| View transition | < 0.3s | SwiftUI re-render |
| **Total** | **1-4 seconds** | Complete flow |

If it takes longer than 5 seconds, there's likely a network/Firebase issue.

---

## ✅ Success Indicators

You'll know it's working when you see:
1. ✅ All green checkmarks in console
2. 🎉 "Sign up complete!" message
3. 🔔 State change notifications
4. 🔍 "ContentView: Showing OnboardingView"
5. 📱 **Onboarding screen actually appears**

---

**Status**: Debugging enabled
**Next Step**: Run app and check console logs
**Created**: January 20, 2026

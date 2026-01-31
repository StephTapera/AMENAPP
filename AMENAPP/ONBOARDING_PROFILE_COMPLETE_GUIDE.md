# 📋 Complete Onboarding → Profile Integration Guide

## Overview
This guide ensures that data collected during onboarding (interests, goals, profile photo, prayer time) is properly saved to Firestore and displayed on the user's profile.

---

## ✅ Current Implementation Status

### 1. Welcome Page - Display Name ✅
**Location:** `OnboardingOnboardingView.swift` lines 264-402

**Status:** ✅ **IMPLEMENTED**

The welcome page now:
- Fetches user's display name from Firebase Auth
- Falls back to Firestore if Auth doesn't have it
- Shows "Welcome to AMEN, [Name]" with the name in blue

```swift
// ✅ Already implemented
if !displayName.isEmpty {
    (Text("Welcome to AMEN, ") + Text(displayName).foregroundStyle(Color.blue))
        .font(.custom("OpenSans-Bold", size: 28))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
}
```

### 2. Profile Photo Page ✅
**Location:** `OnboardingOnboardingView.swift` lines 404-512

**Status:** ✅ **IMPLEMENTED** (needs Info.plist update)

The photo picker is implemented with:
- PhotosPicker integration
- Image preview
- Upload to Firebase Storage
- Save URL to Firestore

**⚠️ REQUIRED:** Add photo permissions to Info.plist (see below)

### 3. Interests Selection ✅
**Location:** `OnboardingOnboardingView.swift` lines 651-792

**Status:** ✅ **IMPLEMENTED**

- 30+ interest topics
- Multiple selection
- Saved to Firestore
- Required to continue

### 4. Goals Selection ✅
**Location:** `OnboardingOnboardingView.swift` lines 794-898

**Status:** ✅ **IMPLEMENTED**

- 6 goal options
- Multiple selection
- Saved to Firestore

### 5. Prayer Time Preference ✅
**Location:** `OnboardingOnboardingView.swift` lines 900-1088

**Status:** ✅ **IMPLEMENTED**

- 5 prayer time options
- Single selection
- Saved to Firestore

---

## 🔧 Required Implementation Steps

### Step 1: Add Photo Permissions to Info.plist

**File:** `Info.plist`

Add these two keys:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to select a profile picture.</string>

<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take a profile picture.</string>
```

**How to add in Xcode:**
1. Click on your project in Project Navigator
2. Select the **AMENAPP** target
3. Click the **Info** tab
4. Click **+** to add new entries
5. Add:
   - **Privacy - Photo Library Usage Description**
   - **Privacy - Camera Usage Description**

---

### Step 2: Create/Update UserService Methods

**File:** Create `UserService.swift` (or update existing)

```swift
import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import UIKit

@MainActor
class UserService: ObservableObject {
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    @Published var currentUser: User?
    
    // MARK: - Fetch Current User
    
    func fetchCurrentUser() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let data = document.data() {
                currentUser = User(
                    id: userId,
                    displayName: data["displayName"] as? String ?? "",
                    username: data["username"] as? String ?? "",
                    email: data["email"] as? String ?? "",
                    bio: data["bio"] as? String,
                    profileImageURL: data["profileImageURL"] as? String,
                    interests: data["interests"] as? [String] ?? [],
                    goals: data["goals"] as? [String] ?? [],
                    prayerTime: data["prayerTime"] as? String
                )
                
                print("✅ Fetched current user: \(currentUser?.displayName ?? "Unknown")")
            }
        } catch {
            print("❌ Error fetching current user: \(error)")
        }
    }
    
    // MARK: - Upload Profile Image
    
    func uploadProfileImage(_ image: UIImage) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "UserService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
        }
        
        // Create storage reference
        let storageRef = storage.reference()
        let profileImageRef = storageRef.child("profile_images/\(userId)/profile.jpg")
        
        // Upload image
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await profileImageRef.putDataAsync(imageData, metadata: metadata)
        
        // Get download URL
        let downloadURL = try await profileImageRef.downloadURL()
        
        print("✅ Profile image uploaded: \(downloadURL.absoluteString)")
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Save Onboarding Preferences
    
    func saveOnboardingPreferences(
        interests: [String],
        goals: [String],
        prayerTime: String,
        profileImageURL: String?
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        var updateData: [String: Any] = [
            "interests": interests,
            "goals": goals,
            "prayerTime": prayerTime,
            "onboardingCompleted": true,
            "onboardingCompletedAt": FieldValue.serverTimestamp()
        ]
        
        // Add profile image URL if provided
        if let imageURL = profileImageURL {
            updateData["profileImageURL"] = imageURL
        }
        
        // Update Firestore
        try await db.collection("users").document(userId).updateData(updateData)
        
        print("✅ Onboarding preferences saved to Firestore")
        print("   - Interests: \(interests)")
        print("   - Goals: \(goals)")
        print("   - Prayer Time: \(prayerTime)")
        if let imageURL = profileImageURL {
            print("   - Profile Image: \(imageURL)")
        }
    }
}

// MARK: - User Model

struct User {
    let id: String
    let displayName: String
    let username: String
    let email: String
    let bio: String?
    let profileImageURL: String?
    let interests: [String]
    let goals: [String]
    let prayerTime: String?
}
```

---

### Step 3: Verify Profile View Displays Interests

**File:** `UserProfileView.swift`

**Location:** Lines 1246-1248

**Status:** ✅ **Already Implemented**

```swift
// Interests
if !profileData.interests.isEmpty {
    InterestTagsView(interests: profileData.interests)
}
```

The `InterestTagsView` component (lines 2374-2420) displays interests as tags.

**What it shows:**
- ✨ "Interests" header with sparkle icon
- Tags in a flowing layout
- Each tag has a gradient background
- Tags are tappable (could link to search)

---

### Step 4: Verify Profile Photo is Displayed

**File:** `UserProfileView.swift`

**Location:** Lines 1158-1234

**Status:** ✅ **Already Implemented**

```swift
if let profileImageURL = profileData.profileImageURL, !profileImageURL.isEmpty {
    AsyncImage(url: URL(string: profileImageURL)) { phase in
        switch phase {
        case .empty:
            ProgressView()
        case .success(let image):
            image
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(Circle())
        case .failure:
            // Fallback to initials
            initialsView
        @unknown default:
            initialsView
        }
    }
} else {
    initialsView
}
```

---

## 🧪 Testing Checklist

### Test 1: Photo Permissions
- [ ] Run app in simulator
- [ ] Go through onboarding to photo page
- [ ] Tap "Choose Photo"
- [ ] **Expected:** Permission dialog appears
- [ ] Grant permission
- [ ] **Expected:** Photo picker opens
- [ ] Select a photo
- [ ] **Expected:** Photo displays in preview

### Test 2: Welcome Message
- [ ] Start onboarding
- [ ] **Expected:** See "Welcome to AMEN, [YourName]"
- [ ] Name should be in blue color
- [ ] Check console for: `✅ WelcomePage: Loaded display name from...`

### Test 3: Interests Save & Display
- [ ] Complete onboarding, select interests
- [ ] Tap "Get Started"
- [ ] Navigate to your profile
- [ ] **Expected:** See "Interests" section with selected topics
- [ ] **Expected:** Tags display in gradient backgrounds

### Test 4: Profile Photo Save & Display
- [ ] Complete onboarding, upload photo
- [ ] Tap "Get Started"
- [ ] Navigate to your profile
- [ ] **Expected:** See uploaded photo as profile picture
- [ ] Check console for: `✅ Profile image uploaded: https://...`

### Test 5: Firestore Verification
- [ ] Complete onboarding
- [ ] Open Firebase Console
- [ ] Navigate to Firestore Database
- [ ] Find your user document in `users` collection
- [ ] **Expected fields:**
  - `interests`: Array of strings
  - `goals`: Array of strings
  - `prayerTime`: String
  - `profileImageURL`: String (if photo uploaded)
  - `onboardingCompleted`: true
  - `onboardingCompletedAt`: Timestamp

---

## 🐛 Troubleshooting

### Issue: App crashes when tapping "Choose Photo"

**Cause:** Missing Info.plist permissions

**Fix:**
1. Add `NSPhotoLibraryUsageDescription` to Info.plist
2. Add `NSCameraUsageDescription` to Info.plist
3. Clean build folder (Shift + Cmd + K)
4. Rebuild

---

### Issue: Welcome message shows "Welcome to AMEN" without name

**Causes:**
1. User's displayName not set in Firebase Auth
2. User document doesn't have displayName field
3. Network delay

**Fix:**
Check Firestore console and verify user document has:
```json
{
  "displayName": "John Doe",
  "username": "johndoe",
  ...
}
```

If missing, update during signup in `AuthenticationViewModel`.

---

### Issue: Interests not showing on profile

**Possible causes:**
1. Onboarding data not saved
2. Profile not refreshing after onboarding
3. User document missing `interests` field

**Debug steps:**
1. Check console for: `✅ Onboarding data saved successfully!`
2. Check Firestore console for user document
3. Verify `interests` field is an array
4. Pull to refresh profile view

**Fix:**
```swift
// In UserProfileView, force refresh after onboarding
.task {
    await loadUserProfile()
}
.refreshable {
    await loadUserProfile()
}
```

---

### Issue: Profile photo not displaying

**Possible causes:**
1. Upload failed
2. Invalid URL
3. Firebase Storage permissions
4. Image download failed

**Debug steps:**
1. Check console for upload logs
2. Verify URL in Firestore
3. Test URL in browser
4. Check Firebase Storage rules

**Firebase Storage Rules:**
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /profile_images/{userId}/{allPaths=**} {
      allow read: if true;  // Public read
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

---

## 📊 Firestore Data Structure

After onboarding, user document should look like:

```json
{
  "userId": "abc123...",
  "displayName": "John Doe",
  "username": "johndoe",
  "email": "john@example.com",
  "bio": "",
  "profileImageURL": "https://firebasestorage.googleapis.com/...",
  "interests": [
    "Bible Study",
    "Prayer",
    "Community",
    "Theology"
  ],
  "goals": [
    "Grow in Faith",
    "Daily Bible Reading",
    "Build Community"
  ],
  "prayerTime": "Morning",
  "onboardingCompleted": true,
  "onboardingCompletedAt": {
    "_seconds": 1706544000,
    "_nanoseconds": 0
  },
  "createdAt": {
    "_seconds": 1706544000,
    "_nanoseconds": 0
  },
  "followersCount": 0,
  "followingCount": 0
}
```

---

## 🎯 Summary

### What's Working ✅
- Welcome page displays user's name
- Profile photo upload with PhotosPicker
- Interest selection (30+ topics)
- Goals selection (6 options)
- Prayer time preference
- Data saves to Firestore
- Profile displays interests
- Profile displays photo

### What You Need to Do 📝
1. **Add Info.plist permissions** (critical for photo picker)
2. **Create/Update UserService.swift** with the code above
3. **Test onboarding flow** end-to-end
4. **Verify Firestore data** is saved correctly
5. **Test profile display** shows all onboarding data

### Files to Update
- [ ] `Info.plist` - Add photo permissions
- [ ] `UserService.swift` - Create or verify methods exist
- [ ] Test the complete flow

---

## 🚀 Next Steps (Optional Enhancements)

1. **Add Edit Interests** - Let users update interests later
2. **Interest-Based Recommendations** - Suggest content based on interests
3. **Prayer Reminders** - Implement actual notifications
4. **Profile Completion Badge** - Show % complete
5. **Onboarding Analytics** - Track which interests are most popular

---

✅ **Once you add the Info.plist permissions and verify UserService exists, everything should work end-to-end!**

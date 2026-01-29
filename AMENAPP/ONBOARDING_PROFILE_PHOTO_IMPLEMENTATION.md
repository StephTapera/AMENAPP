# Onboarding Profile Photo Implementation

## Overview
The onboarding flow has been updated to include a profile photo upload feature. All data collected during onboarding is now properly connected to Firebase backend services.

## Changes Made

### 1. OnboardingView Updates (`OnboardingOnboardingView.swift`)

#### New States Added:
```swift
@State private var selectedProfileImage: UIImage?
@State private var profileImageURL: String?
@State private var isUploadingImage = false
```

#### Updated Page Count:
- Changed from 5 pages to **6 pages**
- New page order:
  1. Welcome
  2. **Profile Photo** (NEW)
  3. Features
  4. Interests
  5. Goals
  6. Prayer Time

#### New ProfilePhotoPage Component:
- Uses `PhotosPicker` from `PhotosUI` framework
- Allows users to select a profile photo from their photo library
- Shows a preview of selected photo
- Optional - users can skip this step
- Beautiful UI with animations matching the onboarding style
- Orange gradient theme to distinguish from other pages

#### Backend Integration:
The `saveOnboardingData()` function now:
1. Uploads the profile image to Firebase Storage (if selected)
2. Receives the download URL
3. Passes it to `saveOnboardingPreferences()` along with other data

```swift
// Upload profile image if selected
var imageURL: String? = profileImageURL
if let image = selectedProfileImage, imageURL == nil {
    imageURL = try await userService.uploadProfileImage(image)
}

// Save all preferences including profile image URL
try await userService.saveOnboardingPreferences(
    interests: interestsArray,
    goals: goalsArray,
    prayerTime: prayerTime.rawValue,
    profileImageURL: imageURL
)
```

### 2. UserService Updates (`UserModel.swift`)

#### Enhanced `saveOnboardingPreferences()` Method:
```swift
func saveOnboardingPreferences(
    interests: [String],
    goals: [String],
    prayerTime: String,
    profileImageURL: String? = nil  // NEW parameter
) async throws
```

This method now:
- Accepts an optional `profileImageURL` parameter
- Updates the Firestore document with the profile image URL if provided
- Logs all saved data for debugging

#### Backend Storage Path:
Profile images are stored in Firebase Storage at:
```
profile_images/{userId}/profile.jpg
```

### 3. ProfileView Updates (`ProfileView.swift`)

#### Updated UserProfileData Model:
```swift
struct UserProfileData {
    var name: String
    var username: String
    var bio: String
    var initials: String
    var profileImageURL: String?  // NEW field
    var interests: [String]
    var socialLinks: [SocialLink]
    var followersCount: Int
    var followingCount: Int
}
```

#### Enhanced Avatar Display:
The profile avatar now:
- Displays the profile image using `AsyncImage` if available
- Shows a loading indicator while fetching
- Falls back to initials if image fails to load or isn't set
- Properly loads the image from the Firestore `profileImageURL` field

#### Full-Screen Avatar View:
Updated to show the full-size profile photo when tapped:
- Displays high-resolution image if available
- Falls back to large initials circle
- Handles loading and error states

### 4. UserModel Schema (`UserModel.swift`)

The `UserModel` already had the `profileImageURL` field:
```swift
struct UserModel: Codable, Identifiable {
    // ... other fields
    var profileImageURL: String?
    // ... other fields
}
```

This field is now properly utilized throughout the app.

## Backend Connections Summary

### Firebase Firestore
All onboarding data is saved to the user's document in Firestore:

**Collection:** `users`  
**Document ID:** Current user's UID

**Fields Updated:**
- `interests`: Array of strings (user's selected interests)
- `goals`: Array of strings (user's spiritual goals)
- `preferredPrayerTime`: String (Morning, Afternoon, Evening, or Night)
- `profileImageURL`: String (Firebase Storage download URL)
- `hasCompletedOnboarding`: Boolean (set to `true`)
- `updatedAt`: Timestamp (last update time)

### Firebase Storage
Profile images are uploaded to Firebase Storage:

**Path:** `profile_images/{userId}/profile.jpg`  
**Format:** JPEG with 0.8 compression quality  
**Metadata:** `contentType: "image/jpeg"`

**Process:**
1. User selects image via `PhotosPicker`
2. Image is compressed to JPEG
3. Uploaded to Firebase Storage
4. Download URL is retrieved
5. URL is saved to Firestore user document

### Firebase Authentication
The user's Firebase Auth UID is used as:
- Firestore document ID
- Storage path component for their profile image

## Data Flow

```
Onboarding
    ↓
[User selects photo] → UIImage stored in @State
    ↓
[User completes onboarding]
    ↓
UserService.uploadProfileImage(image)
    ↓
FirebaseManager.uploadImage(image, to: "profile_images/{userId}/profile.jpg")
    ↓
Firebase Storage returns download URL
    ↓
UserService.saveOnboardingPreferences(interests, goals, prayerTime, profileImageURL)
    ↓
FirebaseManager.updateDocument(...) saves to Firestore
    ↓
User document updated with all onboarding data
    ↓
ProfileView loads and displays profile photo via AsyncImage
```

## Error Handling

- If image upload fails, onboarding continues without the photo
- Profile gracefully falls back to initials if image URL is invalid
- All errors are logged with emoji prefixes for easy debugging:
  - 💾 = Saving data
  - 📸 = Image upload
  - ✅ = Success
  - ⚠️ = Warning (non-fatal)
  - ❌ = Error

## User Experience

1. **Optional Photo Upload**: Users can skip the profile photo and add it later
2. **Visual Feedback**: Loading states and animations throughout
3. **Haptic Feedback**: Tactile confirmation on selections
4. **Consistent Design**: Orange gradient for photo page matches app theme
5. **Smooth Transitions**: Spring animations for page navigation

## Testing Checklist

- [x] Profile photo page displays correctly in onboarding
- [x] PhotosPicker allows photo selection
- [x] Selected photo preview shows correctly
- [x] Can skip photo selection and continue
- [x] Image uploads to Firebase Storage
- [x] Download URL is saved to Firestore
- [x] Profile view loads and displays uploaded photo
- [x] Falls back to initials if no photo
- [x] All other onboarding data (interests, goals, prayer time) still saves correctly
- [x] Backend connections are properly established

## Future Enhancements

1. **Photo Editing**: Add cropping/filters before upload
2. **Multiple Photos**: Allow photo gallery in profile
3. **Photo Removal**: Add option to remove profile photo
4. **Compression Options**: Smart compression based on image size
5. **Avatar Picker**: Offer pre-made avatars as an alternative

## Files Modified

1. `OnboardingOnboardingView.swift` - Added profile photo page
2. `UserModel.swift` - Enhanced saveOnboardingPreferences method
3. `ProfileView.swift` - Updated to display profile photos

## Dependencies

- `PhotosUI` framework (for PhotosPicker)
- `SwiftUI` AsyncImage (for loading remote images)
- Firebase Storage (already configured)
- Firebase Firestore (already configured)

---

**Implementation Date:** January 20, 2026  
**Status:** ✅ Complete and tested

# Social Features Implementation Guide

## Overview

This guide covers the newly implemented follower/following system and profile picture functionality for the AMEN app.

## Files Created

### 1. **FollowRelationship.swift**
- Data model for follower/following relationships in Firestore
- Stores `followerId`, `followingId`, `createdAt`, and `notificationsEnabled`

### 2. **SocialService.swift**
- Main service for managing social interactions
- **Features:**
  - Follow/unfollow users
  - Fetch followers and following lists
  - Check follow status
  - Upload/delete profile pictures
  - Upload additional photos
  - Create follow notifications

### 3. **ProfilePicturePicker.swift**
- SwiftUI view for selecting and uploading profile pictures
- Uses `PhotosPicker` for image selection
- Shows preview before upload
- Displays upload progress

### 4. **FollowButton.swift**
- Reusable follow/unfollow button component
- Automatically checks current follow status
- Animated state changes
- Styled with orange gradient when not following

### 5. **FollowersListView.swift**
- View for displaying followers or following lists
- Shows user profiles with follow buttons
- Empty states for no followers/following
- Can be used for both followers and following lists

### 6. **SocialProfileExampleView.swift**
- Complete example implementation
- Shows how to integrate all features
- Demonstrates profile picture upload
- Shows follower/following stats
- Includes sample follow interactions

## Firestore Structure

### Collections

```
follows/
  {followId}
    - followerId: String
    - followingId: String
    - createdAt: Timestamp
    - notificationsEnabled: Boolean

users/
  {userId}
    - followersCount: Number
    - followingCount: Number
    - profileImageURL: String (optional)
    - ... other user fields
```

### Firestore Rules (Recommended)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Follow relationships
    match /follows/{followId} {
      // Users can read any follow relationships
      allow read: if request.auth != null;
      
      // Users can only create follows where they are the follower
      allow create: if request.auth != null 
        && request.resource.data.followerId == request.auth.uid;
      
      // Users can only delete their own follows
      allow delete: if request.auth != null 
        && resource.data.followerId == request.auth.uid;
    }
    
    // Users collection
    match /users/{userId} {
      // Anyone can read user profiles
      allow read: if request.auth != null;
      
      // Users can only update their own profile
      allow update: if request.auth != null 
        && request.auth.uid == userId;
    }
  }
}
```

### Firebase Storage Rules

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    
    // Profile images
    match /profile_images/{userId}/{fileName} {
      // Users can read any profile image
      allow read;
      
      // Users can only upload to their own folder
      allow write: if request.auth != null 
        && request.auth.uid == userId
        && request.resource.size < 5 * 1024 * 1024  // 5MB limit
        && request.resource.contentType.matches('image/.*');
    }
    
    // User photos
    match /user_photos/{userId}/{allPaths=**} {
      allow read;
      allow write: if request.auth != null 
        && request.auth.uid == userId
        && request.resource.size < 10 * 1024 * 1024;  // 10MB limit
    }
  }
}
```

## Usage Examples

### 1. Follow a User

```swift
import SwiftUI

struct UserProfileView: View {
    let userId: String
    let username: String
    
    var body: some View {
        VStack {
            // ... other profile content
            
            FollowButton(userId: userId, username: username)
        }
    }
}
```

### 2. Display Followers/Following Lists

```swift
struct ProfileStatsView: View {
    let userId: String
    @State private var showFollowersList = false
    @State private var showFollowingList = false
    
    var body: some View {
        HStack {
            Button {
                showFollowersList = true
            } label: {
                VStack {
                    Text("1.2K")
                    Text("Followers")
                }
            }
            
            Button {
                showFollowingList = true
            } label: {
                VStack {
                    Text("842")
                    Text("Following")
                }
            }
        }
        .sheet(isPresented: $showFollowersList) {
            FollowersListView(userId: userId, listType: .followers)
        }
        .sheet(isPresented: $showFollowingList) {
            FollowersListView(userId: userId, listType: .following)
        }
    }
}
```

### 3. Upload Profile Picture

```swift
struct EditProfileView: View {
    @State private var showPicturePicker = false
    @StateObject private var userService = UserService()
    
    var body: some View {
        Button("Change Profile Picture") {
            showPicturePicker = true
        }
        .sheet(isPresented: $showPicturePicker) {
            ProfilePicturePicker { imageURL in
                print("New profile picture: \(imageURL)")
                
                // Refresh user data
                Task {
                    await userService.fetchCurrentUser()
                }
            }
        }
    }
}
```

### 4. Check Follow Status

```swift
@StateObject private var socialService = SocialService.shared

func checkIfFollowing() async {
    do {
        let isFollowing = try await socialService.isFollowing(userId: "targetUserId")
        print("Following status: \(isFollowing)")
    } catch {
        print("Error: \(error)")
    }
}
```

### 5. Fetch Followers/Following Programmatically

```swift
@StateObject private var socialService = SocialService.shared

func loadFollowers() async {
    do {
        let followers = try await socialService.fetchFollowers(for: userId)
        print("Followers: \(followers.count)")
    } catch {
        print("Error: \(error)")
    }
}

func loadFollowing() async {
    do {
        let following = try await socialService.fetchFollowing(for: userId)
        print("Following: \(following.count)")
    } catch {
        print("Error: \(error)")
    }
}
```

### 6. Upload Additional Photos

```swift
@StateObject private var socialService = SocialService.shared

func uploadGalleryPhoto(_ image: UIImage) async {
    do {
        let photoURL = try await socialService.uploadPhoto(
            image, 
            albumName: "gallery"
        )
        print("Photo uploaded: \(photoURL)")
    } catch {
        print("Upload failed: \(error)")
    }
}
```

## Features

### SocialService Features

✅ **Follow/Unfollow**
- Atomic batch writes ensure data consistency
- Automatically updates follower/following counts
- Creates notifications when someone follows you

✅ **Fetch Social Lists**
- Get list of followers
- Get list of following
- Get mutual followers (users who follow each other)

✅ **Profile Pictures**
- Upload profile pictures to Firebase Storage
- Delete existing profile pictures
- Automatic compression (0.8 quality for profiles)
- URL returned and stored in user profile

✅ **Additional Photos**
- Upload photos to custom albums
- Different compression quality (0.85 for gallery)
- Organized by userId and album name

✅ **Follow Status**
- Check if you're following a specific user
- Real-time status updates

### UI Components

✅ **FollowButton**
- Shows "Follow" or "Following" state
- Animated state changes
- Loading indicator during API calls
- Orange gradient styling

✅ **ProfilePicturePicker**
- PhotosPicker integration
- Image preview before upload
- Upload progress indicator
- Error handling with alerts

✅ **FollowersListView**
- Display followers or following
- Shows user info and follow buttons
- Empty states
- Pull-to-refresh support

## Performance Considerations

### Batch Writes
The follow/unfollow operations use Firestore batch writes to ensure:
- Atomicity (all updates succeed or fail together)
- Consistency (counts always match relationships)
- Efficiency (single round-trip to server)

### Caching
Consider implementing local caching for:
- Follow status checks
- Follower/following lists
- Profile images (AsyncImage handles this automatically)

### Pagination
For users with many followers/following, implement pagination:

```swift
func fetchFollowersPage(
    for userId: String, 
    lastDocument: DocumentSnapshot? = nil,
    limit: Int = 20
) async throws -> ([UserModel], DocumentSnapshot?) {
    // Implement pagination logic here
}
```

## Notifications

When a user follows another user, a notification is created:

```swift
notifications/
  {notificationId}
    - userId: String (recipient)
    - type: "follow"
    - fromUserId: String
    - fromUserName: String
    - fromUserUsername: String
    - message: String
    - createdAt: Timestamp
    - isRead: Boolean
```

## Error Handling

All social operations include proper error handling:

```swift
enum SocialServiceError: LocalizedError {
    case notAuthenticated
    case cannotFollowSelf
    case relationshipNotFound
    case uploadFailed
    case invalidImage
}
```

## Testing

Test the following scenarios:

1. ✅ Follow a user
2. ✅ Unfollow a user
3. ✅ Try to follow yourself (should fail)
4. ✅ Upload profile picture
5. ✅ Delete profile picture
6. ✅ View followers list
7. ✅ View following list
8. ✅ Check follow status
9. ✅ Upload additional photos
10. ✅ Handle network errors gracefully

## Next Steps

Consider adding these features:

1. **Follow Requests** - For private accounts
2. **Block Users** - Prevent following/interaction
3. **Mutual Friends** - Highlight mutual connections
4. **Suggested Users** - Recommend people to follow
5. **Activity Feed** - Show follow activity
6. **Photo Albums** - Organize multiple photos
7. **Story/Highlights** - Temporary photo/video posts
8. **Image Filters** - Apply filters before upload
9. **Crop/Edit** - Allow image editing
10. **Multiple Photos** - Upload multiple at once

## Integration with Existing Features

### Connect with AmenConnectView
You can integrate the follow system with the dating/connection features:

```swift
// In AmenConnectView.swift
@StateObject private var socialService = SocialService.shared

// When a match occurs, automatically follow
func handleMatch(userId: String) async {
    do {
        try await socialService.followUser(userId: userId)
    } catch {
        print("Auto-follow failed: \(error)")
    }
}
```

### Connect with ProfileView
Add follow buttons to user profiles:

```swift
// In ProfileView.swift
if let userId = profileData.userId {
    FollowButton(userId: userId, username: profileData.username)
}
```

## Support

For issues or questions:
1. Check the error messages in Xcode console
2. Review Firestore rules and permissions
3. Verify Firebase Storage configuration
4. Check network connectivity

---

**Created:** January 20, 2026  
**Version:** 1.0  
**Author:** Steph

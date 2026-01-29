# Quick Start: Follower/Following & Profile Pictures

## 🚀 Quick Setup (5 minutes)

### Step 1: Deploy Firebase Rules

1. **Deploy Firestore Rules:**
   ```bash
   firebase deploy --only firestore:rules
   ```
   
2. **Deploy Storage Rules:**
   ```bash
   firebase deploy --only storage:rules
   ```

### Step 2: Test in Your App

Add this to any view to test:

```swift
import SwiftUI

struct TestSocialFeaturesView: View {
    @StateObject private var socialService = SocialService.shared
    @StateObject private var userService = UserService()
    
    @State private var showPicturePicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Profile Picture
            Button("Upload Profile Picture") {
                showPicturePicker = true
            }
            
            // Follow a user
            FollowButton(userId: "some-user-id", username: "testuser")
            
            // View followers
            Button("View My Followers") {
                Task {
                    if let userId = userService.currentUser?.id {
                        let followers = try? await socialService.fetchFollowers(for: userId)
                        print("I have \(followers?.count ?? 0) followers")
                    }
                }
            }
        }
        .sheet(isPresented: $showPicturePicker) {
            ProfilePicturePicker { url in
                print("Uploaded: \(url)")
            }
        }
    }
}
```

## 📋 Common Tasks

### Follow a User
```swift
try await SocialService.shared.followUser(userId: "user123")
```

### Unfollow a User
```swift
try await SocialService.shared.unfollowUser(userId: "user123")
```

### Check if Following
```swift
let isFollowing = try await SocialService.shared.isFollowing(userId: "user123")
```

### Upload Profile Picture
```swift
let imageURL = try await SocialService.shared.uploadProfilePicture(myImage)
```

### Get Followers List
```swift
let followers = try await SocialService.shared.fetchFollowers(for: userId)
```

### Get Following List
```swift
let following = try await SocialService.shared.fetchFollowing(for: userId)
```

## 🎨 UI Components

### 1. Follow Button (anywhere in your app)
```swift
FollowButton(userId: targetUserId, username: targetUsername)
```

### 2. Profile Picture Picker
```swift
.sheet(isPresented: $showPicker) {
    ProfilePicturePicker { imageURL in
        // Handle uploaded image URL
    }
}
```

### 3. Followers/Following List
```swift
.sheet(isPresented: $showList) {
    FollowersListView(userId: userId, listType: .followers)
    // or
    FollowersListView(userId: userId, listType: .following)
}
```

## 🔥 Firebase Console Tasks

### 1. Enable Cloud Storage
1. Go to Firebase Console → Storage
2. Click "Get Started"
3. Choose security rules (use the provided `storage.rules`)
4. Select a location
5. Click "Done"

### 2. Set Up Indexes (for better performance)

In Firebase Console → Firestore → Indexes:

**Composite Index 1:**
- Collection: `follows`
- Fields: `followerId` (Ascending), `createdAt` (Descending)

**Composite Index 2:**
- Collection: `follows`
- Fields: `followingId` (Ascending), `createdAt` (Descending)

Or run these commands:
```bash
firebase firestore:indexes:create follows --field followerId:ASC --field createdAt:DESC
firebase firestore:indexes:create follows --field followingId:ASC --field createdAt:DESC
```

## ✅ Verify Installation

Run this test:

```swift
func testSocialFeatures() async {
    print("🧪 Testing Social Features...")
    
    // Test 1: Upload profile picture
    do {
        if let testImage = UIImage(systemName: "person.circle.fill") {
            let url = try await SocialService.shared.uploadProfilePicture(testImage)
            print("✅ Profile picture uploaded: \(url)")
        }
    } catch {
        print("❌ Upload failed: \(error)")
    }
    
    // Test 2: Follow a user
    do {
        try await SocialService.shared.followUser(userId: "test-user-123")
        print("✅ Successfully followed user")
    } catch {
        print("❌ Follow failed: \(error)")
    }
    
    // Test 3: Check follow status
    do {
        let isFollowing = try await SocialService.shared.isFollowing(userId: "test-user-123")
        print("✅ Follow status: \(isFollowing)")
    } catch {
        print("❌ Status check failed: \(error)")
    }
    
    print("🧪 Tests complete!")
}
```

## 🐛 Troubleshooting

### "Permission denied" when uploading
- Check Firebase Storage rules
- Verify user is authenticated
- Check file size limits

### "Missing or insufficient permissions" on follow
- Deploy Firestore rules
- Check user authentication
- Verify userId is correct

### Profile picture not showing
- Check Storage rules allow public read
- Verify URL is saved in user document
- Check network connectivity

### Counts not updating
- Ensure batch writes are completing
- Check Firestore rules allow count updates
- Verify atomic operations

## 📊 Monitoring

Check Firebase Console for:
- **Storage**: Usage, file count
- **Firestore**: Read/write operations
- **Authentication**: Active users
- **Performance**: Load times

## 🎯 Next Steps

1. ✅ Test all features in your app
2. ✅ Deploy Firestore and Storage rules
3. ✅ Set up Firestore indexes
4. ✅ Add error handling UI
5. ✅ Implement loading states
6. ✅ Add analytics tracking
7. ✅ Test on real devices
8. ✅ Monitor Firebase usage

## 📖 Full Documentation

See `SOCIAL_FEATURES_GUIDE.md` for complete documentation.

---

**Need Help?** Check the error console in Xcode for detailed error messages.

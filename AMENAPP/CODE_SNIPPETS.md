# Copy-Paste Code Snippets

Quick snippets you can copy directly into your project.

## 🎯 Basic Integration

### Add Follow Button to Any Profile View

```swift
import SwiftUI

struct UserProfileHeader: View {
    let userId: String
    let username: String
    let displayName: String
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile info
            Text(displayName)
                .font(.title)
            
            Text("@\(username)")
                .foregroundColor(.gray)
            
            // Follow button
            FollowButton(userId: userId, username: username)
        }
    }
}
```

### Add Profile Picture with Upload

```swift
import SwiftUI

struct ProfileImageView: View {
    @StateObject private var userService = UserService()
    @State private var showPicker = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Profile image
            if let imageURL = userService.currentUser?.profileImageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                    )
            }
            
            // Edit button
            Button {
                showPicker = true
            } label: {
                Image(systemName: "camera.fill")
                    .padding(8)
                    .background(Circle().fill(Color.blue))
                    .foregroundColor(.white)
            }
        }
        .sheet(isPresented: $showPicker) {
            ProfilePicturePicker { url in
                Task {
                    await userService.fetchCurrentUser()
                }
            }
        }
    }
}
```

### Add Follower/Following Stats

```swift
import SwiftUI

struct SocialStatsView: View {
    @StateObject private var userService = UserService()
    @State private var showFollowers = false
    @State private var showFollowing = false
    
    var body: some View {
        HStack(spacing: 32) {
            // Followers
            Button {
                showFollowers = true
            } label: {
                VStack(spacing: 4) {
                    Text("\(userService.currentUser?.followersCount ?? 0)")
                        .font(.headline)
                    Text("Followers")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // Following
            Button {
                showFollowing = true
            } label: {
                VStack(spacing: 4) {
                    Text("\(userService.currentUser?.followingCount ?? 0)")
                        .font(.headline)
                    Text("Following")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .sheet(isPresented: $showFollowers) {
            if let userId = userService.currentUser?.id {
                FollowersListView(userId: userId, listType: .followers)
            }
        }
        .sheet(isPresented: $showFollowing) {
            if let userId = userService.currentUser?.id {
                FollowersListView(userId: userId, listType: .following)
            }
        }
    }
}
```

## 🔧 Service Integration

### Follow/Unfollow Actions

```swift
import SwiftUI

struct FollowActionExample: View {
    @StateObject private var socialService = SocialService.shared
    let targetUserId = "example-user-id"
    
    var body: some View {
        VStack(spacing: 20) {
            // Follow
            Button("Follow User") {
                Task {
                    do {
                        try await socialService.followUser(userId: targetUserId)
                        print("✅ Followed successfully")
                    } catch {
                        print("❌ Follow failed: \(error)")
                    }
                }
            }
            
            // Unfollow
            Button("Unfollow User") {
                Task {
                    do {
                        try await socialService.unfollowUser(userId: targetUserId)
                        print("✅ Unfollowed successfully")
                    } catch {
                        print("❌ Unfollow failed: \(error)")
                    }
                }
            }
            
            // Check status
            Button("Check Follow Status") {
                Task {
                    do {
                        let isFollowing = try await socialService.isFollowing(userId: targetUserId)
                        print("Following: \(isFollowing)")
                    } catch {
                        print("❌ Check failed: \(error)")
                    }
                }
            }
        }
    }
}
```

### Fetch Social Lists

```swift
import SwiftUI

struct FetchListsExample: View {
    @StateObject private var socialService = SocialService.shared
    @State private var followers: [UserModel] = []
    @State private var following: [UserModel] = []
    
    var body: some View {
        List {
            Section("Followers (\(followers.count))") {
                ForEach(followers) { user in
                    Text(user.displayName)
                }
            }
            
            Section("Following (\(following.count))") {
                ForEach(following) { user in
                    Text(user.displayName)
                }
            }
        }
        .task {
            await loadLists()
        }
    }
    
    func loadLists() async {
        guard let userId = FirebaseManager.shared.currentUser?.uid else { return }
        
        do {
            followers = try await socialService.fetchFollowers(for: userId)
            following = try await socialService.fetchFollowing(for: userId)
        } catch {
            print("Error loading lists: \(error)")
        }
    }
}
```

### Upload Photos

```swift
import SwiftUI

struct PhotoUploadExample: View {
    @StateObject private var socialService = SocialService.shared
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    
    var body: some View {
        VStack(spacing: 20) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                
                Button("Upload as Profile Picture") {
                    uploadProfilePicture(image)
                }
                
                Button("Upload to Gallery") {
                    uploadToGallery(image)
                }
            } else {
                Button("Select Image") {
                    showImagePicker = true
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            // Use your image picker here
        }
    }
    
    func uploadProfilePicture(_ image: UIImage) {
        Task {
            do {
                let url = try await socialService.uploadProfilePicture(image)
                print("✅ Profile picture uploaded: \(url)")
            } catch {
                print("❌ Upload failed: \(error)")
            }
        }
    }
    
    func uploadToGallery(_ image: UIImage) {
        Task {
            do {
                let url = try await socialService.uploadPhoto(image, albumName: "gallery")
                print("✅ Photo uploaded: \(url)")
            } catch {
                print("❌ Upload failed: \(error)")
            }
        }
    }
}
```

## 📱 Complete Profile View Example

```swift
import SwiftUI

struct CompleteProfileView: View {
    @StateObject private var userService = UserService()
    @StateObject private var socialService = SocialService.shared
    
    @State private var showPicturePicker = false
    @State private var showFollowers = false
    @State private var showFollowing = false
    
    let isOwnProfile: Bool
    let profileUserId: String
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Picture
                profileImageSection
                
                // Name and Username
                userInfoSection
                
                // Stats
                statsSection
                
                // Follow Button (if not own profile)
                if !isOwnProfile {
                    FollowButton(
                        userId: profileUserId,
                        username: userService.currentUser?.username ?? ""
                    )
                }
                
                // Bio
                if let bio = userService.currentUser?.bio {
                    Text(bio)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await userService.fetchCurrentUser()
        }
    }
    
    private var profileImageSection: some View {
        ZStack(alignment: .bottomTrailing) {
            if let imageURL = userService.currentUser?.profileImageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(ProgressView())
                }
                .frame(width: 140, height: 140)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.orange.opacity(0.6))
                    .frame(width: 140, height: 140)
                    .overlay(
                        Text(userService.currentUser?.initials ?? "")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            
            if isOwnProfile {
                Button {
                    showPicturePicker = true
                } label: {
                    Image(systemName: "camera.fill")
                        .padding(10)
                        .background(Circle().fill(Color.blue))
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showPicturePicker) {
            ProfilePicturePicker { url in
                Task {
                    await userService.fetchCurrentUser()
                }
            }
        }
    }
    
    private var userInfoSection: some View {
        VStack(spacing: 8) {
            Text(userService.currentUser?.displayName ?? "")
                .font(.title)
                .fontWeight(.bold)
            
            Text("@\(userService.currentUser?.username ?? "")")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    private var statsSection: some View {
        HStack(spacing: 40) {
            Button {
                showFollowers = true
            } label: {
                statView(
                    count: userService.currentUser?.followersCount ?? 0,
                    label: "Followers"
                )
            }
            
            Button {
                showFollowing = true
            } label: {
                statView(
                    count: userService.currentUser?.followingCount ?? 0,
                    label: "Following"
                )
            }
            
            statView(
                count: userService.currentUser?.postsCount ?? 0,
                label: "Posts"
            )
        }
        .sheet(isPresented: $showFollowers) {
            FollowersListView(userId: profileUserId, listType: .followers)
        }
        .sheet(isPresented: $showFollowing) {
            FollowersListView(userId: profileUserId, listType: .following)
        }
    }
    
    private func statView(count: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// Usage
struct ContentView: View {
    @StateObject private var userService = UserService()
    
    var body: some View {
        NavigationStack {
            if let userId = userService.currentUser?.id {
                CompleteProfileView(
                    isOwnProfile: true,
                    profileUserId: userId
                )
            }
        }
    }
}
```

## 🧪 Testing Snippets

### Test All Features

```swift
import SwiftUI

struct TestSocialFeaturesView: View {
    @StateObject private var socialService = SocialService.shared
    @State private var testResults: [String] = []
    
    var body: some View {
        List {
            Section("Test Results") {
                ForEach(testResults, id: \.self) { result in
                    Text(result)
                }
            }
            
            Section("Actions") {
                Button("Run All Tests") {
                    Task {
                        await runTests()
                    }
                }
            }
        }
    }
    
    func runTests() async {
        testResults = []
        
        // Test 1: Follow
        do {
            try await socialService.followUser(userId: "test-user-1")
            testResults.append("✅ Follow user: PASS")
        } catch {
            testResults.append("❌ Follow user: FAIL - \(error)")
        }
        
        // Test 2: Check status
        do {
            let isFollowing = try await socialService.isFollowing(userId: "test-user-1")
            testResults.append("✅ Check status: PASS (following: \(isFollowing))")
        } catch {
            testResults.append("❌ Check status: FAIL - \(error)")
        }
        
        // Test 3: Unfollow
        do {
            try await socialService.unfollowUser(userId: "test-user-1")
            testResults.append("✅ Unfollow user: PASS")
        } catch {
            testResults.append("❌ Unfollow user: FAIL - \(error)")
        }
        
        // Test 4: Upload picture
        if let testImage = UIImage(systemName: "person.circle.fill") {
            do {
                let url = try await socialService.uploadProfilePicture(testImage)
                testResults.append("✅ Upload picture: PASS - \(url)")
            } catch {
                testResults.append("❌ Upload picture: FAIL - \(error)")
            }
        }
        
        testResults.append("🎉 All tests completed!")
    }
}
```

## 🎨 Custom Follow Button

```swift
import SwiftUI

struct CustomFollowButton: View {
    let userId: String
    @StateObject private var socialService = SocialService.shared
    @State private var isFollowing = false
    @State private var isLoading = false
    
    var body: some View {
        Button {
            handleToggle()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(isFollowing ? "✓ Following" : "+ Follow")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(isFollowing ? Color.gray : Color.blue)
            )
        }
        .disabled(isLoading)
        .task {
            isFollowing = (try? await socialService.isFollowing(userId: userId)) ?? false
        }
    }
    
    func handleToggle() {
        isLoading = true
        Task {
            do {
                if isFollowing {
                    try await socialService.unfollowUser(userId: userId)
                } else {
                    try await socialService.followUser(userId: userId)
                }
                isFollowing.toggle()
            } catch {
                print("Error: \(error)")
            }
            isLoading = false
        }
    }
}
```

---

**Tips:**
- Copy any snippet and paste into your SwiftUI view
- Replace placeholder IDs with actual user IDs
- Customize colors and styling to match your app
- Add error handling UI as needed
- Test on real devices before production

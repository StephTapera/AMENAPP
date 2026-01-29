# Followers/Following & Enhanced Onboarding Guide 👥📸

## Status Summary

### ✅ Already Fully Implemented!

1. **Follow/Unfollow System** ✅ - `SocialService.swift`
2. **Profile Picture Upload** ✅ - `SocialService.uploadProfilePicture()`
3. **Followers/Following Lists** ✅ - Full fetch and display
4. **Mutual Followers** ✅ - Find friends who follow you back

### ❌ Needs to be Added

1. **Social Media Links** (Instagram, Twitter, etc.) - Not in UserModel yet
2. **Enhanced Onboarding UI** with photo upload
3. **Social links input during onboarding**

---

## What's Already Working 🎉

### 1. Follow/Unfollow Functionality

**File:** `SocialService.swift`

#### Follow a User:
```swift
// Usage
let socialService = SocialService.shared

Task {
    try await socialService.followUser(userId: "some-user-id")
}
```

**What it does:**
1. Creates follow relationship in `follows` collection
2. Increments your `followingCount`
3. Increments their `followersCount`  
4. Creates notification for them
5. All atomic (succeeds or fails together)

#### Unfollow a User:
```swift
Task {
    try await socialService.unfollowUser(userId: "some-user-id")
}
```

**What it does:**
1. Deletes follow relationship
2. Decrements your `followingCount`
3. Decrements their `followersCount`

#### Check if Following:
```swift
let isFollowing = try await socialService.isFollowing(userId: "some-user-id")
// Returns: true or false
```

---

### 2. Fetch Followers/Following Lists

#### Get Followers:
```swift
let followers = try await socialService.fetchFollowers(for: userId)
// Returns: [UserModel]
```

#### Get Following:
```swift
let following = try await socialService.fetchFollowing(for: userId)
// Returns: [UserModel]
```

#### Get Mutual Follows (Friends):
```swift
let mutualFriends = try await socialService.fetchMutualFollows(for: userId)
// Returns: [UserModel] - people who follow you AND you follow them
```

---

### 3. Profile Picture Management

#### Upload Profile Picture:
```swift
let imageURL = try await socialService.uploadProfilePicture(selectedImage)
// Uploads to Firebase Storage
// Updates user profile automatically
// Returns: URL string
```

**Where it uploads:**
```
Firebase Storage path:
profile_images/{userId}/profile_{timestamp}.jpg
```

#### Delete Profile Picture:
```swift
try await socialService.deleteProfilePicture()
// Deletes from Storage
// Removes from user profile
```

#### Upload Additional Photos:
```swift
let photoURL = try await socialService.uploadPhoto(image, albumName: "gallery")
// For dating profiles, photo albums, etc.
```

---

## What Needs to be Added 🔧

### 1. Social Media Links in UserModel

Add these fields to `UserModel.swift`:

```swift
// Add to UserModel struct:

// Social Media Links
var instagramHandle: String?
var twitterHandle: String?
var linkedInURL: String?
var tikTokHandle: String?
var youtubeURL: String?
var websiteURL: String?

// Add to CodingKeys:
case instagramHandle
case twitterHandle
case linkedInURL
case tikTokHandle
case youtubeURL
case websiteURL

// Add to init():
instagramHandle: String? = nil,
twitterHandle: String? = nil,
linkedInURL: String? = nil,
tikTokHandle: String? = nil,
youtubeURL: String? = nil,
websiteURL: String? = nil

// In body:
self.instagramHandle = instagramHandle
self.twitterHandle = twitterHandle
self.linkedInURL = linkedInURL
self.tikTokHandle = tikTokHandle
self.youtubeURL = youtubeURL
self.websiteURL = websiteURL
```

---

### 2. Enhanced Onboarding Flow

Create a new **multi-step onboarding** after signup:

#### Step 1: Welcome
- Welcome message
- Brief app overview
- "Let's get started" button

#### Step 2: Profile Photo
- Upload profile picture
- Or skip for now
- Camera or photo library option

#### Step 3: Social Links (Optional)
- Add Instagram handle
- Add Twitter handle
- Add other social media
- "Skip" button available

#### Step 4: Interests
- Select interests (Faith, Tech, Prayer, etc.)
- Used for recommendations

#### Step 5: Complete
- "You're all set!"
- Go to main app

---

## Implementation Plan

### Quick Fix (Update UserModel)

```swift
// In UserModel.swift

struct UserModel: Codable, Identifiable {
    // ... existing fields ...
    
    // ADD THESE:
    // Social Media Links
    var instagramHandle: String?
    var twitterHandle: String?
    var linkedInURL: String?
    var tikTokHandle: String?
    var youtubeURL: String?
    var websiteURL: String?
    
    enum CodingKeys: String, CodingKey {
        // ... existing cases ...
        
        // ADD THESE:
        case instagramHandle
        case twitterHandle
        case linkedInURL
        case tikTokHandle
        case youtubeURL
        case websiteURL
    }
    
    init(
        // ... existing parameters ...
        
        // ADD THESE:
        instagramHandle: String? = nil,
        twitterHandle: String? = nil,
        linkedInURL: String? = nil,
        tikTokHandle: String? = nil,
        youtubeURL: String? = nil,
        websiteURL: String? = nil
    ) {
        // ... existing assignments ...
        
        // ADD THESE:
        self.instagramHandle = instagramHandle
        self.twitterHandle = twitterHandle
        self.linkedInURL = linkedInURL
        self.tikTokHandle = tikTokHandle
        self.youtubeURL = youtubeURL
        self.websiteURL = websiteURL
    }
}
```

### Add Update Method to UserService

```swift
// In UserService class

/// Update social media links
func updateSocialLinks(
    instagram: String? = nil,
    twitter: String? = nil,
    linkedIn: String? = nil,
    tikTok: String? = nil,
    youtube: String? = nil,
    website: String? = nil
) async throws {
    guard let userId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    var updates: [String: Any] = ["updatedAt": Date()]
    
    if let instagram = instagram {
        updates["instagramHandle"] = instagram
    }
    if let twitter = twitter {
        updates["twitterHandle"] = twitter
    }
    if let linkedIn = linkedIn {
        updates["linkedInURL"] = linkedIn
    }
    if let tikTok = tikTok {
        updates["tikTokHandle"] = tikTok
    }
    if let youtube = youtube {
        updates["youtubeURL"] = youtube
    }
    if let website = website {
        updates["websiteURL"] = website
    }
    
    let path = "\(FirebaseManager.CollectionPath.users)/\(userId)"
    try await firebaseManager.updateDocument(updates, at: path)
    
    await fetchCurrentUser()
}
```

---

## Enhanced Onboarding View (Complete Code)

Create `EnhancedOnboardingView.swift`:

```swift
import SwiftUI
import PhotosUI

struct EnhancedOnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var userService = UserService()
    @StateObject private var socialService = SocialService.shared
    
    @State private var currentStep = 0
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var instagramHandle = ""
    @State private var twitterHandle = ""
    @State private var websiteURL = ""
    @State private var selectedInterests: Set<String> = []
    @State private var isUploading = false
    
    let totalSteps = 4
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress Bar
                progressBar
                
                // Content
                TabView(selection: $currentStep) {
                    welcomeStep.tag(0)
                    profilePhotoStep.tag(1)
                    socialLinksStep.tag(2)
                    interestsStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Navigation Buttons
                navigationButtons
            }
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            Task {
                if let data = try? await newPhoto?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    profileImage = uiImage
                }
            }
        }
    }
    
    // MARK: - Steps
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "cross.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.black)
            
            Text("Welcome to AMEN")
                .font(.custom("OpenSans-Bold", size: 32))
            
            Text("Let's set up your profile so you can connect with your faith community")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var profilePhotoStep: some View {
        VStack(spacing: 24) {
            Text("Add a Profile Photo")
                .font(.custom("OpenSans-Bold", size: 28))
            
            Text("Help others recognize you")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Photo Picker
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let profileImage = profileImage {
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.1), lineWidth: 2)
                        )
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray6))
                            .frame(width: 150, height: 150)
                        
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            
                            Text("Tap to upload")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            if profileImage != nil {
                Button {
                    profileImage = nil
                    selectedPhoto = nil
                } label: {
                    Text("Remove Photo")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.red)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var socialLinksStep: some View {
        VStack(spacing: 24) {
            Text("Connect Social Media")
                .font(.custom("OpenSans-Bold", size: 28))
            
            Text("Optional - Add links to your other profiles")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 16) {
                SocialLinkField(
                    icon: "camera.fill",
                    platform: "Instagram",
                    placeholder: "@username",
                    text: $instagramHandle
                )
                
                SocialLinkField(
                    icon: "bird.fill",
                    platform: "Twitter",
                    placeholder: "@username",
                    text: $twitterHandle
                )
                
                SocialLinkField(
                    icon: "globe",
                    platform: "Website",
                    placeholder: "https://yoursite.com",
                    text: $websiteURL
                )
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    private var interestsStep: some View {
        VStack(spacing: 24) {
            Text("Select Your Interests")
                .font(.custom("OpenSans-Bold", size: 28))
            
            Text("Help us personalize your experience")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(interestOptions, id: \.self) { interest in
                    InterestChip(
                        title: interest,
                        isSelected: selectedInterests.contains(interest)
                    ) {
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else {
                            selectedInterests.insert(interest)
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - UI Components
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 4)
                
                Rectangle()
                    .fill(Color.black)
                    .frame(width: geometry.size.width * progress, height: 4)
                    .animation(.easeInOut, value: currentStep)
            }
        }
        .frame(height: 4)
    }
    
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep > 0 {
                Button {
                    withAnimation {
                        currentStep -= 1
                    }
                } label: {
                    Text("Back")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black, lineWidth: 2)
                        )
                }
            }
            
            Button {
                handleNextButton()
            } label: {
                HStack {
                    Text(currentStep == totalSteps - 1 ? "Complete" : "Next")
                        .font(.custom("OpenSans-Bold", size: 16))
                    
                    if isUploading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }
            .disabled(isUploading)
        }
        .padding()
    }
    
    private var progress: CGFloat {
        CGFloat(currentStep + 1) / CGFloat(totalSteps)
    }
    
    private let interestOptions = [
        "Prayer", "Bible Study", "Worship", "Technology",
        "AI & Faith", "Community", "Mission Work", "Youth Ministry",
        "Mentorship", "Entrepreneurship", "Music", "Art"
    ]
    
    // MARK: - Actions
    
    private func handleNextButton() {
        if currentStep < totalSteps - 1 {
            withAnimation {
                currentStep += 1
            }
        } else {
            // Complete onboarding
            Task {
                await completeOnboarding()
            }
        }
    }
    
    private func completeOnboarding() async {
        isUploading = true
        defer { isUploading = false }
        
        do {
            // Upload profile photo if selected
            if let profileImage = profileImage {
                _ = try await socialService.uploadProfilePicture(profileImage)
            }
            
            // Save social links
            if !instagramHandle.isEmpty || !twitterHandle.isEmpty || !websiteURL.isEmpty {
                try await userService.updateSocialLinks(
                    instagram: instagramHandle.isEmpty ? nil : instagramHandle,
                    twitter: twitterHandle.isEmpty ? nil : twitterHandle,
                    website: websiteURL.isEmpty ? nil : websiteURL
                )
            }
            
            // Save interests
            if !selectedInterests.isEmpty {
                try await userService.saveOnboardingPreferences(
                    interests: Array(selectedInterests),
                    goals: [],
                    prayerTime: "Morning"
                )
            }
            
            // Mark onboarding as complete
            dismiss()
            
        } catch {
            print("❌ Onboarding error: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct SocialLinkField: View {
    let icon: String
    let platform: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.black)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(platform)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.secondary)
                
                TextField(placeholder, text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .autocapitalization(.none)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

struct InterestChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(isSelected ? .white : .black)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.black : Color(.systemGray6))
                )
        }
    }
}
```

---

## Display Social Links in Profile

In `UserProfileView.swift` or `ProfileView.swift`, add:

```swift
// Social Links Section
if let instagram = profileData.instagramHandle {
    SocialLinkButton(platform: .instagram, handle: instagram)
}

if let twitter = profileData.twitterHandle {
    SocialLinkButton(platform: .twitter, handle: twitter)
}

if let website = profileData.websiteURL {
    SocialLinkButton(platform: .website, url: website)
}

// Supporting View
struct SocialLinkButton: View {
    enum Platform {
        case instagram, twitter, linkedin, website
        
        var icon: String {
            switch self {
            case .instagram: return "camera.fill"
            case .twitter: return "bird.fill"
            case .linkedin: return "briefcase.fill"
            case .website: return "globe"
            }
        }
        
        var color: Color {
            switch self {
            case .instagram: return .purple
            case .twitter: return .blue
            case .linkedin: return .blue
            case .website: return .gray
            }
        }
    }
    
    let platform: Platform
    var handle: String? = nil
    var url: String? = nil
    
    var body: some View {
        Button {
            openLink()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: platform.icon)
                    .font(.system(size: 16))
                
                Text(handle ?? url ?? "")
                    .font(.custom("OpenSans-SemiBold", size: 14))
            }
            .foregroundStyle(platform.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(platform.color.opacity(0.1))
            )
        }
    }
    
    private func openLink() {
        var urlString = ""
        
        switch platform {
        case .instagram:
            urlString = "https://instagram.com/\(handle ?? "")"
        case .twitter:
            urlString = "https://twitter.com/\(handle ?? "")"
        case .website:
            urlString = url ?? ""
        case .linkedin:
            urlString = url ?? ""
        }
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
```

---

## Testing Guide

### Test Follow/Unfollow

1. **Create two test accounts**
2. **From Account A:** Find Account B's profile
3. **Tap "Follow"** button
4. **Check Firestore:**
   - `follows` collection has new document
   - Account A's `followingCount` = 1
   - Account B's `followersCount` = 1
5. **Tap "Unfollow"**
6. **Verify counts decrease**

### Test Profile Photo Upload

1. **Open onboarding or profile edit**
2. **Select photo** from camera/library
3. **Upload completes**
4. **Check Firebase Storage:**
   - File in `profile_images/{userId}/`
5. **Check Firestore:**
   - User document has `profileImageURL`

### Test Social Links

1. **Complete onboarding** with social links
2. **Check Firestore user document:**
   ```json
   {
     "instagramHandle": "johndoe",
     "twitterHandle": "johndoe",
     "websiteURL": "https://example.com"
   }
   ```
3. **View profile** → Social links appear
4. **Tap link** → Opens in browser/app

---

## Summary

### ✅ Already Working

- Follow/Unfollow system
- Followers/Following lists
- Mutual followers
- Profile picture upload
- Photo gallery uploads

### 🔧 Need to Add

1. Social media fields to `UserModel`
2. `updateSocialLinks()` method to `UserService`
3. Enhanced onboarding UI
4. Social links display in profile

### Files to Modify

1. **UserModel.swift** - Add social media fields
2. **UserService.swift** - Add `updateSocialLinks()` method
3. Create **EnhancedOnboardingView.swift** - New onboarding flow
4. **ProfileView.swift** - Display social links

---

## Quick Implementation Checklist

- [ ] Add social media fields to `UserModel`
- [ ] Add social media cases to `CodingKeys`
- [ ] Add social media parameters to `init()`
- [ ] Add `updateSocialLinks()` to `UserService`
- [ ] Create `EnhancedOnboardingView.swift`
- [ ] Show onboarding after signup
- [ ] Display social links in profile view
- [ ] Test all functionality

Everything else is already done! 🎉

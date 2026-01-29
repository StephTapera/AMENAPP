# Firebase Setup Checklist for AMENAPP

## ✅ What's Been Done

1. **AMENAPPApp.swift** - Firebase initialization added
2. **FirebaseManager.swift** - Centralized Firebase service manager
3. **UserModel.swift** - User model with Firestore integration
4. **AuthenticationViewModel.swift** - Authentication logic
5. **SignInView.swift** - Sign-in/sign-up UI
6. **ContentView.swift** - Updated to check authentication status

## 🔧 Next Steps - You Need to Do

### 1. Add Firebase to Your Xcode Project

#### Option A: Using Swift Package Manager (Recommended)
1. Open your project in Xcode
2. Go to **File > Add Package Dependencies**
3. Enter this URL: `https://github.com/firebase/firebase-ios-sdk`
4. Select version **10.x.x** or latest
5. Add these packages:
   - ✅ FirebaseAuth
   - ✅ FirebaseFirestore
   - ✅ FirebaseStorage
   - ✅ FirebaseAnalytics (optional)

#### Option B: Using CocoaPods
Add to your `Podfile`:
```ruby
pod 'Firebase/Auth'
pod 'Firebase/Firestore'
pod 'Firebase/Storage'
pod 'Firebase/Analytics'
```

Then run: `pod install`

---

### 2. Download GoogleService-Info.plist

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project (or use existing):
   - Project name: **AMENAPP**
   - Enable Google Analytics (optional)
3. Add an iOS app:
   - Bundle ID: Your app's bundle identifier (check in Xcode)
   - App nickname: **AMENAPP**
   - Download **GoogleService-Info.plist**
4. **Drag the file into your Xcode project**:
   - ⚠️ Make sure "Copy items if needed" is checked
   - ⚠️ Add to target: AMENAPP

---

### 3. Enable Firebase Authentication

In Firebase Console:
1. Go to **Build > Authentication**
2. Click **Get Started**
3. Enable sign-in methods:
   - ✅ **Email/Password** - Enable this first
   - 🔧 Google (optional, requires more setup)
   - 🔧 Apple (optional, requires more setup)

---

### 4. Set Up Cloud Firestore

In Firebase Console:
1. Go to **Build > Firestore Database**
2. Click **Create Database**
3. Choose **Start in test mode** (for development)
   - ⚠️ Remember to add security rules later!
4. Select a region (choose closest to your users)

#### Security Rules (Update Later)
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection - users can read/write their own data
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    
    // Posts collection - authenticated users can read all, write their own
    match /posts/{postId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth.uid == resource.data.authorId;
    }
    
    // Comments - authenticated users can create, delete own
    match /posts/{postId}/comments/{commentId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow delete: if request.auth.uid == resource.data.authorId;
    }
  }
}
```

---

### 5. Set Up Firebase Storage

In Firebase Console:
1. Go to **Build > Storage**
2. Click **Get Started**
3. Choose **Start in test mode**
4. Select same region as Firestore

#### Storage Rules (Update Later)
```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /profile_images/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    
    match /post_images/{postId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

---

### 6. Update Info.plist (if needed)

Add these keys if you plan to use photos:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photos to upload profile pictures and post images.</string>
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take photos for your posts.</string>
```

---

### 7. Test the Integration

1. Build and run your app
2. Try to sign up with email/password
3. Check Firebase Console:
   - Authentication > Users (should see new user)
   - Firestore Database > users (should see user document)

---

## 🎯 How to Use in Your App

### Sign In
```swift
let authViewModel = AuthenticationViewModel()
await authViewModel.signIn(email: "user@example.com", password: "password123")
```

### Sign Up
```swift
await authViewModel.signUp(
    email: "user@example.com", 
    password: "password123",
    displayName: "John Doe"
)
```

### Save Data to Firestore
```swift
let post = Post(...)
try await FirebaseManager.shared.saveDocument(
    post, 
    to: "posts/\(post.id)"
)
```

### Fetch Data from Firestore
```swift
let posts = try await FirebaseManager.shared.fetchCollection(
    from: "posts",
    as: Post.self
)
```

### Upload Image
```swift
let url = try await FirebaseManager.shared.uploadImage(
    image,
    to: "profile_images/\(userId)/profile.jpg"
)
```

---

## 🔒 Important Security Notes

1. **Never commit GoogleService-Info.plist to public repos**
   - Add to `.gitignore` if project is public
2. **Update Firestore rules before production**
   - Test mode allows anyone to read/write!
3. **Enable App Check** for production
   - Protects against abuse
4. **Use Firebase Authentication**
   - Don't store passwords yourself
5. **Validate data on server side**
   - Use Cloud Functions for sensitive operations

---

## 🐛 Common Issues & Solutions

### Issue: "No such module 'FirebaseAuth'"
**Solution:** Clean build folder (Cmd+Shift+K) and rebuild

### Issue: "GoogleService-Info.plist not found"
**Solution:** Make sure file is added to target and copied into app bundle

### Issue: "Permission denied" in Firestore
**Solution:** Check your security rules, make sure user is authenticated

### Issue: "Network error"
**Solution:** Check internet connection, Firebase project is active

---

## 📚 Next Steps

After basic setup works:

1. **Add Post creation with Firebase**
   - Save posts to Firestore
   - Upload images to Storage
   
2. **Add real-time listeners**
   - Listen for new posts
   - Real-time chat messages
   
3. **Add user profiles**
   - Profile pictures
   - Bio, followers, etc.
   
4. **Add notifications**
   - Firebase Cloud Messaging
   - Push notifications
   
5. **Add analytics**
   - Track user engagement
   - Monitor app performance

---

## 📖 Useful Resources

- [Firebase iOS Documentation](https://firebase.google.com/docs/ios/setup)
- [Firestore Data Modeling](https://firebase.google.com/docs/firestore/manage-data/structure-data)
- [Firebase Security Rules](https://firebase.google.com/docs/rules)
- [SwiftUI + Firebase Tutorial](https://firebase.google.com/docs/auth/ios/start)

---

## ✨ You're All Set!

Once you complete steps 1-7, your app will have:
- ✅ User authentication (email/password)
- ✅ User profiles stored in Firestore
- ✅ Image upload to Firebase Storage
- ✅ Centralized Firebase management
- ✅ Error handling and validation
- ✅ Beautiful sign-in UI

Happy coding! 🚀

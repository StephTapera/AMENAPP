# Onboarding Flow Implementation

## 📋 Overview

A complete onboarding experience for new AMEN users that collects user information and welcomes them to the community.

## 🎯 Features

### Onboarding Steps (7 total):

1. **Welcome Screen** - Animated introduction to AMEN with feature highlights
2. **Display Name** - User enters their name
3. **Profile Photo** - Optional photo upload (placeholder implementation)
4. **Bio** - Optional 300-character bio about themselves
5. **Interests** - Select at least 3 interests (Prayer, Bible Study, etc.)
6. **Denomination** - Optional faith background selection
7. **Notifications** - Enable/disable notification preferences
8. **Completion** - Celebratory screen with confetti and tips

### Design Highlights:

- ✨ **Animated Welcome** - Pulsing rings, smooth transitions
- 📊 **Progress Bar** - Shows progress through onboarding steps
- 🎨 **Consistent Design** - Blue/purple gradient matching app theme
- ⬅️ **Navigation** - Back button, Skip option, Continue flow
- 🎉 **Confetti Celebration** - Success animation on completion
- 📱 **Haptic Feedback** - Tactile responses throughout

## 📁 File Structure

```
OnboardingCoordinator.swift          - State management & data model
OnboardingContainerView.swift        - Main container with navigation
OnboardingWelcomeView.swift          - Welcome/intro screen
OnboardingStepViews.swift            - Display Name, Photo, Bio views
OnboardingInterestsView.swift        - Interest selection grid
OnboardingDenominationView.swift     - Denomination picker
OnboardingNotificationsView.swift    - Notification preferences
OnboardingCompletionView.swift       - Final celebration screen
```

## 🔧 How It Works

### 1. Authentication Flow Integration

**AuthenticationViewModel** tracks two key states:
- `isAuthenticated` - Whether user is logged in
- `needsOnboarding` - Whether user needs to complete onboarding

**ContentView** shows different screens based on state:
```swift
if !authViewModel.isAuthenticated {
    SignInView()  // Not logged in
} else if authViewModel.needsOnboarding {
    OnboardingContainerView()  // New user
} else {
    mainContent  // Existing user
}
```

### 2. Onboarding Coordinator

**OnboardingCoordinator** manages:
- Current step tracking
- User data collection
- Progress calculation
- Navigation (next, previous, skip)
- Completion logic

### 3. User Data Collection

**OnboardingUserData** stores:
```swift
- displayName: String
- profileImage: Data?
- bio: String
- selectedInterests: [String]
- denomination: String?
- notificationsEnabled: Bool
```

### 4. Completion Flow

When user taps "Enter AMEN" on completion screen:
1. `coordinator.isOnboardingComplete` becomes `true`
2. `saveUserDataToFirebase()` is called
3. User data is logged (ready to save to Firebase)
4. `authViewModel.completeOnboarding()` is called
5. `needsOnboarding` becomes `false`
6. ContentView transitions to main app

## 🎨 Design System

### Colors
- Primary Gradient: Blue → Purple
- Success: Green → Blue
- Background: White & Gray (0.98)
- Text: Black with varying opacity

### Typography
- Titles: OpenSans-Bold
- Body: OpenSans-Regular
- Buttons: OpenSans-Bold

### Animations
- Spring animations for transitions
- Ease-out for content reveals
- Matched geometry for smooth tab changes
- Scale effects for interactive elements

## 📝 Available Options

### Interests (12 options)
- Prayer
- Bible Study
- Worship
- Fellowship
- Evangelism
- Youth Ministry
- Missions
- Testimonies
- Christian Music
- Devotionals
- Theology
- Community Service

### Denominations (14 options)
- Non-denominational
- Baptist
- Catholic
- Methodist
- Pentecostal
- Presbyterian
- Lutheran
- Episcopal
- Orthodox
- Seventh-day Adventist
- Assembly of God
- Church of God
- Other
- Prefer not to say

## 🔄 User Flow

```
Sign Up → Welcome → Display Name → Profile Photo → Bio → 
Interests → Denomination → Notifications → Completion → Main App
```

### Navigation Rules:
- **Can Skip**: Profile Photo, Bio, Denomination, Notifications
- **Required**: Welcome, Display Name, Interests (min 3), Completion
- **Can Go Back**: All steps except Welcome and Completion

## 🚀 Next Steps to Complete Implementation

### 1. Connect to Firebase
Update `saveUserDataToFirebase()` in `OnboardingContainerView.swift`:
```swift
private func saveUserDataToFirebase() async {
    guard let userId = FirebaseManager.shared.currentUser?.uid else { return }
    
    // Update user profile in Firestore
    try? await FirebaseManager.shared.updateDocument([
        "displayName": coordinator.userData.displayName,
        "bio": coordinator.userData.bio,
        "interests": coordinator.userData.selectedInterests,
        "denomination": coordinator.userData.denomination ?? "",
        "notificationsEnabled": coordinator.userData.notificationsEnabled,
        "hasCompletedOnboarding": true
    ], at: "users/\(userId)")
    
    // Upload profile image if exists
    if let imageData = coordinator.userData.profileImage,
       let image = UIImage(data: imageData) {
        let imageUrl = try? await FirebaseManager.shared.uploadImage(
            image,
            to: "profile_images/\(userId)/profile.jpg"
        )
        
        if let url = imageUrl {
            try? await FirebaseManager.shared.updateDocument([
                "profileImageURL": url.absoluteString
            ], at: "users/\(userId)")
        }
    }
    
    authViewModel.completeOnboarding()
}
```

### 2. Implement Real Photo Picker
Replace `ImagePickerView` with `PHPickerViewController`:
```swift
import PhotosUI

struct RealImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: PHPickerViewControllerDelegate {
        let parent: RealImagePicker
        
        init(_ parent: RealImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image as? UIImage
                    }
                }
            }
        }
    }
}
```

### 3. Add Confetti Package
Add to your Xcode project via SPM:
```
https://github.com/simibac/ConfettiSwiftUI
```

Or remove `.confettiCannon()` modifier from `OnboardingCompletionView.swift` if you don't want it.

### 4. Check for Existing Onboarding
Update `checkAuthenticationStatus()` in `AuthenticationViewModel`:
```swift
func checkAuthenticationStatus() {
    isAuthenticated = firebaseManager.isAuthenticated
    
    if isAuthenticated {
        Task {
            // Check if user has completed onboarding
            if let userId = firebaseManager.currentUser?.uid {
                let userData = try? await firebaseManager.fetchDocument(
                    from: "users/\(userId)",
                    as: UserModel.self
                )
                
                // If hasCompletedOnboarding field is false or missing, show onboarding
                needsOnboarding = !(userData?.hasCompletedOnboarding ?? false)
            }
            
            await userService.fetchCurrentUser()
        }
    }
}
```

### 5. Add hasCompletedOnboarding to UserModel
Update `UserModel.swift`:
```swift
struct UserModel: Codable, Identifiable {
    // ... existing fields
    var hasCompletedOnboarding: Bool
    
    // ... in CodingKeys
    case hasCompletedOnboarding
    
    // ... in init
    hasCompletedOnboarding: Bool = false
}
```

## ✅ Testing Checklist

- [ ] Sign up creates new account
- [ ] Onboarding appears for new users
- [ ] Can navigate forward through all steps
- [ ] Can go back to previous steps
- [ ] Can skip optional steps
- [ ] Display name is required
- [ ] At least 3 interests must be selected
- [ ] Profile photo is optional
- [ ] Bio has 300 character limit
- [ ] Confetti appears on completion
- [ ] Data is saved to Firebase
- [ ] Main app loads after completion
- [ ] Existing users skip onboarding

## 🎉 Result

New users now get a beautiful, guided onboarding experience that:
- Collects essential profile information
- Introduces them to AMEN features
- Makes them feel welcome
- Ensures they're set up for success

Welcome to AMEN! 🙏✨

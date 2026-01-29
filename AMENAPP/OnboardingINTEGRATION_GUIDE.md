# App Launch & Onboarding Integration Guide

## Overview
Your app now has a beautiful launch experience with three options:
1. **Create Account** → Sign up flow
2. **Login** → Login flow  
3. **Try Demo Mode** → Interactive onboarding (for exploration without account)

## Files Created

### 📁 Onboarding/
- **AppLaunchView.swift** - First screen with 3 options (new!)
- **OnboardingView.swift** - 5-page interactive onboarding
- **OnboardingCoordinator.swift** - Flow manager

### 📁 Authentication/
- **AuthenticationView.swift** - Login/Signup UI (updated to accept initial mode)

## How to Use

### Option 1: Use OnboardingCoordinator (Recommended)
In your main App file, use the coordinator:

```swift
import SwiftUI

@main
struct AMENAPPApp: App {
    var body: some Scene {
        WindowGroup {
            OnboardingCoordinator()
        }
    }
}
```

### Option 2: Use AppLaunchView Directly
If you want to always show the launch screen:

```swift
import SwiftUI

@main
struct AMENAPPApp: App {
    var body: some Scene {
        WindowGroup {
            AppLaunchView()
        }
    }
}
```

## User Flow

### First Launch:
```
AppLaunchView (Choose: Create Account / Login / Demo)
    ↓
    ├─→ Create Account → AuthenticationView (signup mode)
    ├─→ Login → AuthenticationView (login mode)
    └─→ Try Demo → OnboardingView (5 pages)
```

### After Onboarding:
```
OnboardingCoordinator checks:
- hasCompletedOnboarding = false → Show AppLaunchView
- hasCompletedOnboarding = true, isLoggedIn = false → Show AuthenticationView
- isLoggedIn = true → Show Main App
```

## Features

### AppLaunchView Features:
✅ Animated logo with pulsing background
✅ Three beautiful buttons with distinct styles
✅ Gradient animations
✅ Symbol effects (pulse on demo button)
✅ Smooth transitions

### Demo Mode:
- Users can explore the app without creating an account
- Goes through personalization (interests, goals, prayer time)
- Perfect for showcasing features
- Can sign up after exploring

## Testing Tips

To test different flows, use these commands in Xcode console or code:

```swift
// Reset to first launch
UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
UserDefaults.standard.set(false, forKey: "isLoggedIn")

// Skip to auth screen
UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
UserDefaults.standard.set(false, forKey: "isLoggedIn")

// Skip to main app
UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
UserDefaults.standard.set(true, forKey: "isLoggedIn")
```

## Customization

### Change Colors:
All gradients use purple theme. Search for:
- `Color(red: 0.5, green: 0.3, blue: 0.9)` - Main purple
- `Color(red: 0.6, green: 0.4, blue: 1.0)` - Light purple

### Replace Main App View:
In `OnboardingCoordinator.swift`, replace:
```swift
Text("Main App Content - User is logged in!")
```
with your actual main view (e.g., `ContentView()` or `TabView`)

### Modify Button Text:
In `AppLaunchView.swift`:
- "Create Account" button (line ~99)
- "Login" button (line ~117)
- "Try Demo Mode" button (line ~143)

## Next Steps

1. **Build and run** the app (`Cmd + R`)
2. **Test all three flows**:
   - Tap "Create Account" → See signup form
   - Tap "Login" → See login form
   - Tap "Try Demo Mode" → See onboarding
3. **Connect to your backend** when ready:
   - Update `handleAuthentication()` in AuthenticationView.swift
   - Set `isLoggedIn = true` on successful auth
   - Set `hasCompletedOnboarding = true` after onboarding

## Preview

Run the preview in Xcode:
- AppLaunchView → See launch screen
- OnboardingView → See onboarding flow
- AuthenticationView → See auth screens

---

**Questions?** All files are heavily commented and use SwiftUI best practices!

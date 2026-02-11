# Production Setup Guide

## Quick Start - Getting Ready for Production

### Step 1: Add Required Files to Xcode

1. **Add ChurchSearchService.swift**
   - File → Add Files to "AMENAPP"
   - Select `ChurchSearchService.swift`
   - Ensure "Copy items if needed" is checked
   - Add to AMENAPP target

2. **Add ChurchNotificationManager.swift**
   - Same process as above
   - Add to AMENAPP target

3. **Add CompositeNotificationDelegate.swift**
   - Same process as above
   - Add to AMENAPP target

### Step 2: Update Info.plist

Open `Info.plist` and add these keys:

```xml
<!-- Right-click in Info.plist → Add Row -->

<!-- Location When In Use -->
Key: Privacy - Location When In Use Usage Description
Value: AMENAPP needs your location to find churches near you and provide personalized recommendations based on your area.

<!-- Location Always (for notifications) -->
Key: Privacy - Location Always and When In Use Usage Description
Value: AMENAPP uses your location to send you helpful notifications when you're near a saved church and to help you discover new churches nearby.

<!-- User Notifications -->
Key: Privacy - User Notifications Usage Description  
Value: AMENAPP sends reminders for upcoming church services, weekly notifications, and alerts when you're near your saved churches.

<!-- Camera (if using photos) -->
Key: Privacy - Camera Usage Description
Value: AMENAPP needs camera access to take photos for posts and profile pictures.

<!-- Photo Library -->
Key: Privacy - Photo Library Usage Description
Value: AMENAPP needs access to your photo library to select images for posts and profile.
```

### Step 3: Enable Capabilities in Xcode

1. Select your app target
2. Go to "Signing & Capabilities" tab
3. Click "+ Capability"
4. Add:
   - ✅ Push Notifications
   - ✅ Background Modes
     - Location updates
     - Remote notifications
   - ✅ Maps (already should be enabled)

### Step 4: Verify Build Settings

1. Select your app target
2. Go to "Build Settings"
3. Search for "optimization"
4. Set:
   - Debug: `-Onone` (No optimization)
   - Release: `-O` (Optimize for speed)

### Step 5: Test on Real Device

**Important:** Location and notifications don't work properly in Simulator!

1. Connect iPhone/iPad
2. Select your device in Xcode
3. Product → Run
4. Test:
   - Location permission request
   - Church search
   - Save a church
   - Notification permission request
   - Receive church reminder

### Step 6: Enable App Check (Before Production)

In `AppDelegate.swift`, find this section (around line 35):

```swift
// 🚧 TODO: Configure App Check properly before production
// Uncomment this section:

#if DEBUG
let providerFactory = AppCheckDebugProviderFactory()
AppCheck.setAppCheckProviderFactory(providerFactory)
#else
let providerFactory = DeviceCheckProviderFactory()
AppCheck.setAppCheckProviderFactory(providerFactory)
#endif
```

**Uncomment it before submitting to App Store!**

### Step 7: Firebase Security Rules

#### Firestore

Go to Firebase Console → Firestore → Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    // Users
    match /users/{userId} {
      allow read: if isAuthenticated();
      allow write: if isOwner(userId);
    }
    
    // Posts
    match /posts/{postId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update, delete: if isAuthenticated() && 
        request.auth.uid == resource.data.authorId;
    }
    
    // Comments
    match /posts/{postId}/comments/{commentId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow delete: if isAuthenticated() && 
        request.auth.uid == resource.data.userId;
    }
    
    // Church Notes
    match /churchNotes/{noteId} {
      allow read: if isAuthenticated() && 
        request.auth.uid == resource.data.userId;
      allow write: if isAuthenticated() && 
        request.auth.uid == resource.data.userId;
    }
    
    // Messages
    match /messages/{messageId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update, delete: if isAuthenticated() && 
        request.auth.uid == resource.data.senderId;
    }
    
    // Follows
    match /follows/{followId} {
      allow read: if isAuthenticated();
      allow write: if isAuthenticated();
    }
  }
}
```

#### Realtime Database

Go to Firebase Console → Realtime Database → Rules

```json
{
  "rules": {
    ".read": "auth != null",
    ".write": false,
    "users": {
      "$uid": {
        ".read": "auth != null",
        ".write": "auth.uid === $uid"
      }
    },
    "posts": {
      ".read": "auth != null",
      "$postId": {
        ".write": "auth != null"
      }
    },
    "messages": {
      ".read": "auth != null",
      ".write": "auth != null"
    }
  }
}
```

### Step 8: Archive and Submit

1. **Select "Any iOS Device (arm64)"** as destination
2. Product → Archive
3. Wait for archive to complete
4. Click "Distribute App"
5. Choose "App Store Connect"
6. Upload
7. Wait for processing
8. Submit for review in App Store Connect

### Step 9: TestFlight Beta Testing (Recommended)

Before full release:

1. Upload build to App Store Connect
2. Go to TestFlight tab
3. Add internal testers
4. Add external testers (optional)
5. Gather feedback
6. Fix critical issues
7. Submit final build for review

## Common Issues & Solutions

### Issue: "Location authorization failed"
**Solution:** Make sure Info.plist has location usage descriptions

### Issue: "Notifications not working"
**Solution:** 
1. Check Info.plist has notification usage description
2. Verify Push Notifications capability is enabled
3. Test on real device (not simulator)
4. Check notification permissions in Settings

### Issue: "Church search returns no results"
**Solution:**
1. Verify location permissions granted
2. Check internet connection
3. Increase search radius
4. Try different location

### Issue: "App crashes on launch"
**Solution:**
1. Check Firebase is configured (AppDelegate)
2. Verify all frameworks are linked
3. Clean build folder (Shift + Cmd + K)
4. Delete derived data
5. Check Crashlytics for details

### Issue: "Cannot upload to App Store"
**Solution:**
1. Verify bundle ID matches App Store Connect
2. Check code signing is valid
3. Ensure version number is incremented
4. Try Xcode → Preferences → Accounts → Download Manual Profiles

## Testing Checklist Before Submit

- [ ] App launches successfully
- [ ] Login/signup works
- [ ] Can create posts
- [ ] Can view others' posts
- [ ] Church search finds churches (real device!)
- [ ] Can save churches
- [ ] Receive church notifications (real device!)
- [ ] Push notifications work
- [ ] Offline mode works
- [ ] No crashes during 30-minute use
- [ ] Looks good on small screen (SE)
- [ ] Looks good on large screen (Pro Max)
- [ ] All buttons/actions have feedback
- [ ] Loading states display properly
- [ ] Error messages are user-friendly

## Pre-Launch Final Checks

**Code:**
- [ ] App Check enabled
- [ ] Debug logs removed/disabled
- [ ] Console.log statements removed
- [ ] Test data removed
- [ ] API keys secured
- [ ] Build optimized for release

**Firebase:**
- [ ] Security rules updated
- [ ] App Check configured
- [ ] Billing enabled
- [ ] Usage alerts set
- [ ] Crashlytics enabled

**App Store:**
- [ ] Screenshots uploaded (all required sizes)
- [ ] Description written
- [ ] Keywords added
- [ ] Privacy policy link added
- [ ] Support URL added
- [ ] Age rating set
- [ ] Pricing configured

**Legal:**
- [ ] Privacy policy published
- [ ] Terms of service published
- [ ] Data handling explained
- [ ] User rights documented

## Support Resources

### Firebase
- Console: https://console.firebase.google.com
- Documentation: https://firebase.google.com/docs
- Status: https://status.firebase.google.com

### Apple
- App Store Connect: https://appstoreconnect.apple.com
- Developer Portal: https://developer.apple.com
- Guidelines: https://developer.apple.com/app-store/review/guidelines

### Help
- Firebase Support: Console → Help
- Apple Developer Forums: https://developer.apple.com/forums
- Stack Overflow: Tag with `firebase` and `ios`

## Need Help?

If you encounter issues:

1. Check error messages in Xcode console
2. Review Firebase logs in Console
3. Check Crashlytics for crash reports
4. Review security rules
5. Verify all keys/permissions in Info.plist
6. Test on real device
7. Check internet connectivity
8. Review this guide again

---

**Remember:** Test thoroughly on real devices before submitting to the App Store!

Good luck with your launch! 🚀

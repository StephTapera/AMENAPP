# AMENAPP - Production Readiness Checklist

## ✅ Completed Features

### Core Infrastructure
- [x] Firebase integration (Auth, Firestore, Realtime Database, Cloud Messaging)
- [x] User authentication (Email, Google Sign-In)
- [x] Real-time data synchronization
- [x] Offline persistence (Firestore & Realtime Database)
- [x] Push notifications system
- [x] Church search with MapKit
- [x] Local church notifications
- [x] Composite notification handling

### App Features
- [x] User profiles with search keywords
- [x] Follow/Follower system
- [x] Posts with likes and comments
- [x] Prayer requests
- [x] Church notes with Firebase sync
- [x] Messages/Chat system
- [x] Find Church with real MapKit search
- [x] Saved churches with smart notifications
- [x] Resources section

### Notification System
- [x] Firebase Cloud Messaging integration
- [x] Local church service reminders
- [x] Location-based church notifications
- [x] Weekly church reminders
- [x] Composite delegate for multiple notification types
- [x] Notification categories with actions

## 🚧 Pre-Production Tasks

### 1. Enable App Check (CRITICAL)
**Current Status:** ⚠️ Disabled for development

**Action Required:**
```swift
// In AppDelegate.swift, uncomment the App Check configuration:

#if DEBUG
let providerFactory = AppCheckDebugProviderFactory()
AppCheck.setAppCheckProviderFactory(providerFactory)
#else
let providerFactory = DeviceCheckProviderFactory()
AppCheck.setAppCheckProviderFactory(providerFactory)
#endif
```

**Steps:**
1. Go to Firebase Console → App Check
2. Register your app
3. For iOS: Enable DeviceCheck provider
4. For debugging: Add debug tokens as needed
5. Update Firestore Security Rules to require App Check

### 2. Update Info.plist Privacy Keys

**Required Keys:**
```xml
<!-- Location Services -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>AMENAPP needs your location to find churches near you and provide personalized recommendations based on your area.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>AMENAPP uses your location to send you helpful notifications when you're near a saved church and to help you discover new churches nearby.</string>

<!-- Notifications -->
<key>NSUserNotificationsUsageDescription</key>
<string>AMENAPP sends reminders for upcoming church services, weekly notifications, and alerts when you're near your saved churches.</string>

<!-- Camera (if using photo features) -->
<key>NSCameraUsageDescription</key>
<string>AMENAPP needs camera access to take photos for posts and profile pictures.</string>

<!-- Photo Library -->
<key>NSPhotoLibraryUsageDescription</key>
<string>AMENAPP needs access to your photo library to select images for posts and profile.</string>
```

### 3. Firebase Security Rules Review

**Firestore Rules:**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Require authentication
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Require App Check (ENABLE IN PRODUCTION)
    function passesAppCheck() {
      return request.app != null; // Uncomment for production
    }
    
    // Users collection
    match /users/{userId} {
      allow read: if isAuthenticated();
      allow write: if isAuthenticated() && request.auth.uid == userId;
    }
    
    // Posts collection
    match /posts/{postId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update, delete: if isAuthenticated() && 
        request.auth.uid == resource.data.authorId;
    }
    
    // Church notes
    match /churchNotes/{noteId} {
      allow read, write: if isAuthenticated() && 
        request.auth.uid == resource.data.userId;
    }
    
    // Messages
    match /messages/{messageId} {
      allow read, write: if isAuthenticated();
    }
  }
}
```

**Realtime Database Rules:**
```json
{
  "rules": {
    ".read": "auth != null",
    ".write": "auth != null",
    "users": {
      "$uid": {
        ".read": "auth != null",
        ".write": "auth.uid === $uid"
      }
    }
  }
}
```

### 4. App Store Configuration

#### App Information
- [ ] App name: AMENAPP
- [ ] Bundle ID: Verify matches Firebase project
- [ ] Version: Set to 1.0.0
- [ ] Build number: Set appropriately
- [ ] Category: Social Networking / Lifestyle
- [ ] Privacy Policy URL: Required
- [ ] Terms of Service URL: Recommended

#### App Store Connect
- [ ] Create app in App Store Connect
- [ ] Add app description
- [ ] Add keywords for SEO
- [ ] Upload screenshots (required sizes)
- [ ] Upload app preview video (optional)
- [ ] Set age rating
- [ ] Configure in-app purchases (if any)
- [ ] Set pricing

#### Certificates & Provisioning
- [ ] Production certificate created
- [ ] Production provisioning profile
- [ ] Push notification certificate configured
- [ ] Capabilities enabled:
  - Push Notifications
  - Background Modes (Location, Remote notifications)
  - Sign in with Apple (if using)

### 5. Testing Requirements

#### Functional Testing
- [ ] User registration flow
- [ ] Login/Logout
- [ ] Google Sign-In
- [ ] Profile creation/editing
- [ ] Post creation with images
- [ ] Like/Comment functionality
- [ ] Follow/Unfollow
- [ ] Church search (on real device)
- [ ] Save church
- [ ] Receive church notifications
- [ ] Push notifications
- [ ] Offline functionality
- [ ] Data persistence

#### Device Testing
- [ ] iPhone SE (smallest screen)
- [ ] iPhone 14/15 Pro Max (largest screen)
- [ ] iPad (if supporting)
- [ ] iOS 16 minimum version
- [ ] iOS 17+ latest features
- [ ] Different network conditions
- [ ] Airplane mode (offline)
- [ ] Low battery mode
- [ ] Different regions/languages

#### Performance Testing
- [ ] App launch time < 2 seconds
- [ ] Smooth scrolling (60 FPS)
- [ ] Image loading performance
- [ ] Memory usage reasonable
- [ ] No memory leaks
- [ ] Battery consumption acceptable
- [ ] Network efficiency

### 6. Analytics & Monitoring

#### Firebase Analytics
- [ ] Set up Analytics events
- [ ] Track key user actions
- [ ] Monitor crash-free users
- [ ] Set up conversion funnels

#### Crashlytics
- [ ] Enable Firebase Crashlytics
- [ ] Test crash reporting
- [ ] Set up alert notifications

#### Performance Monitoring
- [ ] Enable Firebase Performance
- [ ] Monitor API response times
- [ ] Track screen rendering
- [ ] Monitor network requests

### 7. Legal & Compliance

- [ ] Privacy Policy created and published
- [ ] Terms of Service created
- [ ] COPPA compliance (if targeting kids)
- [ ] GDPR compliance (EU users)
- [ ] California Privacy Rights Act (CCPA)
- [ ] Data deletion policy
- [ ] User data export capability

### 8. App Store Optimization (ASO)

- [ ] Compelling app icon
- [ ] Engaging screenshots
- [ ] Effective app description
- [ ] Keyword optimization
- [ ] Localization (if targeting multiple regions)
- [ ] What's New descriptions

### 9. Marketing Preparation

- [ ] Landing page created
- [ ] Social media accounts
- [ ] Press kit prepared
- [ ] Beta testing with TestFlight
- [ ] Gather early user feedback
- [ ] Plan launch strategy

### 10. Post-Launch Monitoring

- [ ] Monitor crash reports daily
- [ ] Track user reviews
- [ ] Monitor server costs
- [ ] Check Firebase usage
- [ ] Respond to user feedback
- [ ] Plan feature updates

## 🔥 Critical Production Changes

### AppDelegate.swift
```swift
// BEFORE PRODUCTION: Uncomment App Check configuration
// Line ~35-55 in AppDelegate.swift
```

### Firebase Console
1. Enable App Check
2. Review security rules
3. Set up billing alerts
4. Configure usage quotas
5. Enable Crashlytics

### Xcode Project
1. Switch to Release build configuration
2. Disable debug logging in production
3. Set appropriate optimization level
4. Strip debug symbols
5. Enable bitcode (if required)

## 📊 Monitoring Dashboard

After launch, monitor these metrics:

### Daily Checks
- Crash-free users percentage (should be > 99%)
- Daily active users (DAU)
- User retention (Day 1, Day 7, Day 30)
- Critical errors

### Weekly Reviews
- User growth rate
- Feature usage analytics
- Performance metrics
- Server costs
- User reviews and ratings

### Monthly Analysis
- Monthly active users (MAU)
- Engagement metrics
- Conversion rates
- Churn analysis
- Revenue (if applicable)

## 🚀 Launch Checklist

**Final Steps Before Submit:**

1. [ ] Run final tests on physical devices
2. [ ] Enable App Check
3. [ ] Review all console logs (remove debug prints)
4. [ ] Update version number
5. [ ] Archive and validate build
6. [ ] Submit to App Store Connect
7. [ ] Submit for review
8. [ ] Prepare support channels
9. [ ] Plan launch announcement
10. [ ] Celebrate! 🎉

## 📞 Support Preparation

- [ ] Set up support email
- [ ] Create FAQ section
- [ ] Prepare common issue responses
- [ ] Set up user feedback mechanism
- [ ] Plan update schedule

---

## Quick Reference

### Key Files to Review
- `AppDelegate.swift` - Enable App Check
- `Info.plist` - Add privacy descriptions
- `Firebase Console` - Security rules, App Check
- `App Store Connect` - App information, screenshots

### Support Contacts
- **Firebase Support:** Firebase Console → Support
- **App Store Support:** App Store Connect → Contact Support
- **TestFlight:** For beta testing

### Useful Links
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Firebase Documentation](https://firebase.google.com/docs)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

---

**Last Updated:** February 2, 2026
**Version:** 1.0
**Status:** Pre-Production

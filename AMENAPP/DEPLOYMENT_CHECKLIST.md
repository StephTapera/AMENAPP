# ✅ Deployment Checklist - Track Your Progress

Use this checklist to track your deployment progress. Check off each item as you complete it.

---

## 📋 Pre-Deployment Checklist

### Prerequisites
- [ ] Node.js installed (v18 or higher)
  ```bash
  node --version  # Should show v18.0.0 or higher
  ```

- [ ] npm installed
  ```bash
  npm --version
  ```

- [ ] Firebase CLI installed
  ```bash
  firebase --version  # Should show 12.0.0 or higher
  ```

- [ ] Logged into Firebase
  ```bash
  firebase login
  ```

- [ ] Firebase project exists
  ```bash
  firebase projects:list
  ```

---

## 🔧 Setup Phase (10 minutes)

### Project Configuration
- [ ] Navigated to project directory
  ```bash
  cd /path/to/AMENAPP
  ```

- [ ] Selected correct Firebase project
  ```bash
  firebase use your-project-id
  ```

- [ ] Verified `functions` directory exists
  ```bash
  ls -la functions/
  ```

- [ ] Verified `functions/index.js` or `functions/index.ts` exists

- [ ] Verified `functions/package.json` exists

### Dependencies
- [ ] Installed Node modules in functions directory
  ```bash
  cd functions && npm install
  ```

- [ ] No errors during npm install

- [ ] `node_modules` directory created

---

## 🚀 Deployment Phase (10 minutes)

### Deploy Functions
- [ ] Deployed all Cloud Functions
  ```bash
  firebase deploy --only functions
  ```

- [ ] Deployment completed without errors

- [ ] Saw "✔ Deploy complete!" message

- [ ] All functions listed as deployed:
  - [ ] `onFollowCreated`
  - [ ] `onAmenCreated`
  - [ ] `onCommentCreated`
  - [ ] `onMessageCreated`
  - [ ] `createConversation`
  - [ ] `sendMessage`
  - [ ] `markMessagesAsRead`
  - [ ] `deleteMessage`
  - [ ] `cleanupTypingIndicators`

### Verify Deployment
- [ ] Checked deployed functions list
  ```bash
  firebase functions:list
  ```

- [ ] All functions show in Firebase Console
  - Go to: https://console.firebase.google.com/
  - Navigate to: Build → Functions

- [ ] No errors in function logs
  ```bash
  firebase functions:log
  ```

---

## 🔑 API Configuration (5 minutes)

### Enable Required APIs
- [ ] Cloud Functions API enabled
  ```bash
  gcloud services enable cloudfunctions.googleapis.com
  ```

- [ ] Cloud Messaging API enabled
  ```bash
  gcloud services enable fcm.googleapis.com
  ```

- [ ] Cloud Scheduler API enabled
  ```bash
  gcloud services enable cloudscheduler.googleapis.com
  ```

**OR** check in Google Cloud Console:
- [ ] Visited: https://console.cloud.google.com/
- [ ] Selected correct project
- [ ] Went to: APIs & Services → Enabled APIs
- [ ] Verified all three APIs are enabled

---

## 📱 iOS Configuration (10 minutes)

### Xcode Capabilities
- [ ] Opened project in Xcode

- [ ] Selected app target

- [ ] Went to Signing & Capabilities tab

- [ ] Added Push Notifications capability
  - [ ] Clicked + Capability
  - [ ] Selected Push Notifications

- [ ] Added Background Modes capability
  - [ ] Clicked + Capability
  - [ ] Selected Background Modes
  - [ ] Checked ✅ Remote notifications

### AppDelegate Configuration
- [ ] Verified `AppDelegate.swift` exists

- [ ] Imported Firebase Messaging
  ```swift
  import FirebaseMessaging
  ```

- [ ] Set up notification delegates in `didFinishLaunchingWithOptions`

- [ ] Implemented FCM token handling

- [ ] App successfully builds without errors

---

## 🔐 APNs Configuration (15 minutes)

### Create APNs Key (Apple Developer Portal)
- [ ] Visited: https://developer.apple.com/account/resources/authkeys/list

- [ ] Clicked + to create new key

- [ ] Named key (e.g., "AMENAPP Push Notifications")

- [ ] Selected ✅ Apple Push Notifications service (APNs)

- [ ] Clicked Continue → Register → Download

- [ ] Downloaded `.p8` file

- [ ] **SAVED `.p8` FILE SAFELY** (can only download once!)

- [ ] Noted Key ID (10 characters, e.g., ABC123XYZ0)

- [ ] Noted Team ID (from top right of page)

### Upload APNs Key to Firebase
- [ ] Went to: https://console.firebase.google.com/

- [ ] Selected project

- [ ] Clicked ⚙️ Project Settings

- [ ] Went to Cloud Messaging tab

- [ ] Found "Apple app configuration" section

- [ ] Clicked Upload under APNs Authentication Key

- [ ] Selected downloaded `.p8` file

- [ ] Entered Key ID

- [ ] Entered Team ID

- [ ] Clicked Upload

- [ ] Saw success message: "APNs authentication key uploaded successfully"

---

## 🧪 Testing Phase (15 minutes)

### Build and Run App
- [ ] Built app on physical device (not simulator)
  - ⚠️ **Must use physical device for push notifications**

- [ ] App launched successfully

- [ ] Notification permission prompt appeared

- [ ] Granted notification permissions

- [ ] Checked Xcode console for FCM token
  - Should see: "🔑 FCM Token: ..."

- [ ] FCM token saved to Firestore
  - Check: `/users/{userId}/fcmToken` in Firestore Console

### Test Notifications from Firebase Console
- [ ] Went to: Firebase Console → Cloud Messaging

- [ ] Clicked "Send your first message"

- [ ] Entered test message: "Test from Firebase"

- [ ] Clicked "Send test message"

- [ ] Entered app bundle ID

- [ ] Pasted FCM token from Xcode console

- [ ] Clicked Test

- [ ] **RECEIVED TEST NOTIFICATION ON DEVICE** ✅

### Test Notifications from App
- [ ] Opened app on device

- [ ] Navigated to: Profile → Settings → Notifications

- [ ] Tapped "Send Test Notification" button

- [ ] **RECEIVED TEST NOTIFICATION** ✅

- [ ] Notification appeared in:
  - [ ] Lock screen
  - [ ] Notification center
  - [ ] Banner (if app in foreground)

### Test Automatic Notification Triggers

#### Follow Notification
- [ ] User A followed User B

- [ ] User B received notification: "User A started following you"

- [ ] Notification showed in app

- [ ] Badge count updated

#### Amen Notification
- [ ] User A said Amen to User B's post

- [ ] User B received notification: "User A said Amen to your post"

- [ ] Tapped notification

- [ ] Opened correct post

#### Comment Notification
- [ ] User A commented on User B's post

- [ ] User B received notification with comment preview

- [ ] Tapped notification

- [ ] Opened post with comments visible

#### Message Notification
- [ ] User A sent message to User B

- [ ] User B received notification: "User A sent you a message"

- [ ] Tapped notification

- [ ] Opened conversation

---

## 🎨 UI Integration (5 minutes)

### Add NotificationsView to App
- [ ] Added `NotificationsView.swift` to project

- [ ] Added NotificationsView to navigation
  - **Option 1:** Added to TabView
  - **Option 2:** Added as navigation button
  - **Option 3:** Added as full screen modal

- [ ] Built app successfully

- [ ] Opened NotificationsView

- [ ] Saw notifications list

- [ ] Pull-to-refresh works

- [ ] Swipe-to-delete works

- [ ] Mark as read works

- [ ] Unread badge shows correctly

---

## 📊 Monitoring & Verification (5 minutes)

### Check Function Logs
- [ ] Viewed function logs in terminal
  ```bash
  firebase functions:log --follow
  ```

- [ ] Viewed logs in Firebase Console
  - Build → Functions → Select function → Logs tab

- [ ] No errors in logs

- [ ] Functions executing successfully

- [ ] See successful notification deliveries

### Check Firestore Data
- [ ] Opened: Firebase Console → Firestore Database

- [ ] Verified `notifications` collection exists

- [ ] Verified notifications being created when actions occur

- [ ] Verified notification documents have correct structure:
  - [ ] `userId`
  - [ ] `type` (follow, amen, comment, etc.)
  - [ ] `actorId` and `actorName`
  - [ ] `read` (boolean)
  - [ ] `createdAt` (timestamp)

### Check User Data
- [ ] Opened: Firebase Console → Firestore → `users` collection

- [ ] Verified users have `fcmToken` field

- [ ] Verified `notificationSettings` exist for users

- [ ] Verified follower/following counts updating correctly

---

## 🎯 Final Verification (5 minutes)

### App Functionality
- [ ] All existing features still work

- [ ] No crashes or errors

- [ ] App performance is good

- [ ] Battery usage is normal

### Notification System
- [ ] Push notifications arrive within 1-2 seconds

- [ ] In-app notifications update in real-time

- [ ] Badge count is accurate

- [ ] Notification settings persist

- [ ] Users can turn notifications on/off

### User Experience
- [ ] Notifications are relevant and timely

- [ ] Notification text is clear and helpful

- [ ] Tapping notifications navigates correctly

- [ ] Sounds and vibrations work as expected

- [ ] No duplicate notifications

---

## 📈 Post-Deployment (Ongoing)

### Day 1
- [ ] Monitor function logs for errors
  ```bash
  firebase functions:log --follow
  ```

- [ ] Check notification delivery rate

- [ ] Verify no spam or duplicate notifications

- [ ] Test with multiple users

- [ ] Gather user feedback

### Week 1
- [ ] Review function execution times
  - Firebase Console → Functions → Metrics

- [ ] Check for any failed invocations

- [ ] Monitor costs (should be $0 on free tier)
  - Google Cloud Console → Billing

- [ ] Analyze notification engagement
  - How many users tap notifications?
  - Which notification types perform best?

### Monthly
- [ ] Update function dependencies
  ```bash
  cd functions && npm update
  ```

- [ ] Review and update moderation rules (if applicable)

- [ ] Check for Firebase/Firestore updates

- [ ] Redeploy if needed
  ```bash
  firebase deploy --only functions
  ```

---

## 🐛 Troubleshooting Checklist

If something doesn't work, check these:

### Functions Not Deploying
- [ ] Firebase CLI is up to date: `npm update -g firebase-tools`
- [ ] Logged into correct account: `firebase login --reauth`
- [ ] Selected correct project: `firebase use your-project-id`
- [ ] No syntax errors in functions code
- [ ] Dependencies installed: `cd functions && npm install`

### Notifications Not Received
- [ ] APNs key uploaded to Firebase correctly
- [ ] App has notification permissions enabled
- [ ] FCM token exists in Firestore for user
- [ ] User has notification type enabled in settings
- [ ] Testing on physical device (not simulator)
- [ ] Function logs show notification was sent

### Functions Failing
- [ ] Check function logs: `firebase functions:log`
- [ ] Required APIs are enabled
- [ ] Firestore security rules allow function access
- [ ] Function has correct triggers configured
- [ ] No timeout errors (increase function timeout if needed)

### App Crashes
- [ ] Check Xcode console for error messages
- [ ] Verify all imports are correct
- [ ] Clean build folder: Product → Clean Build Folder
- [ ] Delete derived data
- [ ] Reinstall pods (if using CocoaPods)

---

## 🎉 Success Criteria

Your deployment is successful when ALL of these are true:

- ✅ All 9 Cloud Functions deployed successfully
- ✅ No errors in function logs
- ✅ Test notification received from Firebase Console
- ✅ Test notification received from app
- ✅ All 4 automatic notifications work (follow, amen, comment, message)
- ✅ NotificationsView shows notifications
- ✅ Badge count updates correctly
- ✅ App is stable with no crashes
- ✅ Users can control notification settings
- ✅ Notification delivery is fast (< 2 seconds)

**If all checked: CONGRATULATIONS! Your notification system is LIVE! 🎊**

---

## 📊 Deployment Summary

**Time Breakdown:**
- Pre-deployment: 10 minutes
- Setup: 10 minutes
- Deployment: 10 minutes
- API configuration: 5 minutes
- iOS configuration: 10 minutes
- APNs configuration: 15 minutes
- Testing: 15 minutes
- UI integration: 5 minutes
- Monitoring: 5 minutes
- **Total: ~85 minutes**

**What You Deployed:**
- ✅ 9 Cloud Functions
- ✅ Push notification system
- ✅ In-app notification UI
- ✅ Real-time notification delivery
- ✅ User notification preferences

**What You Get:**
- ✅ Automatic notifications for follows, amens, comments, messages
- ✅ Real-time delivery (< 2 seconds)
- ✅ Badge count on app icon
- ✅ Beautiful in-app notifications
- ✅ User control over notification settings
- ✅ Scalable to thousands of users
- ✅ $0 cost on free tier

---

## 📞 Need Help?

If you're stuck on any step:

1. **Check the detailed guides:**
   - `DEPLOY_NOW.md` - Step-by-step deployment
   - `TERMINAL_COMMANDS.md` - All commands you need
   - `NOTIFICATIONS_INTEGRATION_GUIDE.md` - UI integration

2. **Check logs for errors:**
   ```bash
   firebase functions:log --follow
   ```

3. **Verify basics:**
   - Firebase CLI version: `firebase --version`
   - Node version: `node --version`
   - Logged in: `firebase projects:list`
   - Correct project: `firebase use`

4. **Common issues:**
   - "Firebase command not found" → Reinstall CLI
   - "Permission denied" → Run `firebase login --reauth`
   - "Functions failed" → Check function logs
   - "No notifications" → Verify APNs key and FCM token

---

**Print this checklist and check off items as you go!** ✅

Good luck with your deployment! 🚀

# 🔥 Firebase Cloud Functions Setup Guide for AMEN App

## Overview

Firebase Cloud Functions have been implemented to automate critical backend tasks for your AMEN app. This eliminates manual work and improves user experience.

---

## ✨ What's Included

### 1. **Auto-Update User Search Fields** ✅
- **What it does**: Automatically creates `usernameLowercase` and `displayNameLowercase` whenever users update their profile
- **Benefit**: No more manual user migration needed! Search works automatically for all users

### 2. **Follower/Following Count Updates** 📊
- **What it does**: Keeps follower and following counts accurate in real-time
- **Benefit**: Accurate stats without manual recalculation

### 3. **Push Notifications** 🔔
- **What it does**: Sends notifications for:
  - New followers
  - Amens on posts
  - Comments on posts
  - Prayer reminders
- **Benefit**: Users stay engaged and connected

### 4. **Engagement Count Updates** 💬
- **What it does**: Auto-updates counts for:
  - Amens
  - Comments
  - Reposts
- **Benefit**: Accurate engagement metrics without extra queries

### 5. **Content Moderation** 🛡️
- **What it does**: Automatically flags inappropriate content and detects spam
- **Benefit**: Keeps community safe with minimal manual moderation

### 6. **Prayer Request Reminders** 🙏
- **What it does**: Sends daily reminders to users who committed to pray
- **Benefit**: Helps users fulfill their prayer commitments

### 7. **Weekly Community Stats** 📈
- **What it does**: Generates weekly statistics every Monday
- **Benefit**: Track community growth and engagement

### 8. **Personalized Feed Generation** 📰
- **What it does**: Creates optimized feeds based on who users follow
- **Benefit**: Better user experience with relevant content

### 9. **Content Reporting** 🚩
- **What it does**: Handles user reports of inappropriate content
- **Benefit**: Community-driven moderation

---

## 🚀 Setup Instructions

### Prerequisites

1. Install Node.js (v18 or higher)
2. Install Firebase CLI:
```bash
npm install -g firebase-tools
```

3. Login to Firebase:
```bash
firebase login
```

---

### Step 1: Initialize Firebase Functions

Navigate to your project directory:

```bash
cd /path/to/AMENAPP
```

Initialize Firebase Functions (if not already done):

```bash
firebase init functions
```

**When prompted:**
- Choose "JavaScript" (not TypeScript)
- Install dependencies with npm: **Yes**
- Select your existing Firebase project

---

### Step 2: Copy Function Files

The function files have already been created in your project:

```
functions/
├── index.js       # All Cloud Functions code
└── package.json   # Dependencies
```

If they're not in the right location, move them:

```bash
# If files are in root, move them
mv functions/*.js functions/
mv functions/package.json functions/
```

---

### Step 3: Install Dependencies

```bash
cd functions
npm install
```

This installs:
- `firebase-admin` - Firebase Admin SDK
- `firebase-functions` - Cloud Functions SDK

---

### Step 4: Deploy Functions

Deploy all functions to Firebase:

```bash
firebase deploy --only functions
```

**Deployment takes 5-10 minutes.** You'll see output like:

```
✔  functions: Finished running predeploy script.
i  functions: ensuring required API cloudfunctions.googleapis.com is enabled...
i  functions: ensuring required API cloudbuild.googleapis.com is enabled...
✔  functions: required API cloudfunctions.googleapis.com is enabled
✔  functions: required API cloudbuild.googleapis.com is enabled
i  functions: preparing functions directory for uploading...
i  functions: packaged functions (XX KB) for uploading
✔  functions: functions folder uploaded successfully
i  functions: creating Node.js 18 function updateUserSearchFields(us-central1)...
✔  functions[updateUserSearchFields(us-central1)] Successful create operation.
...
✔  Deploy complete!
```

---

### Step 5: Enable Required APIs

Some functions require additional Firebase/Google Cloud APIs:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your Firebase project
3. Enable these APIs:
   - **Cloud Functions API** (should be auto-enabled)
   - **Cloud Scheduler API** (for scheduled functions)
   - **Cloud Pub/Sub API** (for notifications)
   - **Cloud Messaging API** (for push notifications)

Or use CLI:

```bash
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable fcm.googleapis.com
```

---

### Step 6: Configure Push Notifications in iOS

Add Firebase Cloud Messaging to your app:

1. **Add to your Podfile** (if using CocoaPods):
```ruby
pod 'Firebase/Messaging'
```

Then run:
```bash
pod install
```

2. **Update AppDelegate** - Already done in your code!

---

### Step 7: Test Functions Locally (Optional)

Test functions before deploying:

```bash
cd functions
npm run serve
```

This starts the Firebase emulator. You can test functions at:
```
http://localhost:5001/your-project-id/us-central1/functionName
```

---

## 📊 Monitoring Functions

### View Function Logs

```bash
firebase functions:log
```

Or in Firebase Console:
1. Go to **Firebase Console** > **Functions**
2. Click on any function
3. View logs, metrics, and errors

### Check Function Status

Firebase Console > Functions shows:
- ✅ Deployed functions
- 📊 Invocation count
- ⏱️ Average execution time
- ❌ Error rate

---

## 💰 Cost

### Free Tier (Spark Plan)
- 2M invocations/month
- 400K GB-seconds compute time
- 200K CPU-seconds compute time
- 5GB outbound data

### Your Expected Usage (Small App)

With 1,000 active users:
- User profile updates: ~5K/month
- Follow actions: ~10K/month
- Post interactions: ~50K/month
- Notifications: ~50K/month
- Scheduled functions: ~120/month (daily + weekly)

**Total: ~115K invocations/month**

You'll stay **well within the free tier**! 🎉

---

## 🔧 Managing Functions

### Update a Function

1. Edit `functions/index.js`
2. Deploy:
```bash
firebase deploy --only functions:functionName
```

### Deploy All Functions

```bash
firebase deploy --only functions
```

### Delete a Function

```bash
firebase functions:delete functionName
```

Or remove from `index.js` and redeploy.

---

## 🧪 Testing

### Test Auto-Update Search Fields

1. Update a user's display name in your app
2. Check Firestore - `displayNameLowercase` should auto-update
3. Check function logs:
```bash
firebase functions:log --only updateUserSearchFields
```

### Test Follower Count

1. Follow someone in your app
2. Check both users' `followersCount` and `followingCount`
3. Should update immediately

### Test Notifications

1. Have User A amen User B's post
2. User B should receive a push notification
3. Check `notifications` collection for in-app notification

---

## 🐛 Troubleshooting

### Function Not Triggering

**Issue**: Function deployed but not running

**Solutions**:
1. Check function logs for errors:
```bash
firebase functions:log
```

2. Verify function is deployed:
```bash
firebase functions:list
```

3. Check Firestore triggers match your collection names

### Permission Errors

**Issue**: "Missing or insufficient permissions"

**Solution**: Functions run with admin privileges by default, but check:
1. Firebase Console > **Rules**
2. Ensure service account has proper permissions

### Scheduled Functions Not Running

**Issue**: Prayer reminders or weekly stats not running

**Solution**:
1. Enable **Cloud Scheduler API**
2. Check Cloud Scheduler in Google Cloud Console
3. Verify timezone is correct

### Notification Not Sending

**Issue**: Push notifications not received

**Checklist**:
1. ✅ User has `fcmToken` in Firestore
2. ✅ APNs certificate configured in Firebase
3. ✅ User has notification permissions enabled
4. ✅ User's notification settings allow that type
5. ✅ Test with a simple notification first

---

## 📱 iOS Integration

### Save FCM Token to Firestore

When user logs in, save their FCM token:

```swift
// In your app
import FirebaseMessaging

func saveFCMToken() {
    Messaging.messaging().token { token, error in
        guard let token = token, error == nil else { return }
        
        // Save to Firestore
        let userId = Auth.auth().currentUser?.uid ?? ""
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .updateData(["fcmToken": token])
    }
}
```

This is already implemented in your `AppDelegate.swift`!

---

## 🎯 Key Benefits

### Before Functions ❌
- Manual user migration for search
- Inaccurate follower counts
- No push notifications
- Manual content moderation
- Slow engagement updates

### After Functions ✅
- Automatic search field updates
- Real-time accurate counts
- Push notifications for all interactions
- Automated content moderation
- Instant engagement updates
- Scheduled prayer reminders
- Weekly community stats

---

## 🔄 Maintenance

### Regular Tasks

**Monthly**:
- Review function logs for errors
- Check function performance in Firebase Console
- Review moderation queue

**Quarterly**:
- Update dependencies:
```bash
cd functions
npm update
firebase deploy --only functions
```

**As Needed**:
- Add new moderation keywords
- Adjust notification messages
- Add new function triggers

---

## 📚 Additional Resources

- [Firebase Functions Documentation](https://firebase.google.com/docs/functions)
- [Cloud Functions Pricing](https://firebase.google.com/pricing)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Firebase Cloud Messaging (FCM)](https://firebase.google.com/docs/cloud-messaging)

---

## ✅ Checklist

Before going live, ensure:

- [ ] All functions deployed successfully
- [ ] Cloud Scheduler API enabled
- [ ] FCM configured in Firebase Console
- [ ] APNs certificate uploaded (for iOS notifications)
- [ ] Test notifications working
- [ ] Test search field auto-update
- [ ] Test follower count updates
- [ ] Monitor function logs for errors
- [ ] Set up budget alerts in Google Cloud

---

## 🎉 You're All Set!

Your Firebase Cloud Functions are now automating:
- ✅ User search indexing
- ✅ Engagement counting
- ✅ Push notifications
- ✅ Content moderation
- ✅ Prayer reminders
- ✅ Community stats

**Your app just got 10x more powerful!** 🚀

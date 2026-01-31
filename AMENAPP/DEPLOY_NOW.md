# 🚀 Deploy Cloud Functions - Step by Step

Let's get your notifications working! Follow these steps exactly.

---

## Prerequisites Check

Open Terminal and verify you have the required tools:

```bash
# Check Node.js (need v18 or higher)
node --version

# Check Firebase CLI
firebase --version

# If you don't have Firebase CLI, install it:
npm install -g firebase-tools
```

---

## Step 1: Login to Firebase (2 minutes)

```bash
firebase login
```

This opens your browser. Log in with your Firebase account.

**✅ Expected output:**
```
✔  Success! Logged in as your-email@example.com
```

---

## Step 2: Navigate to Your Project (1 minute)

```bash
# Go to your project directory
cd /path/to/AMENAPP

# Verify you're in the right place - you should see these files:
ls -la
# Should show: AMENAPP.xcodeproj, functions/, firebase.json, etc.
```

---

## Step 3: Check Firebase Project (1 minute)

```bash
# List your Firebase projects
firebase projects:list

# Set the correct project
firebase use your-project-id
```

Replace `your-project-id` with your actual Firebase project ID.

**✅ Expected output:**
```
Now using alias default (your-project-name)
```

---

## Step 4: Check Functions Directory (1 minute)

```bash
# Navigate to functions directory
cd functions

# Check what files exist
ls -la
```

**You should see:**
- `index.js` or `index.ts` - Your Cloud Functions code
- `package.json` - Dependencies
- `.gitignore`

**If you DON'T see these files**, you need to initialize functions first:

```bash
# Go back to project root
cd ..

# Initialize functions
firebase init functions

# When prompted:
# - Use an existing project: YES
# - Language: JavaScript (or TypeScript if you prefer)
# - ESLint: Your choice (I recommend Yes)
# - Install dependencies: YES
```

---

## Step 5: Install Dependencies (2 minutes)

```bash
# Make sure you're in the functions directory
cd functions

# Install all dependencies
npm install

# Install specific packages for notifications
npm install firebase-admin firebase-functions --save
```

**✅ Expected output:**
```
added XX packages, and audited YY packages in ZZs
```

---

## Step 6: Deploy Functions (5-10 minutes)

This is the big one! Deploy all your Cloud Functions:

```bash
# From the functions directory, go back to project root
cd ..

# Deploy ONLY functions (not hosting, storage, etc.)
firebase deploy --only functions
```

**What you'll see:**
```
i  functions: preparing functions directory for uploading...
i  functions: packaged functions (XX.XX KB) for uploading
✔  functions: functions folder uploaded successfully
i  functions: creating Node.js 18 function onFollowCreated(us-central1)...
i  functions: creating Node.js 18 function onAmenCreated(us-central1)...
i  functions: creating Node.js 18 function onCommentCreated(us-central1)...
i  functions: creating Node.js 18 function onMessageCreated(us-central1)...
✔  functions[onFollowCreated(us-central1)]: Successful create operation.
✔  functions[onAmenCreated(us-central1)]: Successful create operation.
✔  functions[onCommentCreated(us-central1)]: Successful create operation.
✔  functions[onMessageCreated(us-central1)]: Successful create operation.

✔  Deploy complete!
```

**This deploys:**
- ✅ `onFollowCreated` - Sends notification when someone follows you
- ✅ `onAmenCreated` - Sends notification when someone says Amen
- ✅ `onCommentCreated` - Sends notification when someone comments
- ✅ `onMessageCreated` - Sends notification for new messages
- ✅ Other helper functions

**⏱️ Time: 5-10 minutes**

---

## Step 7: Verify Deployment (2 minutes)

Check that your functions were deployed successfully:

```bash
# List all deployed functions
firebase functions:list
```

**✅ Expected output:**
```
onFollowCreated (us-central1)
onAmenCreated (us-central1)
onCommentCreated (us-central1)
onMessageCreated (us-central1)
createConversation (us-central1)
sendMessage (us-central1)
markMessagesAsRead (us-central1)
deleteMessage (us-central1)
cleanupTypingIndicators (us-central1)
```

**OR** check in Firebase Console:
1. Go to https://console.firebase.google.com/
2. Select your project
3. Go to **Build** → **Functions**
4. You should see all deployed functions listed

---

## Step 8: Enable Required APIs (3 minutes)

Some Google Cloud APIs need to be enabled:

```bash
# Enable Cloud Functions API
gcloud services enable cloudfunctions.googleapis.com

# Enable Cloud Messaging API (for notifications)
gcloud services enable fcm.googleapis.com

# Enable Cloud Scheduler API (for scheduled functions)
gcloud services enable cloudscheduler.googleapis.com
```

**OR** enable in Google Cloud Console:
1. Go to https://console.cloud.google.com/
2. Select your Firebase project
3. Go to **APIs & Services** → **Enable APIs and Services**
4. Search for and enable:
   - Cloud Functions API
   - Firebase Cloud Messaging API
   - Cloud Scheduler API

---

## Step 9: Configure Push Notifications in Xcode (5 minutes)

### A. Add Capabilities

1. Open your project in Xcode
2. Select your app target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Push Notifications**
6. Add **Background Modes**
   - Check ✅ **Remote notifications**

### B. Verify Code

Your `AppDelegate.swift` should already have Firebase Messaging configured. If not, add:

```swift
import FirebaseMessaging
import UserNotifications

// In application(_:didFinishLaunchingWithOptions:)
UNUserNotificationCenter.current().delegate = self
Messaging.messaging().delegate = self

// Request notification permission
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
    print(granted ? "✅ Notifications authorized" : "❌ Notifications denied")
}

// Register for remote notifications
application.registerForRemoteNotifications()
```

---

## Step 10: Create APNs Key (10 minutes)

For iOS push notifications to work, you need an Apple Push Notification service (APNs) authentication key:

### A. Create APNs Key in Apple Developer

1. Go to https://developer.apple.com/account/resources/authkeys/list
2. Click **+** (Create a new key)
3. Enter a key name (e.g., "AMENAPP Push Notifications")
4. Check ✅ **Apple Push Notifications service (APNs)**
5. Click **Continue** → **Register** → **Download**
6. **IMPORTANT:** Save the `.p8` file somewhere safe (you can only download it once!)
7. Note your **Key ID** (10 characters, like `ABC123XYZ0`)
8. Note your **Team ID** (in the top right of the page)

### B. Upload to Firebase

1. Go to Firebase Console → Your Project
2. Click ⚙️ **Project Settings** (gear icon)
3. Go to **Cloud Messaging** tab
4. Scroll to **Apple app configuration**
5. Under **APNs Authentication Key**, click **Upload**
6. Select your downloaded `.p8` file
7. Enter your **Key ID** (from step A.7)
8. Enter your **Team ID** (from step A.8)
9. Click **Upload**

**✅ You should see:** "APNs authentication key uploaded successfully"

---

## Step 11: Test Notifications (5 minutes)

### Test from Firebase Console

1. Firebase Console → **Cloud Messaging**
2. Click **Send your first message**
3. Enter notification text: "Test notification from AMEN"
4. Click **Send test message**
5. Enter your app's bundle ID
6. Add an FCM token:
   - Run your app on a device
   - Check Xcode console for "🔑 FCM Token: ..."
   - Copy and paste that token
7. Click **Test**

**✅ You should receive a notification on your device!**

### Test from App

Build and run your app on a **physical device** (not simulator):

1. Build app → Physical device
2. Allow notifications when prompted
3. Go to **Profile** → **Settings** → **Notifications**
4. Tap **Send Test Notification**
5. You should receive a notification!

---

## Step 12: Test Real Notifications (5 minutes)

Test the automatic notification triggers:

### Test Follow Notification

1. **User A** (you on device 1): Follow **User B** (another account)
2. **User B** should receive notification: "User A started following you"

### Test Amen Notification

1. **User A**: Say Amen to **User B's** post
2. **User B** should receive: "User A said Amen to your post"

### Test Comment Notification

1. **User A**: Comment on **User B's** post
2. **User B** should receive: "User A commented on your post: [comment text]"

### Test Message Notification

1. **User A**: Send message to **User B**
2. **User B** should receive: "User A sent you a message"

---

## Troubleshooting

### ❌ "Firebase command not found"

**Solution:**
```bash
npm install -g firebase-tools
```

### ❌ "Not authorized to perform this action"

**Solution:**
```bash
firebase login --reauth
```

### ❌ "Missing required API: cloudfunctions.googleapis.com"

**Solution:**
```bash
gcloud services enable cloudfunctions.googleapis.com
```

Or enable in Google Cloud Console (see Step 8).

### ❌ "Functions deployment failed"

**Solution:**
```bash
# Check function logs for errors
firebase functions:log

# Try deploying one function at a time
firebase deploy --only functions:onFollowCreated
```

### ❌ "No FCM token"

**Solution:**
- Make sure you're testing on a **physical device** (not simulator)
- Check that user granted notification permissions
- Verify `AppDelegate` is configured correctly
- Check Xcode console for FCM token

### ❌ "APNs certificate invalid"

**Solution:**
- Make sure you uploaded a `.p8` file (not `.cer` or `.p12`)
- Verify Key ID and Team ID are correct
- Download a new APNs key if needed

---

## View Function Logs

To see what's happening with your functions:

```bash
# View all function logs
firebase functions:log

# Follow logs in real-time
firebase functions:log --follow

# View specific function
firebase functions:log --only onFollowCreated
```

---

## Cost Estimate

Your Cloud Functions usage will be **FREE** for most apps:

**Free Tier (per month):**
- 2M function invocations
- 400K GB-seconds compute time
- 200K CPU-seconds compute time

**Expected Usage (1,000 active users):**
- ~100K notifications/month
- ~50K message operations/month
- **Total:** ~150K invocations/month

**You're well within the free tier!** 🎉

**At 10,000 users:** ~$5-10/month
**At 100,000 users:** ~$30-50/month

---

## ✅ Deployment Checklist

Check off each item as you complete it:

- [ ] Node.js installed (v18+)
- [ ] Firebase CLI installed
- [ ] Logged into Firebase (`firebase login`)
- [ ] Selected correct project (`firebase use your-project-id`)
- [ ] Dependencies installed (`npm install` in functions/)
- [ ] Functions deployed (`firebase deploy --only functions`)
- [ ] Cloud Functions API enabled
- [ ] Cloud Messaging API enabled
- [ ] Push Notifications capability added in Xcode
- [ ] Background Modes enabled in Xcode
- [ ] APNs key created in Apple Developer
- [ ] APNs key uploaded to Firebase
- [ ] Test notification sent from Firebase Console
- [ ] Test notification sent from app
- [ ] Real notification tested (follow, amen, comment, message)
- [ ] Function logs checked for errors
- [ ] NotificationsView added to app

---

## Next Steps

After deployment:

1. **Add NotificationsView to your app** (see NOTIFICATIONS_INTEGRATION_GUIDE.md)
2. **Monitor function logs** for the first few days
3. **Test all notification types**
4. **Set up budget alerts** in Google Cloud Console (optional)
5. **Share with beta testers**

---

## Need Help?

**Check function logs:**
```bash
firebase functions:log --follow
```

**Check for errors in Xcode console:**
- Look for emoji prefixes: ✅ (success), ❌ (error), 📡 (network)

**Test notification delivery:**
- Firebase Console → Cloud Messaging → Send test message

**Verify functions are running:**
- Firebase Console → Functions → Check metrics

---

## Summary

You've deployed:
- ✅ 9 Cloud Functions
- ✅ Automatic notification triggers
- ✅ Push notification infrastructure
- ✅ Real-time messaging backend

**Total time:** ~45-60 minutes
**Cost:** $0 (free tier)

Your notifications are now **LIVE**! 🎉

---

**Questions?** Check the troubleshooting section or review function logs.

**Ready to add the UI?** See `NOTIFICATIONS_INTEGRATION_GUIDE.md`

Good luck! 🚀

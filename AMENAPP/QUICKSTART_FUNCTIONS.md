# ⚡️ Quick Start: Deploy Cloud Functions in 5 Minutes

## Prerequisites
- Node.js installed
- Firebase CLI installed (`npm install -g firebase-tools`)
- Logged into Firebase (`firebase login`)

---

## 🚀 Deployment Steps

### 1. Install Dependencies (1 minute)
```bash
cd functions
npm install
```

### 2. Deploy to Firebase (3-5 minutes)
```bash
firebase deploy --only functions
```

Wait for deployment to complete. You'll see:
```
✔  Deploy complete!
```

### 3. Enable APIs (30 seconds)
```bash
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable fcm.googleapis.com
```

### 4. Configure Push Notifications (1 minute)
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to **Project Settings** > **Cloud Messaging**
4. Upload your APNs Auth Key (.p8 file)
5. Enter Key ID and Team ID

---

## ✅ That's It!

Your functions are now live and will automatically:
- ✅ Update user search fields when profiles change
- ✅ Send push notifications for interactions
- ✅ Update engagement counts in real-time
- ✅ Flag inappropriate content
- ✅ Send daily prayer reminders
- ✅ Generate weekly community stats

---

## 🧪 Test It

### Test Search Auto-Update:
1. Update your display name in the app
2. Check Firestore - `displayNameLowercase` field should auto-appear

### Test Notifications:
1. Have a friend amen your post
2. You should receive a push notification

### View Logs:
```bash
firebase functions:log
```

---

## 📊 Monitor

Firebase Console > Functions

See:
- Invocation count
- Execution time
- Error rate
- Logs

---

## 🐛 Issues?

### Functions not deploying:
```bash
# Check for syntax errors
cd functions
npm run lint
```

### Notifications not working:
1. Check APNs certificate is configured
2. Verify user has `fcmToken` in Firestore
3. Test on real device (not simulator)

### View detailed logs:
```bash
firebase functions:log --only functionName
```

---

## 💡 What You Get

With these functions live, your app now has:
- **Zero manual work** for search indexing
- **Automated notifications** for all user interactions
- **Real-time** engagement statistics
- **Built-in** content moderation
- **Scheduled** prayer reminders

All running **automatically** in the cloud! 🎉

---

## 📚 Full Documentation

For detailed information, see:
- `FIREBASE_FUNCTIONS_SETUP.md` - Complete setup guide
- `CLOUD_FUNCTIONS_IMPLEMENTATION_SUMMARY.md` - What's implemented
- `functions/index.js` - Function code with comments

---

**Deploy now:**
```bash
cd functions && npm install && firebase deploy --only functions
```

That's it! 🚀

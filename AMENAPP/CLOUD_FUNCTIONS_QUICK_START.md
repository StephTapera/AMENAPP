# 🚀 Quick Start: Firebase Cloud Functions for AMENAPP

## ⚡️ **Super Quick Setup (5 minutes)**

### Option 1: Automated Script
```bash
chmod +x setup-cloud-functions.sh
./setup-cloud-functions.sh
```

### Option 2: Manual Setup
```bash
# 1. Install Firebase CLI
npm install -g firebase-tools

# 2. Login
firebase login

# 3. Initialize Functions
firebase init functions

# 4. Copy the functions code
# See FIREBASE_CLOUD_FUNCTIONS_DEPLOYMENT_GUIDE.md for code

# 5. Deploy
cd functions
firebase deploy --only functions
```

---

## 📋 **What Gets Deployed**

| Function Name | Trigger | What It Does |
|--------------|---------|--------------|
| `sendFollowNotification` | User follows someone | Sends "You have a new follower" push notification |
| `sendMessageNotification` | New message sent | Sends message notification to recipient |
| `sendSavedSearchNotification` | Content matches saved search | Notifies user of matching content |

---

## ✅ **Verification Steps**

After deploying, test each function:

### 1. Test Follow Notification
```
1. User A follows User B
2. Check Firebase Functions logs
3. User B should receive notification
```

### 2. Test Message Notification
```
1. User A sends message to User B
2. Check logs
3. User B receives notification
```

### 3. Test Saved Search
```
1. User A saves search "prayer for healing"
2. User B creates prayer request with "healing"
3. User A receives notification
```

---

## 🔍 **Monitoring Commands**

```bash
# View all logs
firebase functions:log

# View specific function logs
firebase functions:log --only sendFollowNotification

# Follow logs in real-time
firebase functions:log --continuous

# View errors only
firebase functions:log --filter error
```

---

## 🐛 **Common Issues & Fixes**

### Issue: "Firebase CLI not found"
```bash
npm install -g firebase-tools
```

### Issue: "Permission denied"
```bash
# Enable required APIs in Google Cloud Console
# 1. Go to console.cloud.google.com
# 2. Enable Cloud Functions API
# 3. Enable Cloud Messaging API
```

### Issue: "Function timeout"
Edit `firebase.json`:
```json
{
  "functions": {
    "timeoutSeconds": 60,
    "memory": "256MB"
  }
}
```

### Issue: "No FCM token found"
- User needs to open app while logged in
- `PushNotificationManager` saves token automatically
- Check Firestore: `users/{userId}` should have `fcmToken` field

---

## 💰 **Cost Estimate**

Firebase Cloud Functions pricing for AMENAPP:

**Free Tier (Spark Plan):**
- ✅ 2 million invocations/month
- ✅ 400,000 GB-seconds/month
- ✅ 200,000 CPU-seconds/month

**Estimated Monthly Usage (1,000 active users):**
- Follow notifications: ~5,000 invocations/month
- Message notifications: ~50,000 invocations/month
- Saved search: ~2,000 invocations/month
- **Total: ~57,000 invocations/month** ✅ Well within free tier!

You'll stay in the **free tier** unless you have 10,000+ daily active users.

---

## 📊 **Dashboard**

Monitor your functions:
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select AMENAPP project
3. Click **Functions** → **Dashboard**

You'll see:
- Invocations per hour
- Execution time
- Error rate
- Memory usage

---

## 🔄 **Updating Functions**

When you make changes:

```bash
# Deploy all functions
firebase deploy --only functions

# Deploy specific function
firebase deploy --only functions:sendFollowNotification

# Check deployment status
firebase functions:list
```

---

## 🧪 **Local Testing (Optional)**

Test without deploying:

```bash
# Install emulator
firebase init emulators

# Start emulator
firebase emulators:start

# Your functions now run at:
# http://localhost:5001/your-project/us-central1/sendFollowNotification
```

---

## ⚙️ **Advanced Configuration**

### Set Environment Variables
```bash
firebase functions:config:set notification.enabled=true
firebase functions:config:set notification.quiet_hours.start=22
firebase functions:config:set notification.quiet_hours.end=8
```

### Use in function:
```javascript
const config = functions.config();
const quietStart = config.notification.quiet_hours.start;
```

---

## 📱 **iOS App Integration**

No changes needed! Your app already:
- ✅ Saves FCM tokens (`PushNotificationManager.swift`)
- ✅ Handles notification taps
- ✅ Updates badge counts
- ✅ Shows notifications

Just deploy Cloud Functions and test!

---

## 📚 **Full Documentation**

For complete step-by-step guide, see:
**`FIREBASE_CLOUD_FUNCTIONS_DEPLOYMENT_GUIDE.md`**

---

## 🆘 **Need Help?**

**Firebase Documentation:**
- [Cloud Functions Guide](https://firebase.google.com/docs/functions)
- [FCM Documentation](https://firebase.google.com/docs/cloud-messaging)

**Community:**
- [Stack Overflow](https://stackoverflow.com/questions/tagged/firebase-cloud-functions)
- [Firebase Discord](https://discord.gg/firebase)

---

## ✅ **Post-Deployment Checklist**

- [ ] Functions deployed successfully
- [ ] Verified in Firebase Console
- [ ] Tested follow notification
- [ ] Tested message notification
- [ ] Tested saved search notification
- [ ] Checked error logs
- [ ] Set up budget alerts (optional)
- [ ] Configured monitoring (optional)

---

**Status**: Ready to deploy! 🚀

**Estimated Setup Time**: 5-10 minutes

**Difficulty**: ⭐️⭐️ Easy (following guide)

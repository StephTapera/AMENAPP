# 🚀 QUICK SETUP CHECKLIST

## Xcode Setup (5 minutes)
- [ ] Add **Push Notifications** capability
- [ ] Add **Background Modes** capability (check "Remote notifications")
- [ ] Add FirebaseMessaging package if not already added

## Apple Developer Portal (10 minutes)
- [ ] Create APNs Key (.p8 file)
- [ ] Note your Key ID and Team ID
- [ ] **Download and save .p8 file** (you can only download once!)

## Firebase Console (5 minutes)
- [ ] Go to Project Settings → Cloud Messaging
- [ ] Upload APNs Key (.p8 file)
- [ ] Enter Key ID and Team ID

## Deploy Cloud Functions (5 minutes)
```bash
cd functions
npm install
firebase login
firebase use --add    # Select your project
firebase deploy --only functions
```

## Update Firestore Rules (2 minutes)
```bash
firebase deploy --only firestore:rules
```

## Test on Device (5 minutes)
- [ ] Build and run on **physical device** (not simulator)
- [ ] Allow notification permissions
- [ ] Check console for FCM token
- [ ] Send test notification from app
- [ ] Test real notifications (follow, amen, comment, message)

---

## ✅ Success Indicators

You'll know it's working when you see:

**In Xcode Console:**
```
✅ Firebase configured
✅ Push notification delegates configured
🔑 FCM Token: [long string]
✅ FCM token saved to Firestore
```

**In Firebase Console → Functions:**
```
✔ functions[onFollowCreated] Successful create
✔ functions[onAmenCreated] Successful create
✔ functions[onCommentCreated] Successful create
✔ functions[onMessageCreated] Successful create
```

**On Device:**
- Notification permission alert appears
- Test notification arrives in 5 seconds
- Real notifications arrive when actions occur

---

## 🐛 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| No FCM token | Upload APNs key to Firebase |
| No permission alert | Check capabilities in Xcode |
| Functions deploy fails | Run `npm install` in functions folder |
| Notifications don't arrive | Check user has notifications enabled in-app |
| "Permission denied" error | Deploy Firestore rules |

---

## 📞 Where to Get Help

1. **Function Logs:** `firebase functions:log`
2. **Firebase Console:** Functions dashboard shows errors
3. **Xcode Console:** Shows FCM token and registration status
4. **Device Settings:** Settings → AMENAPP → Notifications

---

## Total Setup Time: ~30 minutes

**After setup, notifications work automatically! No additional configuration needed.** 🎉

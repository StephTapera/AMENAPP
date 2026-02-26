# SafeSearch Deployment - Region Fix Applied ✅

## Issue Found
The Cloud Function was set to deploy in `us-central1` but your Storage bucket is in `us-west1`. This has been **FIXED**.

## What Was Changed
Updated `functions/imageModeration.js` to specify:
```javascript
exports.moderateUploadedImage = onObjectFinalized({
    region: "us-west1",  // ✅ Matches Storage bucket region
    bucket: "amen-5e359.appspot.com"
}, async (event) => {
    // ... function code
});
```

---

## Deployment Commands

Run these commands in your terminal:

### 1. Navigate to project directory
```bash
cd /Users/stephtapera/Desktop/AMEN/AMENAPP\ copy
```

### 2. Deploy the Cloud Function
```bash
firebase deploy --only functions:moderateUploadedImage
```

### 3. Verify deployment
```bash
firebase functions:list
```

You should see:
```
✔ moderateUploadedImage(us-west1)
```

---

## If Deployment Succeeds

### Test It
1. **Upload a test image** to Storage (any folder under `posts/`, `profile_pictures/`, etc.)
2. **Check Cloud Functions logs:**
   ```bash
   firebase functions:log --only moderateUploadedImage
   ```
3. **Look for:**
   - `🛡️ [IMAGE MOD] Processing file: ...`
   - `🔍 SafeSearch results: { adult: ..., racy: ..., ... }`
   - `✅ Image approved: ...` or `❌ BLOCKING image: ...`

### Monitor First 24 Hours
- Check Firestore collection: `imageModerationLogs`
- Check Firestore collection: `moderatorAlerts` (if any images blocked)
- Monitor costs in GCP Console > Vision API

---

## If You Get Errors

### "firebase: command not found"
Install Firebase CLI globally:
```bash
npm install -g firebase-tools
```

Then retry deployment.

### "Insufficient permissions"
Login to Firebase:
```bash
firebase login
```

### "Function already exists in different region"
Delete the old function first:
```bash
firebase functions:delete moderateUploadedImage
```

Then redeploy.

---

## What's Now Active

### Client-Side (Already Working)
- ✅ Profile picture uploads → SafeSearch before upload
- ✅ Post image uploads → SafeSearch before upload
- ✅ User sees instant feedback if blocked

### Server-Side (After Deployment)
- ⏳ Automatic scanning of ALL uploaded images
- ⏳ Auto-delete inappropriate content
- ⏳ Moderator alerts for blocked images
- ⏳ Full audit trail in Firestore

---

## Cost Reminder

- **First 1,000 images/month:** FREE
- **After that:** $1.50 per 1,000 images
- **Expected monthly cost:** ~$14.25 (for 10,500 images)

Set a billing alert at $20/month in GCP Console.

---

## Success Criteria

After deployment, you should have:
1. ✅ Function deployed to `us-west1`
2. ✅ Client-side moderation working in app
3. ✅ Server-side scanning active
4. ✅ Firestore logs being created
5. ✅ No inappropriate images in Storage

---

## Next Steps After Deployment

1. **Test with real images** (clean + inappropriate samples)
2. **Monitor logs** for first 24-48 hours
3. **Adjust thresholds** if too strict/lenient
4. **Enable for Messages** (already coded, just enable)

---

**Status:** Code ready, deployment pending
**Region:** Fixed to us-west1 ✅
**Command:** `firebase deploy --only functions:moderateUploadedImage`

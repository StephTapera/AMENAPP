# Deploy Image Moderation Function - Quick Fix

## The Issue
Other functions in your codebase are deployed to `us-central1`, but your Storage bucket is in `us-west1`. Firebase validates all functions even when deploying one.

## Solution: Deploy Using GCP Console

Since the Cloud Function code is already correct, you can deploy it directly via GCP Console:

### Option 1: Deploy via GCP Console (Easiest)

1. **Go to Cloud Functions Console:**
   - Open: https://console.cloud.google.com/functions/list?project=amen-5e359

2. **Create Function:**
   - Click "CREATE FUNCTION"
   - Name: `moderateUploadedImage`
   - Region: **us-west1** (IMPORTANT!)
   - Trigger: Cloud Storage
   - Event: `google.storage.object.finalize`
   - Bucket: `amen-5e359.appspot.com`

3. **Configure Runtime:**
   - Runtime: Node.js 24 (or 20)
   - Entry point: `moderateUploadedImage`

4. **Upload Code:**
   - Click "NEXT"
   - Source code: "Inline editor"
   - Copy the contents of `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions/imageModeration.js`
   - Paste into `index.js`
   - Update `package.json` dependencies:
     ```json
     {
       "dependencies": {
         "@google-cloud/vision": "^4.3.3",
         "firebase-admin": "^13.6.0",
         "firebase-functions": "^7.0.0"
       }
     }
     ```

5. **Deploy:**
   - Click "DEPLOY"
   - Wait 2-3 minutes

---

### Option 2: Deploy Only Image Moderation (Command Line)

Create a temporary isolated deployment:

```bash
# 1. Create temp directory
mkdir /tmp/image-mod-deploy
cd /tmp/image-mod-deploy

# 2. Initialize Firebase (use existing project)
firebase init functions
# Select: Use existing project → amen-5e359
# Language: JavaScript
# ESLint: No
# Install now: Yes

# 3. Copy your image moderation function
cp /Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/functions/imageModeration.js functions/index.js

# 4. Update package.json
cat > functions/package.json << 'EOF'
{
  "name": "functions",
  "engines": {
    "node": "24"
  },
  "main": "index.js",
  "dependencies": {
    "@google-cloud/vision": "^4.3.3",
    "firebase-admin": "^13.6.0",
    "firebase-functions": "^7.0.0"
  }
}
EOF

# 5. Install dependencies
cd functions
npm install

# 6. Deploy
cd ..
firebase deploy --only functions:moderateUploadedImage
```

---

### Option 3: Fix All Functions' Regions (Best Long-term)

Update ALL functions in your main `functions/` directory to use consistent regions:

```bash
cd /Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/functions
```

Find all `onDocumentCreated`, `onValueCreated`, etc. and add:
```javascript
{
  region: "us-west1"  // Add this to ALL function triggers
}
```

Then deploy normally:
```bash
firebase deploy --only functions
```

---

## Quick Test After Deployment

### 1. Verify Function Exists
```bash
gcloud functions list --project=amen-5e359 --region=us-west1
```

Should show:
```
NAME                      STATE    TRIGGER
moderateUploadedImage     ACTIVE   google.storage.object.finalize
```

### 2. Upload Test Image
Upload any image to Firebase Storage at:
```
gs://amen-5e359.appspot.com/posts/test/test-image.jpg
```

### 3. Check Logs
```bash
gcloud functions logs read moderateUploadedImage --region=us-west1 --project=amen-5e359 --limit=50
```

Look for:
- `🛡️ [IMAGE MOD] Processing file: posts/test/test-image.jpg`
- `🔍 SafeSearch results: { adult: ..., racy: ..., ... }`
- `✅ Image approved` or `❌ BLOCKING image`

---

## Why This Happened

Firebase Functions v2 requires functions to be in the same region as the resources they monitor. Your Storage bucket (`amen-5e359.appspot.com`) is in `us-west1`, so the function must also be in `us-west1`.

The code is already correct - the function specifies `region: "us-west1"`. The deployment error happens because Firebase validates ALL functions in your codebase, and some other function is in a different region.

---

## Recommended: Option 1 (GCP Console)

This is the fastest way to get it working:
1. Takes 5 minutes
2. No command-line issues
3. Can verify immediately
4. Easy to troubleshoot

After it's working via console, you can figure out the Firebase CLI deployment later.

---

## After Deployment

The function will automatically:
- Scan all newly uploaded images
- Block inappropriate content
- Delete flagged files
- Log to Firestore: `imageModerationLogs`
- Alert moderators: `moderatorAlerts`

Client-side moderation in your iOS app already works - this is just the server-side backup layer.

---

**Need help?** Check Cloud Functions logs in GCP Console:
https://console.cloud.google.com/functions/details/us-west1/moderateUploadedImage?project=amen-5e359

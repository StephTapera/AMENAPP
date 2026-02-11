# 🚀 Deploy Genkit to Cloud Run - Complete Guide
**Date**: 2026-02-07
**Target**: https://genkit-amen-78278013543.us-central1.run.app

---

## 📋 What You're Deploying

Your Genkit server provides AI Bible Study responses using Google's Gemini AI. It needs to be running on Cloud Run so your iOS app can connect to it.

**Current Setup**:
- ✅ Server code: `genkit/index.js`
- ✅ Dockerfile: `genkit/Dockerfile`
- ✅ Dependencies: Express + Google Generative AI
- ✅ iOS app is already configured to use Cloud Run endpoint

---

## 🎯 Two Deployment Options

### **Option 1: Firebase CLI (Recommended - Easiest)**
Uses Firebase to deploy to Cloud Run automatically

### **Option 2: Google Cloud Console (Manual)**
Upload and configure through web interface

---

## ✅ Option 1: Firebase CLI Deployment (RECOMMENDED)

### Step 1: Install Firebase CLI (if not installed)

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Verify installation
firebase --version
```

### Step 2: Login to Firebase

```bash
firebase login
```

This will open a browser for you to authenticate with your Google account.

### Step 3: Initialize Firebase (if needed)

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"

# Check if firebase.json exists
ls firebase.json

# If it doesn't exist, run:
firebase init hosting
```

### Step 4: Deploy to Cloud Run via Firebase

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/genkit"

# Deploy using Firebase
firebase deploy --only functions:genkit
```

**OR** if that doesn't work, use direct Cloud Run deployment:

```bash
# Make sure you're in the genkit directory
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/genkit"

# Deploy to Cloud Run
gcloud run deploy genkit-amen \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 60s \
  --project YOUR_PROJECT_ID
```

**Replace `YOUR_PROJECT_ID`** with your Firebase project ID

### Step 5: Verify Deployment

```bash
# Test the endpoint
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "message": "What is John 3:16 about?",
      "history": []
    }
  }'
```

**Expected Response**:
```json
{
  "result": {
    "response": "John 3:16 is one of the most beloved verses..."
  }
}
```

---

## 🌐 Option 2: Google Cloud Console (Manual)

### Step 1: Install Google Cloud CLI

**macOS**:
```bash
# Download and install
curl https://sdk.cloud.google.com | bash

# Restart terminal, then:
gcloud init
```

**Alternative** (if curl fails):
1. Go to: https://cloud.google.com/sdk/docs/install
2. Download the macOS installer
3. Run the installer
4. Follow the setup wizard

### Step 2: Authenticate

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

**Find your project ID**:
- Go to: https://console.firebase.google.com/
- Select your project
- Project ID is shown at the top

### Step 3: Enable Cloud Run API

```bash
gcloud services enable run.googleapis.com
```

**OR** via Console:
1. Go to: https://console.cloud.google.com/
2. Select your project
3. Search for "Cloud Run API"
4. Click "Enable"

### Step 4: Deploy to Cloud Run

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/genkit"

gcloud run deploy genkit-amen \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 60s \
  --max-instances 10
```

**What this does**:
- `--source .` → Uploads current directory
- `--platform managed` → Uses fully managed Cloud Run
- `--region us-central1` → Deploys to US Central (Iowa)
- `--allow-unauthenticated` → Allows iOS app to call without auth
- `--memory 1Gi` → Allocates 1GB RAM
- `--timeout 60s` → Max request time
- `--max-instances 10` → Auto-scales up to 10 instances

### Step 5: Get the URL

After deployment, you'll see:
```
Service [genkit-amen] revision [genkit-amen-00001-xxx] has been deployed and is serving 100 percent of traffic.
Service URL: https://genkit-amen-78278013543.us-central1.run.app
```

This URL should match what's in your iOS code!

### Step 6: Verify Deployment

```bash
# Test the endpoint
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "message": "What is John 3:16 about?",
      "history": []
    }
  }'
```

---

## 🔑 Important: Add Gemini API Key

Your Genkit server needs a Gemini API key to work.

### Get API Key

1. Go to: https://makersuite.google.com/app/apikey
2. Click "Create API Key"
3. Copy the key (starts with `AIza...`)

### Add to Cloud Run

**Option A: Via Console**
1. Go to: https://console.cloud.google.com/run
2. Click on `genkit-amen` service
3. Click "Edit & Deploy New Revision"
4. Scroll to "Container" → "Variables & Secrets"
5. Add environment variable:
   - Name: `GEMINI_API_KEY`
   - Value: `[your-api-key]`
6. Click "Deploy"

**Option B: Via CLI**
```bash
gcloud run services update genkit-amen \
  --region us-central1 \
  --set-env-vars GEMINI_API_KEY=your-api-key-here
```

---

## 🧪 Testing Your Deployment

### Test 1: Health Check
```bash
curl https://genkit-amen-78278013543.us-central1.run.app/
```

**Expected**: `{"status":"ok","message":"Genkit AI Server is running"}`

### Test 2: Bible Chat
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "message": "Explain John 3:16",
      "history": []
    }
  }'
```

**Expected**: JSON response with AI explanation

### Test 3: From iOS App
1. Build and run your app
2. Navigate to AI Bible Study
3. Type: "What is John 3:16?"
4. Press Send
5. **Expected**: AI response appears within 3-5 seconds

---

## 🐛 Troubleshooting

### Error: "gcloud: command not found"

**Fix**: Install Google Cloud CLI
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

### Error: "Permission denied"

**Fix**: Authenticate
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### Error: "API not enabled"

**Fix**: Enable Cloud Run API
```bash
gcloud services enable run.googleapis.com
```

### Error: "Deployment failed: source upload"

**Fix**: Check your Dockerfile exists
```bash
cd genkit
ls Dockerfile  # Should exist
```

### Error: "Container failed to start"

**Causes**:
- Missing Gemini API key
- Incorrect index.js entry point
- Missing dependencies

**Fix**: Check Cloud Run logs
```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=genkit-amen" \
  --limit 50 \
  --format json
```

**OR** via Console:
1. Go to: https://console.cloud.google.com/run
2. Click on `genkit-amen`
3. Click "Logs" tab
4. Look for errors

### Error: "GEMINI_API_KEY not found"

**Fix**: Add the environment variable (see "Add Gemini API Key" section above)

### iOS App: "Failed to get response"

**Checks**:
1. Is Cloud Run service deployed? (Check console)
2. Is URL correct in iOS code? (Should match deployed URL)
3. Is Gemini API key set? (Check Cloud Run env vars)
4. Test endpoint with curl (see Test 2 above)

---

## 💰 Pricing (Important!)

### Cloud Run Costs
- **Free Tier**: 2 million requests/month
- **After Free Tier**: $0.40 per million requests
- **Memory**: $0.0000025 per GB-second
- **CPU**: $0.00002400 per vCPU-second

### Gemini API Costs
- **Free Tier**: 60 requests/minute
- **After Free Tier**: Varies by model

### Estimated Monthly Cost (1000 active users)
- Cloud Run: $5-10
- Gemini API: $10-20
- **Total**: ~$15-30/month

---

## 🔒 Security Best Practices

### 1. Add Rate Limiting
Prevent abuse by limiting requests per user:
```javascript
// In index.js, add:
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});

app.use('/bibleChat', limiter);
```

### 2. Add Request Validation
```javascript
app.post('/bibleChat', (req, res) => {
  const { message } = req.body?.data || {};

  if (!message || message.length > 1000) {
    return res.status(400).json({ error: 'Invalid message' });
  }

  // ... rest of handler
});
```

### 3. Monitor Usage
```bash
# View request logs
gcloud logging read "resource.type=cloud_run_revision" --limit 100
```

### 4. Set Budget Alerts
1. Go to: https://console.cloud.google.com/billing
2. Create a budget alert
3. Set limit: $50/month
4. Get email notifications

---

## ✅ Quick Deploy Checklist

Before deploying, verify:

- [ ] You have a Google Cloud / Firebase account
- [ ] You have a Gemini API key
- [ ] You're in the genkit directory
- [ ] `index.js` and `Dockerfile` exist
- [ ] `package.json` has correct dependencies

**Then run**:
```bash
# 1. Install CLI (if needed)
npm install -g firebase-tools

# 2. Login
firebase login

# 3. Deploy
cd genkit
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 1Gi
```

**After deployment**:
- [ ] Test endpoint with curl
- [ ] Add Gemini API key as env variable
- [ ] Test from iOS app
- [ ] Check Cloud Run logs for errors

---

## 🎯 Final Steps for TestFlight

Once your Cloud Run service is deployed and working:

1. ✅ **Verify endpoint** (curl test passes)
2. ✅ **Test from iOS app** (send 1 message successfully)
3. ✅ **Deploy Firestore rules** (see previous guide)
4. ✅ **Archive in Xcode** (Product → Archive)
5. ✅ **Upload to TestFlight**

---

## 📞 Need Help?

**If you get stuck**, send me:
1. The command you ran
2. The full error message
3. Output of: `gcloud config list`

I'll help you debug!

---

## 🚀 TL;DR (Too Long; Didn't Read)

**Fastest way to deploy**:

```bash
# Install gcloud CLI
curl https://sdk.cloud.google.com | bash

# Restart terminal, then:
gcloud init
gcloud auth login

# Deploy
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/genkit"
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --allow-unauthenticated

# Add API key
gcloud run services update genkit-amen \
  --region us-central1 \
  --set-env-vars GEMINI_API_KEY=your-key-here

# Test
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{"data":{"message":"test","history":[]}}'
```

**Done!** Your AI Bible Study is now live! 🎉

---

**Created**: 2026-02-07
**Status**: Ready for deployment
**Next**: Run the commands above and tell me if you get any errors!

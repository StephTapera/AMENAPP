# 🚀 Deploy Complete Genkit Server with All AI Flows

## 📋 What You're Deploying

A complete AI server with **10 Genkit flows**:
1. ✅ **bibleChat** - AI Bible study chat
2. ✅ **generateDevotional** - Daily devotionals
3. ✅ **generateStudyPlan** - Study plans
4. ✅ **analyzeScripture** - Scripture analysis
5. ✅ **generateMemoryAid** - Memory verse helpers
6. ✅ **generateInsights** - AI insights
7. ✅ **generateFunBibleFact** - Fun Bible facts
8. ✅ **generateSearchSuggestions** - Smart search
9. ✅ **enhanceBiblicalSearch** - Enhanced biblical search
10. ✅ **suggestSearchFilters** - Filter suggestions

---

## 🛠️ Step 1: Set Up Your Genkit Directory

```bash
# Create a new directory for your Genkit server
cd ~
mkdir amen-genkit-server
cd amen-genkit-server
```

---

## 📁 Step 2: Copy These 3 Files

### File 1: `index.js`
Copy the entire contents of `genkit-server-index.js` from this repo.

### File 2: `package.json`
Copy the entire contents of `genkit-package.json` from this repo.

### File 3: `Dockerfile`
Copy the entire contents of `genkit-Dockerfile` from this repo.

---

## 📦 Step 3: Install Dependencies (Local Testing - Optional)

```bash
npm install
```

---

## 🧪 Step 4: Test Locally (Optional)

```bash
# Set your Google AI API key
export GOOGLE_AI_API_KEY=<GOOGLE_AI_API_KEY>

# Start the server
npm start
```

**Then test in another terminal:**
```bash
curl -X POST http://localhost:8080/generateFunBibleFact \
  -H "Content-Type: application/json" \
  -d '{"data": {"category": "random"}}'
```

You should get a real AI-generated Bible fact!

---

## ☁️ Step 5: Deploy to Cloud Run

```bash
# Make sure you're in the amen-genkit-server directory
cd ~/amen-genkit-server

# Deploy with Google AI API key
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars GOOGLE_AI_API_KEY=<GOOGLE_AI_API_KEY> \
  --port 8080 \
  --memory 1Gi \
  --timeout 300
```

**Wait 2-3 minutes for deployment...**

---

## ✅ Step 6: Verify Deployment

```bash
# 1. Check health endpoint
curl https://genkit-amen-78278013543.us-central1.run.app/

# Should return:
# {
#   "status": "healthy",
#   "service": "AMEN Genkit AI",
#   "flows": ["bibleChat", "generateDevotional", ...]
# }

# 2. Test a flow
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/generateFunBibleFact \
  -H "Content-Type: application/json" \
  -d '{"data": {"category": "random"}}'

# Should return:
# {"result": {"fact": "An interesting Bible fact..."}}
```

---

## 🎯 Step 7: Test All Flows

### 1. Bible Chat
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{"data": {"message": "What does John 3:16 mean?", "history": []}}'
```

### 2. Generate Devotional
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/generateDevotional \
  -H "Content-Type: application/json" \
  -d '{"data": {"topic": "faith"}}'
```

### 3. Generate Study Plan
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/generateStudyPlan \
  -H "Content-Type: application/json" \
  -d '{"data": {"topic": "Prayer", "duration": 7}}'
```

### 4. Analyze Scripture
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/analyzeScripture \
  -H "Content-Type: application/json" \
  -d '{"data": {"reference": "Romans 8:28", "analysisType": "Contextual"}}'
```

### 5. Generate Memory Aid
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/generateMemoryAid \
  -H "Content-Type: application/json" \
  -d '{"data": {"verse": "I can do all things through Christ", "reference": "Philippians 4:13"}}'
```

### 6. Generate Insights
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/generateInsights \
  -H "Content-Type: application/json" \
  -d '{"data": {"topic": "love"}}'
```

### 7. Fun Bible Fact
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/generateFunBibleFact \
  -H "Content-Type: application/json" \
  -d '{"data": {"category": "random"}}'
```

### 8. Search Suggestions
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/generateSearchSuggestions \
  -H "Content-Type: application/json" \
  -d '{"data": {"query": "salvation", "context": "general"}}'
```

### 9. Enhance Biblical Search
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/enhanceBiblicalSearch \
  -H "Content-Type: application/json" \
  -d '{"data": {"query": "Moses", "type": "person"}}'
```

### 10. Suggest Search Filters
```bash
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/suggestSearchFilters \
  -H "Content-Type: application/json" \
  -d '{"data": {"query": "miracles"}}'
```

---

## 🎉 Step 8: Test in Your iOS App

1. **Clean build** in Xcode: ⇧⌘K
2. **Run your app**
3. **Open Berean AI Assistant**
4. **Ask**: "What does John 3:16 mean?"
5. **Watch** the AI response stream in! ✨

---

## 🐛 Troubleshooting

### Error: "Cannot POST /flowName"
**Cause**: Flow doesn't exist or Genkit isn't starting properly  
**Fix**: Check Cloud Run logs
```bash
gcloud run logs read genkit-amen --region us-central1 --limit 50
```

### Error: "Invalid API key"
**Cause**: Google AI API key not set or invalid  
**Fix**: Redeploy with correct key
```bash
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars GOOGLE_AI_API_KEY=YOUR_CORRECT_KEY
```

### Error: "Timeout" or "Memory limit exceeded"
**Cause**: Not enough resources  
**Fix**: Increase memory/timeout
```bash
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars GOOGLE_AI_API_KEY=YOUR_KEY \
  --memory 2Gi \
  --timeout 600
```

---

## 📊 Monitor Your Server

### View Logs
```bash
gcloud run logs read genkit-amen --region us-central1 --limit 50 --follow
```

### View Metrics
```bash
# Open in browser
open https://console.cloud.google.com/run/detail/us-central1/genkit-amen/metrics
```

---

## 💰 Cost Estimate

**Google Cloud Run** (Free tier):
- 2 million requests/month FREE
- 360,000 GB-seconds of memory FREE
- 180,000 vCPU-seconds of compute FREE

**Google AI (Gemini 1.5 Flash)** (Free tier):
- 1,500 requests per day FREE
- 1 million tokens per day FREE

**Expected cost for typical use**: **$0/month** ✅

---

## 🔒 Security Recommendations

### 1. Add API Key Authentication (Recommended)

Update `index.js` to add authentication:
```javascript
const VALID_API_KEY = process.env.GENKIT_API_KEY || "your-secret-key";

app.use((req, res, next) => {
  if (req.path === '/') return next();
  
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  
  if (auth.replace('Bearer ', '') !== VALID_API_KEY) {
    return res.status(401).json({ error: 'Invalid API key' });
  }
  
  next();
});
```

Then redeploy:
```bash
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars GOOGLE_AI_API_KEY=YOUR_GEMINI_KEY,GENKIT_API_KEY=your-secret-key
```

And add to your iOS app's Info.plist:
```xml
<key>GENKIT_API_KEY</key>
<string>your-secret-key</string>
```

### 2. Rate Limiting

Add rate limiting to prevent abuse:
```bash
npm install express-rate-limit
```

### 3. Enable Cloud Armor

Protect against DDoS attacks (paid feature).

---

## 🎯 Quick Command Reference

```bash
# Deploy
gcloud run deploy genkit-amen --source . --region us-central1 --allow-unauthenticated --set-env-vars GOOGLE_AI_API_KEY=KEY

# View logs
gcloud run logs read genkit-amen --region us-central1 --limit 50

# Update environment variable
gcloud run services update genkit-amen --region us-central1 --set-env-vars GOOGLE_AI_API_KEY=NEW_KEY

# Delete service
gcloud run services delete genkit-amen --region us-central1

# Get service URL
gcloud run services describe genkit-amen --region us-central1 --format 'value(status.url)'
```

---

## ✅ Success Checklist

- [x] Created amen-genkit-server directory
- [x] Added index.js with all 10 flows
- [x] Added package.json
- [x] Added Dockerfile
- [x] Got Google AI API key
- [x] Deployed to Cloud Run
- [x] Health check responds
- [x] All 10 flows work
- [x] iOS app connects successfully
- [x] AI responses are accurate

---

## 🎉 You're Done!

Your complete AI-powered Bible study server is now live with:
- ✅ 10 fully functional AI flows
- ✅ Gemini 1.5 Flash integration
- ✅ Automatic scaling
- ✅ $0 cost (free tier)
- ✅ Production-ready

**Next step**: Build and test your iOS app! 📱

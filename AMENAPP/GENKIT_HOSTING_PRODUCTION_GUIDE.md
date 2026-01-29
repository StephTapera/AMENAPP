# 🚀 Genkit Hosting & Production Deployment Guide

## 📍 Current Location
Your Genkit backend is in: `AMENAPP/genkit/`

---

## 🎯 Quick Start: Run Locally (2 Minutes)

### **Step 1: Open Terminal**
```bash
# Navigate to your app directory
cd /path/to/your/AMENAPP

# Go into genkit folder
cd genkit
```

### **Step 2: Check if Dependencies are Installed**
```bash
# Check if node_modules exists
ls node_modules

# If empty or doesn't exist, install:
npm install
```

### **Step 3: Set Up Environment Variables**
```bash
# Create .env file from example
cp .env.example .env

# Edit .env with your API key
nano .env
# or
open .env
```

Add your Google AI API key:
```env
GOOGLE_AI_API_KEY=your_actual_api_key_here
FIREBASE_PROJECT_ID=your_firebase_project_id
```

**Get your API key**: https://makersuite.google.com/app/apikey

### **Step 4: Start the Development Server**
```bash
npm run dev
```

You should see:
```
✓ Genkit server running at http://localhost:3400
✓ Developer UI at http://localhost:4000
```

### **Step 5: Test It!**
Open in browser: http://localhost:4000

---

## 🧪 Testing Your Flows

### **In Developer UI (http://localhost:4000)**

1. Click on **"bibleChat"** flow
2. Add test input:
```json
{
  "message": "What does John 3:16 mean?",
  "history": []
}
```
3. Click **"Run"**
4. See the AI response!

### **From Your iOS App**

1. Make sure Genkit is running (`npm run dev`)
2. Run your iOS app
3. Open Berean AI Assistant
4. Type: "Explain John 3:16"
5. Get AI response!

---

## 🏗️ Production Deployment Options

## **Option 1: Cloud Run (Recommended) ⭐**

### **Why Cloud Run?**
- ✅ Auto-scaling (0 to millions)
- ✅ Pay only for requests
- ✅ Built-in HTTPS
- ✅ Easy deployment
- ✅ Fast cold starts

### **Deploy to Cloud Run:**

```bash
# Make sure you're in genkit directory
cd genkit

# Install Genkit CLI if not installed
npm install -g genkit

# Login to Google Cloud
gcloud auth login

# Set your project
gcloud config set project YOUR_FIREBASE_PROJECT_ID

# Deploy!
genkit deploy --project YOUR_FIREBASE_PROJECT_ID
```

This will:
1. Build your Genkit flows
2. Create a Docker container
3. Deploy to Cloud Run
4. Give you a production URL like: `https://berean-genkit-xxxxx.run.app`

### **Configure iOS App for Production:**

Update `Info.plist`:
```xml
<key>GENKIT_ENDPOINT</key>
<string>https://berean-genkit-xxxxx.run.app</string>
```

### **Secure Your API:**

```bash
# Generate secure API key
openssl rand -hex 32

# Add to Cloud Run
gcloud run services update berean-genkit \
  --update-env-vars GENKIT_API_KEY=your_generated_key_here
```

Update iOS `Info.plist`:
```xml
<key>GENKIT_API_KEY</key>
<string>your_generated_key_here</string>
```

---

## **Option 2: Firebase Functions**

### **Deploy to Firebase Functions:**

```bash
# In genkit directory
cd genkit

# Initialize Firebase if not done
firebase init functions

# Deploy
firebase deploy --only functions
```

Your endpoint will be:
```
https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/bereanChat
```

---

## **Option 3: Railway/Render/Fly.io (Alternative)**

### **Deploy to Railway:**

1. **Create `Procfile`:**
```bash
# In genkit directory
echo "web: npm start" > Procfile
```

2. **Update `package.json`:**
```json
{
  "scripts": {
    "start": "genkit start --port $PORT",
    "dev": "genkit start --port 3400"
  }
}
```

3. **Deploy:**
- Go to https://railway.app
- Connect your GitHub repo
- Select the `genkit` directory
- Deploy!

4. **Add Environment Variables:**
- Go to Railway dashboard
- Add `GOOGLE_AI_API_KEY`
- Add `FIREBASE_PROJECT_ID`

---

## 🔒 Production Security Checklist

### **1. API Key Protection**
```bash
# Add API key to environment
export GENKIT_API_KEY=$(openssl rand -hex 32)
```

Update `berean-flows.ts`:
```typescript
// Add middleware for API key check
function validateApiKey(req: any) {
  const apiKey = req.headers['x-api-key'];
  if (apiKey !== process.env.GENKIT_API_KEY) {
    throw new Error('Unauthorized');
  }
}
```

### **2. Rate Limiting**
```typescript
import rateLimit from 'express-rate-limit';

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});

app.use(limiter);
```

### **3. Firebase App Check**
```swift
// In iOS app
import FirebaseAppCheck

// In AppDelegate
let providerFactory = AppAttestProviderFactory()
AppCheck.setAppCheckProviderFactory(providerFactory)
```

### **4. CORS Configuration**
```typescript
import cors from 'cors';

app.use(cors({
  origin: ['https://yourapp.com'], // Your iOS app bundle ID
  credentials: true
}));
```

---

## 📊 Monitoring & Observability

### **Genkit Developer UI (Local)**
```bash
# Start with observability
npm run dev

# Open
open http://localhost:4000
```

Features:
- ✅ View all flow executions
- ✅ Trace timing
- ✅ Input/output inspection
- ✅ Error debugging
- ✅ Cost tracking

### **Production Monitoring**

**Cloud Run Metrics:**
```bash
# View logs
gcloud run logs read berean-genkit --limit 50

# View metrics
gcloud run services describe berean-genkit --region us-central1
```

**Firebase Console:**
- Go to Firebase Console → Functions
- View invocation count, errors, execution time

---

## 💰 Cost Optimization

### **1. Use Flash Models**
```typescript
// In berean-flows.ts
import { gemini15Flash } from '@genkit-ai/googleai';

// Instead of gemini20FlashExp
const model = gemini15Flash;
```

### **2. Implement Caching**
```typescript
import NodeCache from 'node-cache';

const cache = new NodeCache({ stdTTL: 3600 }); // 1 hour

export const bibleChat = defineFlow({
  name: 'bibleChat',
  inputSchema: z.object({
    message: z.string(),
    history: z.array(z.any())
  }),
  outputSchema: z.object({
    response: z.string()
  })
}, async (input) => {
  // Check cache first
  const cacheKey = `chat:${input.message}`;
  const cached = cache.get(cacheKey);
  
  if (cached) {
    return { response: cached as string };
  }
  
  // Generate response
  const result = await generate({
    model: gemini15Flash,
    prompt: input.message
  });
  
  // Cache for 1 hour
  cache.set(cacheKey, result.text);
  
  return { response: result.text };
});
```

### **3. Batch Requests**
```swift
// In iOS app - batch multiple questions
struct BatchRequest {
    let questions: [String]
}

// Send all at once
let responses = try await genkitService.batchProcess(questions: questions)
```

---

## 🧪 Testing in Production

### **Health Check Endpoint**
```typescript
// Add to berean-flows.ts
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});
```

### **Test from Terminal**
```bash
# Test health
curl https://your-genkit-url.run.app/health

# Test flow
curl -X POST https://your-genkit-url.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -H "x-api-key: your_api_key" \
  -d '{"message": "What does John 3:16 mean?", "history": []}'
```

### **Load Testing**
```bash
# Install k6
brew install k6

# Create test script
cat > load-test.js << 'EOF'
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  vus: 10, // 10 virtual users
  duration: '30s',
};

export default function() {
  let res = http.post('https://your-genkit-url.run.app/bibleChat', 
    JSON.stringify({
      message: 'What does John 3:16 mean?',
      history: []
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}
EOF

# Run test
k6 run load-test.js
```

---

## 🐛 Troubleshooting

### **Problem: "Cannot find module 'genkit'"**
```bash
# Reinstall dependencies
cd genkit
rm -rf node_modules package-lock.json
npm install
```

### **Problem: "Port 3400 already in use"**
```bash
# Kill process on port 3400
lsof -ti:3400 | xargs kill -9

# Or use different port
npm run dev -- --port 3500
```

### **Problem: "API key invalid"**
```bash
# Check .env file
cat .env

# Verify key at Google AI Studio
open https://makersuite.google.com/app/apikey

# Test with curl
curl -H "x-goog-api-key: YOUR_API_KEY" \
  https://generativelanguage.googleapis.com/v1beta/models
```

### **Problem: "Module not found in iOS"**
```swift
// Make sure BereanGenkitService.swift is added to target
// Right-click file → Show in Finder → Check target membership
```

### **Problem: Slow cold starts on Cloud Run**
```bash
# Increase minimum instances
gcloud run services update berean-genkit \
  --min-instances 1 \
  --region us-central1
```

---

## 📁 Project Structure

```
AMENAPP/
├── AMENAPP/                      # iOS App
│   ├── BereanGenkitService.swift # Calls Genkit
│   ├── BereanAIAssistantView.swift
│   └── Info.plist               # Has GENKIT_ENDPOINT
│
└── genkit/                       # Genkit Backend
    ├── src/
    │   └── berean-flows.ts      # AI flows
    ├── package.json              # Dependencies
    ├── tsconfig.json             # TypeScript config
    ├── .env                      # Environment variables (local)
    ├── .env.example              # Template
    └── README.md                 # This guide
```

---

## 🔄 Development Workflow

### **Daily Development:**
```bash
# Terminal 1: Run Genkit
cd genkit
npm run dev

# Terminal 2: Run iOS app
open AMENAPP.xcodeproj
# Press Cmd+R to run
```

### **Before Committing:**
```bash
# Test all flows
npm test

# Check TypeScript
npm run build

# Format code
npm run format
```

### **Deploying Updates:**
```bash
# Update flows
vim src/berean-flows.ts

# Test locally
npm run dev

# Deploy
genkit deploy --project YOUR_PROJECT_ID

# Update iOS app with new endpoint (if changed)
```

---

## 🎯 Next Steps

### **1. Run Locally** ✅
```bash
cd genkit
npm install
npm run dev
```

### **2. Test in iOS** ✅
- Run app
- Open Berean AI
- Ask a question
- Verify response

### **3. Deploy to Cloud Run** 🚀
```bash
genkit deploy --project YOUR_PROJECT_ID
```

### **4. Update iOS for Production** 📱
```xml
<!-- Info.plist -->
<key>GENKIT_ENDPOINT</key>
<string>https://your-production-url.run.app</string>
```

### **5. Monitor** 📊
- Check Cloud Run logs
- Monitor API usage
- Track costs

---

## 💡 Pro Tips

### **Tip 1: Keep Dev Server Running**
```bash
# Use tmux or screen to keep server running
tmux new -s genkit
cd genkit && npm run dev
# Detach with Ctrl+B then D
```

### **Tip 2: Auto-restart on Changes**
```bash
# Already enabled with genkit start
# Just save your files and server reloads!
```

### **Tip 3: Debug with Verbose Logging**
```bash
# Start with debug logs
GENKIT_LOG_LEVEL=debug npm run dev
```

### **Tip 4: Use Environment-Specific Configs**
```typescript
// berean-flows.ts
const isDev = process.env.NODE_ENV === 'development';
const apiKey = isDev ? process.env.DEV_API_KEY : process.env.PROD_API_KEY;
```

---

## 📞 Support

### **Genkit Issues:**
- Docs: https://firebase.google.com/docs/genkit
- GitHub: https://github.com/firebase/genkit

### **Google AI Issues:**
- Studio: https://makersuite.google.com
- Docs: https://ai.google.dev/docs

### **Cloud Run Issues:**
- Docs: https://cloud.google.com/run/docs
- Console: https://console.cloud.google.com/run

---

## ✅ Checklist

### **Local Development:**
- [ ] Node.js 20+ installed
- [ ] Genkit CLI installed (`npm install -g genkit`)
- [ ] Dependencies installed (`npm install`)
- [ ] `.env` file created with API key
- [ ] Server starts (`npm run dev`)
- [ ] Developer UI opens (http://localhost:4000)
- [ ] iOS app connects to localhost

### **Production Deployment:**
- [ ] Cloud Run deployment successful
- [ ] Production URL received
- [ ] iOS Info.plist updated
- [ ] API key authentication enabled
- [ ] CORS configured
- [ ] Rate limiting enabled
- [ ] Monitoring set up
- [ ] Load testing completed
- [ ] Cost alerts configured

### **Security:**
- [ ] API keys not in source code
- [ ] Environment variables secured
- [ ] App Check enabled
- [ ] Rate limiting active
- [ ] HTTPS only
- [ ] Input validation

---

## 🎉 You're Ready!

Your Genkit backend is now:
- ✅ Running locally for development
- ✅ Ready to deploy to production
- ✅ Secured with API keys
- ✅ Monitored and observable
- ✅ Cost-optimized

**Start developing!**

```bash
cd genkit
npm run dev
```

Then open your iOS app and start chatting with Berean AI! 🙏✨

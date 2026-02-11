# Fix Cloud Run Deployment - Genkit Server

## 🔴 Error You're Seeing

```
ERROR: The user-provided container failed to start and listen on the port defined by PORT=8080
```

This means your Genkit server isn't properly configured to listen on Cloud Run's required port.

---

## ✅ Solution: Update Your Genkit Server Configuration

### Step 1: Check Your Package.json

**File:** `genkit/package.json` or `genkit-flows/package.json`

Make sure you have these scripts:

```json
{
  "name": "genkit-amen",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "genkit start -- tsx --watch src/index.ts",
    "start": "node dist/index.js",
    "build": "tsc",
    "deploy": "npm run build && gcloud run deploy genkit-amen --source . --region us-central1 --allow-unauthenticated"
  },
  "dependencies": {
    "@genkit-ai/ai": "latest",
    "@genkit-ai/core": "latest",
    "@genkit-ai/dotprompt": "latest",
    "@genkit-ai/firebase": "latest",
    "@genkit-ai/googleai": "latest",
    "express": "^4.18.2",
    "genkit": "latest",
    "zod": "^3.22.4"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.0",
    "tsx": "^4.7.0",
    "typescript": "^5.3.3"
  }
}
```

### Step 2: Fix Your Server Entry Point

**File:** `genkit/src/index.ts` (or wherever your server starts)

```typescript
import { genkit } from 'genkit';
import { googleAI } from '@genkit-ai/googleai';
import express from 'express';

// Initialize Genkit with Google AI
const ai = genkit({
  plugins: [
    googleAI({
      apiKey: process.env.GOOGLE_AI_API_KEY || process.env.GEMINI_API_KEY
    })
  ]
});

// ✅ CRITICAL: Create Express app and configure for Cloud Run
const app = express();

// ✅ Parse JSON bodies
app.use(express.json());

// ✅ Health check endpoint (required for Cloud Run)
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ✅ Root endpoint
app.get('/', (req, res) => {
  res.json({ 
    message: 'Berean AI Genkit Server',
    version: '1.0.0',
    status: 'running'
  });
});

// Import your flows
import './flows/bibleChat.js';
import './flows/devotional.js';
// ... other flows

// ✅ CRITICAL: Listen on PORT from environment (Cloud Run requirement)
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Genkit server running on port ${PORT}`);
  console.log(`📍 Health check: http://localhost:${PORT}/health`);
});

// ✅ Export for testing
export default app;
```

### Step 3: Create/Update Dockerfile

**File:** `genkit/Dockerfile`

```dockerfile
# Use Node.js 20 LTS
FROM node:20-slim

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Build TypeScript
RUN npm run build

# ✅ Expose port 8080 (Cloud Run default)
EXPOSE 8080

# ✅ Set environment variable for port
ENV PORT=8080

# ✅ Start the server
CMD ["npm", "start"]
```

### Step 4: Create .dockerignore

**File:** `genkit/.dockerignore`

```
node_modules
npm-debug.log
.env
.git
.gitignore
dist
*.md
```

### Step 5: Update tsconfig.json

**File:** `genkit/tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "lib": ["ES2020"],
    "moduleResolution": "node",
    "esModuleInterop": true,
    "skipLibCheck": true,
    "strict": true,
    "resolveJsonModule": true,
    "outDir": "./dist",
    "rootDir": "./src"
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

---

## 🚀 **Deploy Again (Step by Step)**

### Option 1: Quick Deploy (Automatic Build)

```bash
cd genkit-flows  # or wherever your genkit code is

# Deploy with source code (Cloud Run builds for you)
gcloud run deploy genkit-amen \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 2Gi \
  --timeout 300s \
  --port 8080 \
  --set-env-vars "GEMINI_API_KEY=your-api-key-here"
```

### Option 2: Manual Build + Deploy

```bash
cd genkit-flows

# 1. Build TypeScript
npm run build

# 2. Test locally first
PORT=8080 npm start

# In another terminal, test:
curl http://localhost:8080/health
# Should return: {"status":"ok","timestamp":"..."}

# 3. If local test works, deploy:
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --port 8080
```

---

## 🔍 **Debugging Cloud Run Deployment**

### View Logs

```bash
# View deployment logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=genkit-amen" \
  --limit 100 \
  --format json

# Or view in browser:
# https://console.cloud.google.com/run/detail/us-central1/genkit-amen/logs
```

### Common Issues & Fixes

#### Issue 1: Port Not Listening
```typescript
// ❌ Wrong
app.listen(3400);  // Hardcoded port

// ✅ Correct
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0');
```

#### Issue 2: Missing Health Check
```typescript
// ✅ Add this endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});
```

#### Issue 3: Timeout During Build
```bash
# Increase timeout
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1 \
  --timeout 300s  # 5 minutes
```

#### Issue 4: Missing Dependencies
```bash
# Make sure package.json includes all deps
npm install express @genkit-ai/ai @genkit-ai/googleai --save
```

---

## ✅ **Verify Deployment**

Once deployed successfully:

```bash
# 1. Get the URL
gcloud run services describe genkit-amen \
  --region us-central1 \
  --format 'value(status.url)'

# 2. Test health endpoint
curl https://genkit-amen-78278013543.us-central1.run.app/health

# 3. Test AI flow
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{"message":"What does John 3:16 mean?","history":[]}'
```

**Expected response:**
```json
{
  "response": "John 3:16 is one of the most well-known verses..."
}
```

---

## 🎯 **How Users Access It**

Once deployed to Cloud Run:

1. **Your iOS app** has the URL hardcoded:
   ```swift
   let genkitEndpoint = "https://genkit-amen-78278013543.us-central1.run.app"
   ```

2. **TestFlight users** automatically use Cloud Run:
   - App sends request to Cloud Run URL
   - Cloud Run wakes up (if asleep)
   - Processes request with Gemini
   - Returns response
   - Cloud Run goes back to sleep

3. **No user setup required!**
   - Users just tap and ask questions
   - Everything happens automatically
   - Cloud Run handles all scaling

---

## 💰 **Cost (Spoiler: It's Cheap)**

Cloud Run pricing:
- First 2 million requests/month: **FREE**
- After that: $0.40 per million requests
- Idle time (sleeping): **FREE**
- Only charged when actually processing

**For TestFlight testing:**
- Even with 100 active testers
- Sending 10 questions each per day
- = 1,000 requests/day = 30,000/month
- **Cost: $0** (under free tier)

---

## 🆘 **Still Having Issues?**

If deployment keeps failing:

### Option A: Check Genkit Version
```bash
npm list genkit
# Should be 0.9.0 or higher
```

### Option B: Use Genkit CLI Deploy
```bash
# Install Genkit CLI globally
npm install -g genkit

# Deploy using Genkit's built-in command
genkit deploy --project amen-5e359 --region us-central1
```

### Option C: Manual Docker Build
```bash
# Build Docker image locally
docker build -t genkit-amen .

# Test locally
docker run -p 8080:8080 -e PORT=8080 genkit-amen

# Test in browser
curl http://localhost:8080/health

# If works, push to Container Registry
gcloud builds submit --tag gcr.io/amen-5e359/genkit-amen

# Deploy from Container Registry
gcloud run deploy genkit-amen \
  --image gcr.io/amen-5e359/genkit-amen \
  --region us-central1
```

---

## 📋 **Quick Checklist**

Before deploying again:

- [ ] `package.json` has `"start": "node dist/index.js"`
- [ ] `src/index.ts` listens on `process.env.PORT`
- [ ] Health check endpoint exists (`/health`)
- [ ] TypeScript compiles (`npm run build`)
- [ ] Local test works (`PORT=8080 npm start`)
- [ ] All dependencies installed
- [ ] Gemini API key set as env var

---

## 🎉 **Once Deployed Successfully**

Your app will:
1. ✅ Work for all TestFlight users
2. ✅ Run 24/7 automatically
3. ✅ Scale with usage
4. ✅ Cost almost nothing during testing
5. ✅ No manual server management needed

**You never need to "keep the server running" - Cloud Run does it automatically!**

---

Need help with any of these steps? Let me know what errors you're seeing in the logs!

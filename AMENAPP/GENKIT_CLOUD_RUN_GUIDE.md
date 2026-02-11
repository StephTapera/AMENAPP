# 🚀 How to Keep Genkit Server Running 24/7 for TestFlight

## 📍 **You Are Here:**

```
❌ Running Genkit locally (localhost:3400)
   - Only works on YOUR computer
   - Stops when you close your laptop
   - TestFlight users CAN'T access it

✅ Running Genkit on Cloud Run (the solution!)
   - Available 24/7 automatically
   - Works for ALL TestFlight users
   - Scales automatically
   - You deploy ONCE, it runs FOREVER
```

---

## ☁️ **Deploy Genkit to Cloud Run (One-Time Setup)**

### **Prerequisites:**

1. **Google Cloud Account** (you already have this)
2. **gcloud CLI installed** (check with `gcloud --version`)
3. **Your genkit-flows project**

### **Step 1: Navigate to Your Project**

```bash
# Find your genkit flows directory
cd /path/to/your/genkit-flows

# Verify you're in the right place
ls
# Should see: package.json, src/, genkit.config.ts
```

### **Step 2: Deploy to Cloud Run**

```bash
# Deploy (takes 5-10 minutes first time)
gcloud run deploy genkit-amen \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 2Gi \
  --cpu 2 \
  --timeout 300s \
  --max-instances 10 \
  --min-instances 0
```

**What each flag means:**
- `--source .` → Deploy from current directory
- `--region us-central1` → Host in US Central (fast for US users)
- `--allow-unauthenticated` → Anyone can call it (your app)
- `--memory 2Gi` → 2GB RAM (enough for AI)
- `--timeout 300s` → 5 minutes max per request
- `--max-instances 10` → Scale up to 10 servers if needed
- `--min-instances 0` → Scale to zero when not used (saves money)

### **Step 3: Get Your URL**

After deployment, you'll see:

```
Service [genkit-amen] revision [genkit-amen-00001-xyz] has been deployed and is serving 100 percent of traffic.
Service URL: https://genkit-amen-78278013543.us-central1.run.app
```

**Copy this URL!** This is YOUR permanent server address.

### **Step 4: Test It**

```bash
# Test health endpoint
curl https://genkit-amen-78278013543.us-central1.run.app/health

# Should return: {"status": "ok"}

# Test AI endpoint
curl -X POST https://genkit-amen-78278013543.us-central1.run.app/bibleChat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What does John 3:16 mean?",
    "history": []
  }'

# Should return: {"response": "John 3:16 is one of the most..."}
```

✅ **If these work, you're done!** Your server is now live 24/7.

---

## 📱 **Your App Already Points to Cloud Run**

Check `BereanGenkitService.swift` - it's already configured:

```swift
init() {
    // Production: Use Cloud Run
    self.genkitEndpoint = "https://genkit-amen-78278013543.us-central1.run.app"
}
```

**This means:**
- TestFlight users automatically use YOUR Cloud Run server
- You don't need to change anything in the app
- It just works! ✨

---

## 🔄 **How to Update Your Server**

When you make changes to Genkit flows:

```bash
# 1. Make your code changes in genkit-flows/

# 2. Test locally (optional)
npm run dev

# 3. Deploy the update
gcloud run deploy genkit-amen \
  --source . \
  --region us-central1

# That's it! New version is live in ~3 minutes
```

**Users automatically get the update** - no app update needed!

---

## 💰 **Costs (Very Affordable)**

### **Free Tier (Most Likely You'll Stay Here):**
- 2 million requests/month FREE
- 360,000 GB-seconds compute/month FREE
- 180,000 vCPU-seconds/month FREE

### **For 100 TestFlight Users:**
- Average usage: ~10,000 requests/month
- Estimated cost: **$0-5/month** (likely FREE)

### **If You Get Popular (1000+ users):**
- Heavy usage: ~100,000 requests/month
- Estimated cost: **$10-30/month**

### **Cost Breakdown:**
```
Request: $0.40 per million
CPU: $0.00002400 per vCPU-second
Memory: $0.00000250 per GB-second
```

**Example calculation for 10,000 requests:**
- Requests: 10,000 × $0.40/1M = $0.004
- Compute: ~$2-5
- **Total: ~$2-5/month**

---

## 🎛️ **Managing Your Server**

### **View in Google Cloud Console:**

```
https://console.cloud.google.com/run/detail/us-central1/genkit-amen
```

Here you can see:
- ✅ Request count
- ✅ Response times
- ✅ Error rates
- ✅ CPU/Memory usage
- ✅ Logs
- ✅ Costs

### **View Logs:**

```bash
# View recent logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=genkit-amen" \
  --limit 50 \
  --format json

# Follow logs in real-time
gcloud alpha logging tail "resource.type=cloud_run_revision AND resource.labels.service_name=genkit-amen"
```

### **Check Status:**

```bash
# Get service details
gcloud run services describe genkit-amen \
  --region us-central1 \
  --format yaml

# Get service URL
gcloud run services describe genkit-amen \
  --region us-central1 \
  --format 'value(status.url)'
```

---

## ⚡ **Improve Performance (Optional)**

### **Problem: Cold Starts (10-30 second delay)**

When no one uses your server for ~15 minutes, Cloud Run scales to zero. The next request has to "wake up" the server (cold start).

### **Solution 1: Keep Minimum Instances**

```bash
# Keep 1 instance always running (no cold starts)
gcloud run services update genkit-amen \
  --region us-central1 \
  --min-instances 1

# Cost: ~$10-15/month
# Benefit: No cold starts ever!
```

### **Solution 2: Scheduled Warm-Up Pings**

Create a Cloud Scheduler job to ping every 5 minutes:

```bash
# Create scheduler job (free tier: 3 jobs)
gcloud scheduler jobs create http genkit-warmup \
  --location us-central1 \
  --schedule "*/5 * * * *" \
  --uri "https://genkit-amen-78278013543.us-central1.run.app/health" \
  --http-method GET

# Cost: FREE (in free tier)
# Benefit: Reduces cold starts significantly
```

### **Solution 3: Faster CPU**

```bash
# Use 4 CPUs instead of 2 (faster responses)
gcloud run services update genkit-amen \
  --region us-central1 \
  --cpu 4

# Cost: 2x compute cost (~$5-10 extra/month)
# Benefit: 30-50% faster responses
```

---

## 🔒 **Security (Recommended for Production)**

### **Add API Key Protection:**

**Step 1: Generate API Key**

```bash
# Generate secure key
openssl rand -base64 32
# Example output: Kx7Yf9mN3pQ8rV2sT6wU4xZ1aC5bD0eF
```

**Step 2: Add to Cloud Run**

```bash
gcloud run services update genkit-amen \
  --region us-central1 \
  --set-env-vars "API_KEY=Kx7Yf9mN3pQ8rV2sT6wU4xZ1aC5bD0eF"
```

**Step 3: Update Genkit Flows**

```typescript
// In your genkit flow (e.g., bibleChat.ts)
export const bibleChat = ai.defineFlow(
  {
    name: 'bibleChat',
    inputSchema: z.object({
      message: z.string(),
      history: z.array(z.any()).optional(),
    }),
    outputSchema: z.object({
      response: z.string(),
    }),
  },
  async (input, { request }) => {
    // ✅ Check API key
    const apiKey = process.env.API_KEY;
    const providedKey = request?.headers?.authorization?.replace('Bearer ', '');
    
    if (apiKey && providedKey !== apiKey) {
      throw new Error('Unauthorized');
    }
    
    // ... rest of your flow
  }
);
```

**Step 4: Add to iOS App**

In `Info.plist`:
```xml
<key>GENKIT_API_KEY</key>
<string>Kx7Yf9mN3pQ8rV2sT6wU4xZ1aC5bD0eF</string>
```

The app already uses it:
```swift
// In BereanGenkitService.swift
if let apiKey = apiKey {
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
}
```

---

## 📊 **Monitoring & Alerts**

### **Set Up Alerts (Optional but Recommended):**

**Alert for High Error Rate:**

```bash
# Email you if error rate > 5%
gcloud alpha monitoring policies create \
  --notification-channels=YOUR_CHANNEL_ID \
  --display-name="Genkit High Error Rate" \
  --condition-display-name="Error rate above 5%" \
  --condition-threshold-value=0.05 \
  --condition-threshold-duration=300s
```

**Alert for High Latency:**

```bash
# Email you if response time > 10 seconds
gcloud alpha monitoring policies create \
  --notification-channels=YOUR_CHANNEL_ID \
  --display-name="Genkit Slow Response" \
  --condition-display-name="Response time above 10s" \
  --condition-threshold-value=10000 \
  --condition-threshold-duration=300s
```

---

## 🚀 **Deployment Checklist**

Before shipping to TestFlight:

- [ ] Deploy Genkit to Cloud Run
- [ ] Test health endpoint (curl)
- [ ] Test AI endpoint (curl)
- [ ] Verify app points to Cloud Run URL
- [ ] Test from iOS device (not simulator)
- [ ] Check Cloud Console shows requests
- [ ] (Optional) Add API key
- [ ] (Optional) Set up monitoring
- [ ] (Optional) Enable min-instances if budget allows

---

## 🎯 **Quick Reference**

```bash
# Deploy/Update Server
gcloud run deploy genkit-amen --source . --region us-central1

# Test Server
curl https://genkit-amen-78278013543.us-central1.run.app/health

# View Logs
gcloud logging read "resource.labels.service_name=genkit-amen" --limit 50

# Check Status
gcloud run services describe genkit-amen --region us-central1

# Set Min Instances (prevent cold starts)
gcloud run services update genkit-amen --region us-central1 --min-instances 1

# View in Console
https://console.cloud.google.com/run
```

---

## ❓ **FAQs**

**Q: Do I need to keep my computer on?**
A: No! Once deployed to Cloud Run, it runs on Google's servers 24/7.

**Q: What if my computer crashes?**
A: Your server keeps running - it's on Google Cloud, not your computer.

**Q: How do I stop paying?**
A: Delete the service: `gcloud run services delete genkit-amen --region us-central1`

**Q: Can I use a custom domain?**
A: Yes! Map your own domain in Cloud Console → Domain Mappings.

**Q: What if I exceed free tier?**
A: You'll get an email warning. Set billing alerts to be safe.

**Q: How do I see costs?**
A: Cloud Console → Billing → Reports (filter by Cloud Run)

---

## ✅ **You're Ready!**

Once you run `gcloud run deploy`, your server is live forever (until you delete it).

**TestFlight users will:**
1. Open Berean AI
2. Ask questions
3. Get responses from YOUR Cloud Run server
4. Never know it's in the cloud - it just works! ✨

**You'll:**
1. Deploy once
2. Monitor occasionally
3. Pay ~$0-5/month
4. Update when needed (redeploy in 3 minutes)

🎉 **Ship it!**

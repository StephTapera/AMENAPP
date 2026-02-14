# Production Security Setup Guide

## Step 1: Firebase Remote Config Setup

### 1.1 Enable Remote Config in Firebase Console

1. Go to Firebase Console: https://console.firebase.google.com/project/amen-5e359
2. Click **Build** → **Remote Config** in left sidebar
3. Click **"Create configuration"** (if first time)

### 1.2 Add Gemini API Key Parameter

1. Click **"Add parameter"**
2. Fill in:
   - **Parameter key:** `gemini_api_key`
   - **Data type:** String
   - **Default value:** `AIzaSyBqmDFx46X5q_MmAKQxleJGBa_8jiQKmnY`
   - **Description:** "Gemini API key for AI features"
3. Click **"Save"**
4. Click **"Publish changes"** at the top

### 1.3 Add Safety Settings (Optional but Recommended)

Add these parameters for dynamic control:

**Parameter:** `ai_safety_enabled`
- Type: Boolean
- Default: true
- Description: "Enable AI safety filtering"

**Parameter:** `ai_rate_limit_per_minute`
- Type: Number
- Default: 10
- Description: "Max AI requests per user per minute"

**Parameter:** `ai_features_enabled`
- Type: Boolean
- Default: true
- Description: "Master kill switch for AI features"

Click **"Publish changes"** when done.

---

## Step 2: Add iOS Bundle ID Restriction to API Key

### 2.1 Restrict API Key in Google Cloud Console

1. Go to: https://console.cloud.google.com/apis/credentials?project=amen-5e359
2. Find your API key: `AIzaSyBqmDFx46X5q_MmAKQxleJGBa_8jiQKmnY`
3. Click the pencil icon (Edit)

### 2.2 Add iOS App Restriction

1. Under **"Application restrictions"**, select **"iOS apps"**
2. Click **"Add an item"**
3. Enter your iOS bundle ID: `tapera.AMENAPP`
4. Click **"Done"**
5. Click **"Save"**

**Wait 5 minutes** for changes to propagate.

---

## Step 3: Set Up Firebase Usage Monitoring

### 3.1 Enable Firebase Analytics (Already Done)

Your app already has Analytics. Verify:
1. Go to Firebase Console → Analytics
2. Check for recent events

### 3.2 Add Custom Events for AI Usage

These are implemented in the updated code:
- `ai_request_started` - When AI request begins
- `ai_request_completed` - When AI responds successfully
- `ai_request_failed` - When AI request fails
- `ai_rate_limit_hit` - When user hits rate limit

View in: Firebase Console → Analytics → Events

---

## Step 4: Set Up Billing Alerts

### 4.1 Enable Billing Monitoring

1. Go to Google Cloud Console: https://console.cloud.google.com/billing?project=amen-5e359
2. Click **"Budgets & alerts"** in left sidebar
3. Click **"Create Budget"**

### 4.2 Configure Budget Alert

Fill in:
- **Name:** "Gemini API Usage Alert"
- **Projects:** Select "amen-5e359"
- **Services:** Select "Generative Language API"
- **Budget type:** Specified amount
- **Target amount:** Enter your monthly budget (e.g., $50)

**Alert thresholds:** (recommended)
- 50% of budget
- 80% of budget
- 100% of budget

**Email recipients:** Add your email

Click **"Finish"**

### 4.3 Set Up Quota Monitoring

1. Go to: https://console.cloud.google.com/apis/api/generativelanguage.googleapis.com/quotas?project=amen-5e359
2. Monitor:
   - Requests per minute: 60 (free tier)
   - Requests per day: Check current limit

---

## Step 5: Monitor API Abuse

### 5.1 Check Firebase Analytics Daily

Monitor these metrics:
- `ai_request_started` count - Total AI requests
- `ai_rate_limit_hit` count - Users hitting limits
- `ai_request_failed` count - Error rate

**Alert if:**
- Failed requests > 20% of total
- Rate limit hits increasing rapidly
- Unusual spike in requests from single user

### 5.2 Set Up Cloud Monitoring (Advanced)

1. Go to: https://console.cloud.google.com/monitoring?project=amen-5e359
2. Create dashboard for Generative Language API
3. Add charts:
   - Request count over time
   - Error rate
   - Latency

---

## Step 6: Testing Checklist

After implementing all changes:

- [ ] Verify Remote Config returns API key correctly
- [ ] Test app launches successfully
- [ ] Test Berean AI works
- [ ] Test rate limiting (try 15 requests quickly)
- [ ] Check Firebase Analytics shows AI events
- [ ] Verify billing alerts are configured
- [ ] Test with iOS bundle restriction enabled

---

## Emergency Procedures

### If API Key is Compromised

1. **Immediately disable in Google Cloud Console:**
   - Go to Credentials page
   - Click the key
   - Click "Disable" (don't delete yet)

2. **Create new key:**
   - Click "Create Credentials" → "API Key"
   - Add iOS bundle restriction immediately
   - Copy new key

3. **Update Remote Config:**
   - Go to Firebase Remote Config
   - Update `gemini_api_key` parameter
   - Publish changes

4. **Force app update:**
   - Users will fetch new key on next launch
   - Or release hotfix update if needed

### If Usage Spikes Unexpectedly

1. Check Firebase Analytics for abuse patterns
2. Temporarily disable AI in Remote Config:
   - Set `ai_features_enabled` = false
   - Publish changes
3. Investigate source of spike
4. Re-enable once resolved

---

## Cost Estimation

**Free Tier (Current):**
- 60 requests per minute
- 1,500 requests per day
- Good for small user base

**When to Upgrade:**
- Users > 100 daily active
- AI requests > 1,000/day consistently
- Need higher rate limits

**Paid Tier Pricing (estimate):**
- Gemini 2.5 Flash: ~$0.001 per 1K tokens
- Average conversation: ~500 tokens
- 1,000 conversations/day ≈ $0.50/day ≈ $15/month

**Monitor monthly costs** in Google Cloud Console → Billing

---

## Security Best Practices

✅ **Do:**
- Keep API key in Remote Config
- Use iOS bundle restriction
- Monitor usage daily
- Set billing alerts
- Implement rate limiting
- Log suspicious patterns

❌ **Don't:**
- Hardcode API keys in app
- Share API keys publicly
- Ignore usage spikes
- Skip billing alerts
- Allow unlimited requests

---

## Status After Implementation

After completing all steps:

✅ API key secured in Remote Config
✅ iOS bundle restriction active
✅ Rate limiting implemented
✅ Usage monitoring enabled
✅ Billing alerts configured
✅ Abuse detection ready

**Your app is production-ready for AI features!**

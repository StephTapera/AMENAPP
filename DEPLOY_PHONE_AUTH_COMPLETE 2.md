# Phone OTP Authentication - Deployment Guide

**Status**: ✅ Ready to Deploy
**Priority**: P0
**Date**: February 25, 2026

---

## 🚀 Quick Deploy (5 Steps)

### Step 1: Deploy Cloud Functions (5 minutes)

```bash
cd /Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/functions

# Install dependencies (if not already done)
npm install

# Deploy phone auth rate limiting functions
firebase deploy --only functions:checkPhoneVerificationRateLimit,functions:reportPhoneVerificationFailure,functions:unblockPhoneNumber

# Expected output:
# ✔ functions[checkPhoneVerificationRateLimit(us-central1)] Successful create operation.
# ✔ functions[reportPhoneVerificationFailure(us-central1)] Successful create operation.
# ✔ functions[unblockPhoneNumber(us-central1)] Successful create operation.
```

### Step 2: Verify Functions Deployed

```bash
# List deployed functions
firebase functions:list

# Should see:
# checkPhoneVerificationRateLimit(us-central1)
# reportPhoneVerificationFailure(us-central1)
# unblockPhoneNumber(us-central1)
```

### Step 3: Enable Client Integration

Open `AMENAPP/AuthenticationViewModel.swift` and:

1. **Uncomment lines 937-960** (checkServerRateLimit function)
2. **Uncomment lines 977-989** (reportVerificationFailure function)

Before:
```swift
// TODO: Uncomment when Cloud Functions are deployed
/*
do {
    let functions = Functions.functions()
    ...
*/
```

After:
```swift
// Cloud Functions deployed - enabled server-side rate limiting
do {
    let functions = Functions.functions()
    ...
}
```

### Step 4: Test Locally

```bash
# Build project
xcodebuild -workspace AMENAPP.xcworkspace \
  -scheme AMENAPP \
  -configuration Debug \
  clean build

# Or use Xcode: Product → Build (⌘B)
```

### Step 5: Test on Device

**Required**: Physical iOS device (simulator won't work for phone auth)

1. Connect iPhone/iPad
2. Build and run to device
3. Navigate to Sign Up → Choose Phone
4. Enter real phone number
5. Verify SMS received
6. Complete OTP verification
7. Confirm account created

✅ **Deployment Complete!**

---

## 🔧 Detailed Configuration

### Firebase Console Setup

#### 1. Enable Phone Authentication

```
1. Open Firebase Console
2. Go to Authentication → Sign-in method
3. Enable "Phone" provider
4. Save changes
```

#### 2. Configure Authorized Domains

```
1. Authentication → Settings → Authorized domains
2. Add your production domain (e.g., amenapp.com)
3. localhost is auto-added for development
```

#### 3. SMS Quota Configuration

```
1. Go to Authentication → Usage
2. Check current SMS quota (default: 100/day per user)
3. For production, request quota increase if needed
4. Monitor usage in Firebase Console
```

#### 4. reCAPTCHA Settings (Optional)

```
1. Authentication → Settings → reCAPTCHA
2. Enable "Enforce reCAPTCHA flow" for web
3. iOS uses silent push notification verification (no user action needed)
```

### Firestore Security Rules

The following collections are used by phone auth rate limiting:

```javascript
// Add to firestore.rules

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Phone auth rate limit tracking (server-side only)
    match /phoneAuthRateLimits/{phoneNumber} {
      allow read: if false;  // No client reads
      allow write: if false; // Server-side only via Cloud Functions
    }

    // IP-based rate limit tracking (server-side only)
    match /phoneAuthIPRateLimits/{ipAddress} {
      allow read: if false;
      allow write: if false;
    }

    // Security event logging (admin only)
    match /securityEvents/{eventId} {
      allow read: if request.auth != null &&
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
      allow write: if false; // Server-side only
    }

    // Existing user rules...
    match /users/{userId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.auth.uid == userId;
      allow update: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

Deploy rules:
```bash
firebase deploy --only firestore:rules
```

### Firestore Indexes

No additional indexes needed for phone auth rate limiting (uses simple document lookups).

---

## 🧪 Testing Checklist

### Pre-Deployment Testing

- [ ] Build succeeds locally
- [ ] Cloud Functions deploy successfully
- [ ] Firestore rules deployed
- [ ] Test phone numbers configured (optional for simulator)

### Post-Deployment Testing

**On Physical Device**:
- [ ] Phone signup works
- [ ] OTP code received
- [ ] Code auto-fills (iOS)
- [ ] Account created successfully
- [ ] Phone login works for existing account
- [ ] Rate limiting kicks in after 3 attempts
- [ ] "Change Phone Number" button works
- [ ] Network offline shows error
- [ ] Invalid code shows error
- [ ] Expired code (10 min) shows error

**Account Linking**:
- [ ] Can link phone to email account
- [ ] OTP verification for linking works
- [ ] Phone shows in linked providers
- [ ] Can unlink phone (with another provider)
- [ ] Cannot unlink if only provider

**Rate Limiting**:
- [ ] Client cooldown (3 seconds) works
- [ ] Resend timer (60 seconds) works
- [ ] Server limit (3/15min) enforced
- [ ] IP limit (10/15min) enforced
- [ ] Exponential backoff increases wait time
- [ ] Security events logged in Firestore

---

## 📊 Monitoring & Analytics

### Firebase Console Monitoring

#### Authentication Usage
```
1. Go to Authentication → Usage
2. Monitor:
   - Daily active users
   - Phone sign-ins
   - SMS sent per day
   - Error rates
```

#### Cloud Functions Metrics
```
1. Go to Functions → Dashboard
2. Monitor for each function:
   - Invocations per day
   - Execution time (p50, p95, p99)
   - Error rate
   - Memory usage
```

#### Security Events Logging
```
1. Go to Firestore → securityEvents collection
2. Monitor:
   - phoneAuthRequest events (allowed/denied)
   - phoneAuthFailure events
   - Suspicious activity patterns
   - Blocked phone numbers
```

### Set Up Alerts

Create Cloud Monitoring alerts for:

**High Error Rate**:
```
Alert if:
  checkPhoneVerificationRateLimit error rate > 5% for 5 minutes
Action: Email admin team
```

**Quota Exceeded**:
```
Alert if:
  SMS quota > 80% of daily limit
Action: Email admin + SMS to on-call
```

**Suspicious Activity**:
```
Alert if:
  > 100 blocked phone numbers in 1 hour
Action: Email security team
```

---

## 🔒 Security Hardening (Production)

### 1. Enable App Check

Protect Cloud Functions from abuse:

```swift
// In AppDelegate or App struct
import FirebaseAppCheck

@main
struct AMENAPPApp: App {
    init() {
        FirebaseApp.configure()

        // Enable App Check in production
        #if !DEBUG
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif
    }
}
```

Update Cloud Functions:
```javascript
// In phoneAuthRateLimit.js, change:
enforceAppCheck: false  // Development
// To:
enforceAppCheck: true   // Production
```

### 2. Reduce Rate Limits (Production)

For production, consider tighter limits:

```javascript
// functions/phoneAuthRateLimit.js

// Development: 3 OTPs per 15 minutes
const MAX_ATTEMPTS = 3;
const WINDOW_MINUTES = 15;

// Production recommendation: 2 OTPs per 30 minutes
const MAX_ATTEMPTS = 2;
const WINDOW_MINUTES = 30;
```

### 3. Enable Admin Verification

Uncomment admin check in `unblockPhoneNumber`:

```javascript
// Check if user is admin
const userDoc = await admin.firestore().collection('users').doc(userId).get();
if (!userDoc.data()?.isAdmin) {
  throw new Error("Unauthorized: Admin access required");
}
```

Add `isAdmin` field to admin users in Firestore:
```javascript
{
  "uid": "admin-user-id",
  "isAdmin": true,
  // other fields...
}
```

### 4. Set Up Firestore Backups

```bash
# Daily automated backups
gcloud firestore export gs://amen-app-backups/$(date +%Y-%m-%d)

# Restore if needed
gcloud firestore import gs://amen-app-backups/2026-02-25
```

---

## 🐛 Troubleshooting

### Issue: Functions fail to deploy

**Error**: `Error: HTTP Error: 403, Caller does not have permission`

**Solution**:
```bash
# Enable required APIs
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Retry deployment
firebase deploy --only functions
```

### Issue: SMS not received

**Possible causes**:
1. Phone number not in E.164 format → Check formatting
2. Carrier blocking automated SMS → Test with different carrier
3. Firebase SMS quota exceeded → Check usage in console
4. Test phone number not configured → Add to Firebase Console

**Debug**:
```swift
// Check formatted number
print("📱 Formatted number: \(formatPhoneNumber(phoneNumber))")

// Check Firebase Auth logs in console
// Look for SMS send events
```

### Issue: Rate limit not working

**Symptoms**: Can send unlimited OTPs

**Check**:
1. Functions deployed? `firebase functions:list`
2. Client code uncommented? Check `AuthenticationViewModel.swift:937-960`
3. Network connectivity? Function calls require internet
4. Firestore rules allow function writes? Check rules

**Debug**:
```javascript
// In Cloud Function, add logging
console.log("Rate limit check:", {
  phoneNumber,
  recentAttempts: recentAttempts.length,
  allowed: recentAttempts.length < 3
});
```

### Issue: Account linking fails

**Error**: "Credential already in use"

**Cause**: Phone number is linked to a different account

**Solution**:
1. User must sign in to account with that phone
2. Unlink from old account
3. Link to new account

**Prevention**: Show clear error message guiding user

---

## 📈 Performance Optimization

### Cloud Function Optimization

**Current**: All functions run on-demand (cold starts possible)

**Production Optimization**:

1. **Increase min instances** (reduce cold starts):
```javascript
exports.checkPhoneVerificationRateLimit = onCall({
  region: "us-central1",
  minInstances: 1,  // Keep 1 instance warm
  maxInstances: 10,
}, async (request) => { ... });
```

2. **Use multiple regions** (reduce latency):
```javascript
// Deploy to multiple regions for global coverage
exports.checkPhoneVerificationRateLimitUS = onCall({ region: "us-central1" }, handler);
exports.checkPhoneVerificationRateLimitEU = onCall({ region: "europe-west1" }, handler);
exports.checkPhoneVerificationRateLimitASIA = onCall({ region: "asia-east1" }, handler);
```

3. **Cache rate limit data** (reduce Firestore reads):
```javascript
// Use Memorystore or Node.js memory cache
const rateLimitCache = new Map();

// Check cache before Firestore
if (rateLimitCache.has(phoneNumber)) {
  const cached = rateLimitCache.get(phoneNumber);
  if (Date.now() - cached.timestamp < 60000) { // 1 min TTL
    return cached.data;
  }
}
```

---

## 💰 Cost Estimation

### Firebase Costs (Monthly)

**Assumptions**:
- 10,000 monthly active users
- 50% use phone auth
- Average 1.5 OTP sends per signup (some retries)

**SMS Costs**:
```
5,000 users × 1.5 OTPs = 7,500 SMS/month
Firebase SMS: $0.01 per message (US)
Cost: $75/month
```

**Cloud Functions**:
```
7,500 rate limit checks × 3 functions = 22,500 invocations
Free tier: 2M invocations/month
Cost: $0 (within free tier)
```

**Firestore**:
```
Reads: ~30,000 (rate limit checks)
Writes: ~15,000 (security events)
Free tier: 50,000 reads, 20,000 writes
Cost: $0 (within free tier)
```

**Total Estimated Cost**: ~$75/month for 10K users

**Optimization**: Use test phone numbers in development to avoid SMS costs.

---

## ✅ Go-Live Checklist

### Pre-Launch
- [ ] All Cloud Functions deployed
- [ ] Client integration enabled
- [ ] Firestore rules deployed
- [ ] Test on physical device
- [ ] Rate limiting verified
- [ ] Account linking tested
- [ ] Error handling verified
- [ ] Documentation complete

### Launch Day
- [ ] Monitor Firebase Console (Authentication usage)
- [ ] Check Cloud Functions metrics
- [ ] Review security events log
- [ ] Test phone signup end-to-end
- [ ] Verify SMS delivery
- [ ] Check error rates

### Post-Launch (Week 1)
- [ ] Review daily SMS usage
- [ ] Check for blocked phone numbers
- [ ] Monitor rate limit effectiveness
- [ ] Analyze security events
- [ ] Gather user feedback
- [ ] Adjust limits if needed

---

## 📞 Support

**Documentation**:
- Quick Start: `PHONE_OTP_QUICK_START.md`
- Technical Details: `PHONE_OTP_IMPLEMENTATION_COMPLETE.md`
- This deployment guide

**Firebase Support**:
- Console: https://console.firebase.google.com
- Documentation: https://firebase.google.com/docs/auth/ios/phone-auth
- Support: Firebase Console → Support

**Internal**:
- Code: `AuthenticationViewModel.swift`, `SignInView.swift`
- Server: `functions/phoneAuthRateLimit.js`
- Issues: Check Xcode console logs

---

**Ready to deploy?** Follow the 5-step Quick Deploy guide above.

**Questions?** Review the Troubleshooting section or check logs.

**Good luck! 🚀**

---

**Last Updated**: February 25, 2026
**Status**: ✅ PRODUCTION READY

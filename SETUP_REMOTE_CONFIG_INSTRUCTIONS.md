# Setup Instructions for Production Security

## Step 1: Add New Files to Xcode

The following files have been created and need to be added to your Xcode project:

1. `AMENAPP/RemoteConfigManager.swift` - Manages Remote Config
2. `AMENAPP/AIRateLimiter.swift` - Rate limiting system
3. `AMENAPP/AIUsageMonitor.swift` - Usage monitoring and analytics
4. `AMENAPP/AppLaunchConfig.swift` - App launch configuration

### How to Add:
1. In Xcode, right-click on the `AMENAPP` folder
2. Select "Add Files to AMENAPP..."
3. Navigate to the AMENAPP folder
4. Select all 4 new .swift files
5. Make sure "Copy items if needed" is checked
6. Click "Add"

---

## Step 2: Initialize Remote Config on App Launch

Update `AMENAPPApp.swift` to initialize Remote Config:

```swift
import SwiftUI
import FirebaseCore

@main
struct AMENAPPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Configure Firebase (already done)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        // NEW: Initialize Remote Config and monitoring
        AppLaunchConfig.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

## Step 3: Set Up Firebase Remote Config

### 3.1 Go to Firebase Console

https://console.firebase.google.com/project/amen-5e359/config

### 3.2 Add Parameters

Click "Add parameter" for each of these:

**Parameter 1: gemini_api_key**
- Key: `gemini_api_key`
- Type: String
- Default value: `<GOOGLE_AI_API_KEY>`
- Description: Gemini API key for AI features

**Parameter 2: ai_features_enabled**
- Key: `ai_features_enabled`
- Type: Boolean
- Default value: `true`
- Description: Master kill switch for AI features

**Parameter 3: ai_safety_enabled**
- Key: `ai_safety_enabled`
- Type: Boolean
- Default value: `false`
- Description: Enable AI safety filtering (disabled for faith content)

**Parameter 4: ai_rate_limit_per_minute**
- Key: `ai_rate_limit_per_minute`
- Type: Number
- Default value: `10`
- Description: Max AI requests per user per minute

### 3.3 Publish Changes

Click "Publish changes" button at the top of the Remote Config page.

---

## Step 4: Add iOS Bundle Restriction to API Key

### 4.1 Go to Google Cloud Console

https://console.cloud.google.com/apis/credentials?project=amen-5e359

### 4.2 Edit API Key

1. Find key: `<GOOGLE_AI_API_KEY>`
2. Click pencil icon (Edit)
3. Under "Application restrictions", select "iOS apps"
4. Click "Add an item"
5. Enter bundle ID: `tapera.AMENAPP`
6. Click "Done"
7. Click "Save"

**Wait 5 minutes for changes to propagate**

---

## Step 5: Build and Test

### 5.1 Clean Build

In Xcode:
- Press `⌘ + Shift + K` (Clean)
- Press `⌘ + B` (Build)

### 5.2 Test Features

Run the app and test:

1. **Berean AI**
   - Send a message
   - Should work normally
   - Console should show: "🔐 Using API key from Remote Config"

2. **Rate Limiting**
   - Send 15 messages quickly
   - 11th+ should show rate limit error
   - Console should show: "⚠️ Rate limit exceeded"

3. **Remote Config**
   - Check console for: "✅ Remote Config fetched from server"
   - If you see "⚠️ Using fallback API key", Remote Config isn't ready yet

4. **Analytics**
   - Go to Firebase Console → Analytics → Events
   - Look for events:
     - `ai_request_started`
     - `ai_request_completed`
     - `ai_rate_limit_hit`

### 5.3 Test Kill Switch

In Firebase Remote Config:
1. Set `ai_features_enabled` to `false`
2. Click "Publish changes"
3. Restart app (to fetch new config)
4. Try Berean AI
5. Should show "AI features are temporarily disabled"

---

## Step 6: Monitor Usage

### Daily Monitoring

Check these daily in Firebase Console:

**Analytics → Events:**
- `ai_request_started` - Total requests
- `ai_request_failed` - Error rate (should be <5%)
- `ai_rate_limit_hit` - Abuse attempts

**Google Cloud Console → APIs:**
https://console.cloud.google.com/apis/api/generativelanguage.googleapis.com/metrics?project=amen-5e359

- Requests per day
- Error rate
- Latency

### Set Up Alerts

**Billing Alert:**
https://console.cloud.google.com/billing/budgets?project=amen-5e359

Create budget alert for Generative Language API

**Usage Alert:**
If requests spike >10x normal, investigate for abuse

---

## Troubleshooting

### "Using fallback API key" in Console

**Cause:** Remote Config not fetched yet

**Fix:**
1. Check internet connection
2. Wait 10 seconds after app launch
3. Check Firebase Console shows the parameters
4. Restart app

### "Rate limit exceeded" on first request

**Cause:** Rate limiter initialized incorrectly

**Fix:**
1. Check Remote Config parameter `ai_rate_limit_per_minute`
2. Should be ≥1
3. Default is 10

### API key doesn't work after bundle restriction

**Cause:** Need to wait for propagation

**Fix:**
1. Wait 5 minutes
2. Rebuild app
3. If still fails, check bundle ID matches exactly

---

## Production Checklist

Before releasing to TestFlight/App Store:

- [ ] All 4 new files added to Xcode project
- [ ] AppLaunchConfig.configure() called in App.swift
- [ ] Remote Config parameters added in Firebase Console
- [ ] iOS bundle restriction added to API key
- [ ] Billing alerts configured
- [ ] Tested rate limiting works
- [ ] Tested Remote Config fetch works
- [ ] Verified analytics events appear
- [ ] Tested kill switch works

---

## Security Status

**After completing all steps:**

✅ API key secured in Remote Config
✅ iOS bundle restriction active
✅ Rate limiting prevents abuse
✅ Usage monitoring enabled
✅ Billing alerts configured
✅ Kill switch ready for emergencies

**Your app is now production-ready for AI features!**

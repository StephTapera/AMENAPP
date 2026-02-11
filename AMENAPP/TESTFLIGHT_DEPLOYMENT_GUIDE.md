# TestFlight Deployment Checklist for Berean AI

## ✅ Pre-Flight Checklist

### 1. Verify Genkit Server is Live

**Test the production endpoint:**

```bash
# Test if server is responding
curl https://genkit-amen-78278013543.us-central1.run.app/health

# Test the bibleChat flow
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

### 2. Deploy Genkit Server (If Not Already Deployed)

If the above test fails, deploy your server:

```bash
# Navigate to genkit-flows directory
cd genkit-flows

# Option A: Deploy via npm script (if configured)
npm run deploy

# Option B: Deploy manually with gcloud
gcloud run deploy genkit-amen \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 2Gi \
  --timeout 300s \
  --max-instances 10
```

**Verify deployment:**
```bash
# Get the service URL
gcloud run services describe genkit-amen \
  --platform managed \
  --region us-central1 \
  --format 'value(status.url)'
```

---

## 🔧 Code Changes Required

### Change 1: Update BereanAIAssistantView.swift

Remove or disable the DEBUG-only mock fallback for production:

```swift
// In BereanViewModel.generateResponseStreaming()

// ❌ REMOVE THIS FOR PRODUCTION:
#if DEBUG
print("🔄 Using mock fallback response (DEBUG mode only)")
let fallbackMessage = generateMockResponse(for: query)
await MainActor.run {
    onComplete(fallbackMessage)
}
#endif

// ✅ REPLACE WITH:
// Don't use mock responses - let the error propagate to the user
// The error banner will show them what went wrong
```

### Change 2: Add Production Error Messages

Update error handling to be user-friendly:

```swift
// In BereanAIAssistantView.swift, sendMessage function

onError: { error in
    print("❌ Error generating response: \(error.localizedDescription)")
    
    // ... existing error handling ...
    
    // ✅ Add user-friendly production errors
    if !Task.isCancelled {
        let bereanError: BereanError
        
        if let genkitError = error as? GenkitError {
            switch genkitError {
            case .invalidURL:
                bereanError = .unknown("Configuration error. Please update the app.")
            case .invalidResponse:
                bereanError = .unknown("Unable to process response. Please try again.")
            case .httpError(let statusCode):
                if statusCode == 429 {
                    bereanError = .rateLimitExceeded
                } else if statusCode >= 500 {
                    bereanError = .aiServiceUnavailable
                } else if statusCode == 503 {
                    bereanError = .unknown("AI service is temporarily unavailable. Please try again in a moment.")
                } else {
                    bereanError = .unknown("Server error. Please try again.")
                }
            case .networkError:
                bereanError = .networkUnavailable
            }
        } else if let urlError = error as? URLError {
            if urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                bereanError = .networkUnavailable
            } else if urlError.code == .timedOut {
                bereanError = .unknown("Request took too long. Please try again.")
            } else {
                bereanError = .unknown("Network error. Please check your connection.")
            }
        } else {
            bereanError = .unknown("Something went wrong. Please try again.")
        }
        
        // Show error
        showError = bereanError
        showErrorBanner = true
    }
}
```

### Change 3: Enable Firebase Offline Persistence

**Critical for TestFlight!** Add this to your app initialization:

```swift
// In AMENAPPApp.swift (or AppDelegate.swift)

import SwiftUI
import FirebaseCore
import FirebaseDatabase

@main
struct AMENAPPApp: App {
    
    init() {
        // Configure Firebase
        FirebaseApp.configure()
        
        // ✅ CRITICAL: Enable offline persistence for production
        Database.database().isPersistenceEnabled = true
        Database.database().persistenceCacheSizeBytes = 50 * 1024 * 1024 // 50MB
        
        print("✅ Firebase configured with offline persistence")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Change 4: Add API Key for Production (Recommended)

Secure your Genkit endpoint with an API key:

**Step 1: Generate an API key**
```bash
# Generate a secure random key
openssl rand -base64 32
```

**Step 2: Add to Cloud Run environment**
```bash
gcloud run services update genkit-amen \
  --region us-central1 \
  --set-env-vars "API_KEY=your-generated-key-here"
```

**Step 3: Update your Genkit flows to check the key**
```typescript
// In your genkit flow
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
  async (input, { auth }) => {
    // ✅ Check API key
    const apiKey = process.env.API_KEY;
    if (apiKey && auth?.token !== apiKey) {
      throw new Error('Unauthorized');
    }
    
    // ... rest of your flow
  }
);
```

**Step 4: Add key to Xcode**

Add to `Info.plist`:
```xml
<key>GENKIT_API_KEY</key>
<string>your-generated-key-here</string>
```

---

## 🧪 Testing Before TestFlight

### 1. Test Network Scenarios

```swift
// Test checklist:
- [ ] Works with WiFi
- [ ] Works with cellular data
- [ ] Shows offline message when airplane mode is on
- [ ] Recovers gracefully when network comes back
- [ ] Error messages are user-friendly
```

### 2. Test AI Responses

```swift
// Test these scenarios:
- [ ] Simple question: "What does John 3:16 mean?"
- [ ] Complex question: "Compare different interpretations of Genesis 1"
- [ ] Follow-up questions in conversation
- [ ] Stop generation mid-response
- [ ] Retry after error
- [ ] Share AI response to OpenTable feed
```

### 3. Test Error Scenarios

```swift
// Simulate errors:
- [ ] Disconnect WiFi mid-request (should show error banner)
- [ ] Send very long message (should handle gracefully)
- [ ] Send empty message (should be prevented)
- [ ] Rapid-fire multiple messages (should queue properly)
```

### 4. Performance Testing

```swift
// Monitor these metrics:
- [ ] Time to first response chunk (< 2 seconds ideal)
- [ ] Streaming smoothness (no stuttering)
- [ ] Memory usage (check for leaks)
- [ ] Battery impact (run for 30 minutes)
```

---

## 📱 Xcode Configuration for TestFlight

### 1. Update Build Configuration

**Set the correct endpoint:**

In `Info.plist`:
```xml
<key>GENKIT_ENDPOINT</key>
<string>https://genkit-amen-78278013543.us-central1.run.app</string>

<!-- Optional: Add API key -->
<key>GENKIT_API_KEY</key>
<string>your-generated-key-here</string>
```

### 2. Update Build Settings

**Archive configuration:**
- Build Configuration: **Release**
- Code Signing: **Automatic**
- Team: **Your Apple Developer Team**

### 3. Version Numbers

Update version for TestFlight:

```swift
// In Xcode:
// Target → General → Identity
Version: 1.0.0 (or your current version)
Build: Increment by 1 (e.g., 42 → 43)
```

### 4. What's New Notes

Prepare release notes for TestFlight testers:

```
🆕 Berean AI Assistant (Beta)

New Features:
• Intelligent Bible study companion powered by AI
• Ask questions about Scripture in natural language
• Get detailed explanations, context, and cross-references
• Continue conversations with follow-up questions
• Save and share insights to OpenTable feed

How to Use:
1. Tap the Berean AI tab
2. Type or speak your question
3. Receive instant, detailed responses
4. Explore Smart Features for guided topics

Known Limitations:
• Requires internet connection
• Response quality depends on question clarity
• May take 10-30 seconds for complex questions

Please Report:
• Any incorrect Biblical information
• App crashes or freezes
• Slow or empty responses
• UI/UX issues
```

---

## 🚢 Upload to TestFlight

### Step 1: Archive the Build

```
1. In Xcode: Product → Archive
2. Wait for archive to complete
3. Organizer window will open
```

### Step 2: Validate the Archive

```
1. Select your archive
2. Click "Validate App"
3. Choose your distribution method: App Store Connect
4. Fix any validation errors
```

### Step 3: Distribute to TestFlight

```
1. Click "Distribute App"
2. Choose "App Store Connect"
3. Select "Upload"
4. Wait for upload to complete (5-15 minutes)
```

### Step 4: Configure in App Store Connect

```
1. Go to https://appstoreconnect.apple.com
2. Select your app
3. Go to TestFlight tab
4. Select the new build
5. Fill out "What to Test" field
6. Add Berean AI features to the description
7. Save changes
```

### Step 5: Add Test Information

**Export Compliance:**
```
Does your app use encryption? YES
Is it exempt? NO (if using HTTPS)
Add encryption registration number (if you have one)
```

**Beta App Review:**
```
If this is a new feature, provide:
• Demo account credentials
• Test data or scenarios
• Screenshots showing the feature
• Any special instructions
```

---

## 🔍 Monitoring & Analytics

### 1. Add Logging for Production

```swift
// Add this to BereanGenkitService.swift

func logAIInteraction(query: String, responseTime: TimeInterval, success: Bool) {
    // Log to Firebase Analytics
    Analytics.logEvent("berean_ai_query", parameters: [
        "query_length": query.count,
        "response_time_ms": Int(responseTime * 1000),
        "success": success,
        "endpoint": genkitEndpoint
    ])
}
```

### 2. Monitor Cloud Run Metrics

```bash
# View logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=genkit-amen" \
  --limit 50 \
  --format json

# View metrics in Cloud Console
https://console.cloud.google.com/run/detail/us-central1/genkit-amen/metrics
```

### 3. Set Up Alerts

Create alerts for:
- [ ] High error rate (> 5%)
- [ ] Slow response time (> 10 seconds)
- [ ] High memory usage (> 80%)
- [ ] Service downtime

---

## 🐛 Troubleshooting Guide for Testers

Include this in your TestFlight notes:

```markdown
## Troubleshooting

**AI not responding:**
1. Check internet connection
2. Try force-quitting and reopening the app
3. Report the issue with screenshot

**Slow responses:**
• First response may be slower (cold start)
• Complex questions take longer
• Try simplifying your question

**Empty responses:**
• This is a bug - please report!
• Include the question you asked
• Try again in a few minutes

**App crashes:**
• Please report via TestFlight
• Include steps to reproduce
• Note: We're actively fixing bugs
```

---

## ✅ Final Checklist

Before uploading to TestFlight:

- [ ] Genkit server is deployed and responding
- [ ] Tested on real device (not simulator)
- [ ] Firebase offline persistence enabled
- [ ] Production endpoint configured in Info.plist
- [ ] Mock responses disabled for production
- [ ] Error messages are user-friendly
- [ ] Build number incremented
- [ ] Release notes prepared
- [ ] Export compliance information ready
- [ ] Tested all critical flows:
  - [ ] Send message
  - [ ] Stop generation
  - [ ] Save message
  - [ ] Share to feed
  - [ ] Offline mode
  - [ ] Error recovery

---

## 📊 Success Metrics to Track

Monitor these after TestFlight release:

**Usage Metrics:**
- Number of AI queries per user
- Average session length
- Most common question types
- Conversion: users who try AI → active users

**Performance Metrics:**
- Average response time
- Error rate
- Crash rate
- Network failure rate

**Quality Metrics:**
- User ratings/feedback
- Feature requests
- Bug reports
- Share-to-feed usage

---

## 🎯 Next Steps After TestFlight

1. **Collect feedback** from testers (1 week)
2. **Fix critical bugs** reported
3. **Optimize performance** based on metrics
4. **Add requested features** if valuable
5. **Prepare for App Store** submission

---

## 🆘 Need Help?

If you encounter issues:

1. Check `GENKIT_HOSTING_PRODUCTION_GUIDE.md`
2. Review logs in Cloud Console
3. Test endpoint manually with curl
4. Check Firebase console for errors
5. Verify App Store Connect status

---

## 🎉 Ready to Ship!

Once all items are checked, you're ready to:

```bash
# 1. Archive in Xcode
Product → Archive

# 2. Validate
Validate App

# 3. Upload
Distribute App → TestFlight

# 4. Monitor
Watch Cloud Run logs and TestFlight Feedback
```

**Good luck with your TestFlight launch! 🚀**

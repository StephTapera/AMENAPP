# Deploy AI Moderation to Firebase - Quick Guide

## What You Have
✅ **AI Moderation Function Already Created!**
- File: `functions/aiModeration.js`
- Exports: `moderateContent`, `detectCrisis`, `deliverBatchedNotifications`
- Already linked in `functions/index.js`

## What It Does
The `moderateContent` function:
1. Listens for new documents in `moderationRequests/{requestId}`
2. Analyzes content using basic keyword filtering
3. Stores results in `moderationResults/{requestId}`
4. Swift app retrieves the result

## Deploy to Firebase

### Step 1: Make Sure You're Logged In
```bash
firebase login
```

### Step 2: Deploy ONLY the AI Moderation Function
```bash
cd /Users/stephtapera/Desktop/AMEN/AMENAPP\ copy
firebase deploy --only functions:moderateContent
```

Or deploy all AI functions at once:
```bash
firebase deploy --only functions:moderateContent,functions:detectCrisis,functions:deliverBatchedNotifications
```

### Step 3: Verify Deployment
After deployment, you should see:
```
✔  functions[moderateContent(us-central1)] Successful create operation.
Function URL: https://us-central1-amen-5e359.cloudfunctions.net/moderateContent
```

### Step 4: Test the Function
Post a test comment in your app. You should see in Firebase Console logs:
```
🛡️ [MODERATION] Processing request {requestId}
✅ [MODERATION] Request {requestId}: safe
```

## Re-Enable AI Moderation in Swift

Once deployed, uncomment the code in `ContentModerationService.swift:203-226`:

### Before (Current - Bypassed):
```swift
// ✅ QUICK FIX: Skip Firebase AI Logic for now
print("⚠️ [MODERATION] AI Logic not deployed - using fallback approval")
return ModerationResult(isApproved: true, ...)
```

### After (Uncomment the real implementation):
```swift
// Prepare request payload for Firebase AI Logic
let requestData: [String: Any] = [
    "content": content,
    "contentType": type.rawValue,
    "userId": userId,
    "timestamp": FieldValue.serverTimestamp()
]

do {
    let result = try await db.collection("moderationRequests")
        .addDocument(data: requestData)

    let response = try await waitForModerationResponse(requestId: result.documentID)
    return response
} catch {
    // Fallback on error
    return ModerationResult(isApproved: true, ...)
}
```

## What the Function Currently Does

### Basic Keyword Filtering (performBasicModeration)
Checks for:
- ✅ Profanity: "f***", "s***", "damn", "hell", "wtf"
- ✅ Returns blocked status if found
- ✅ Returns safe status if clean

### Future: AI-Powered Analysis
Line 101 has a TODO for Firebase AI Logic extension:
```javascript
// TODO: Replace with actual Firebase AI Logic extension call
// For now, return basic keyword filtering
return performBasicModeration(content);
```

You can upgrade this later to use:
- Vertex AI (Google's AI)
- OpenAI API
- Firebase Extensions (Perspective API)

## Deployment Command Summary

**Quick Deploy (just moderation):**
```bash
firebase deploy --only functions:moderateContent
```

**Full Deploy (all functions):**
```bash
firebase deploy --only functions
```

**Check logs after deployment:**
```bash
firebase functions:log
```

## Expected Flow After Deployment

### User Posts Comment:
1. Swift: Creates document in `moderationRequests/{id}`
2. Cloud Function: Triggered automatically
3. Cloud Function: Analyzes content (basic keywords)
4. Cloud Function: Writes result to `moderationResults/{id}`
5. Swift: Retrieves result (waits max 5 seconds)
6. Swift: Approves or blocks comment based on result

### Logs You'll See:
```
// Swift App
🛡️ Running AI moderation check for comment...
🛡️ [MODERATION] Checking comment content...
🛡️ [MODERATION] AI moderation check initiated

// Cloud Function (Firebase Console)
🛡️ [MODERATION] Processing request ABC123
✅ [MODERATION] Request ABC123: safe

// Swift App
🛡️ [MODERATION] AI check: safe (confidence: 0.9)
✅ Comment passed moderation check
✅ Comment data written to RTDB successfully
```

## Current Behavior (AI Bypassed)
For now, since the function isn't deployed:
- ✅ Comments post immediately (bypass enabled)
- ✅ Basic local checks still run (profanity, spam)
- ✅ No waiting for Cloud Function response
- ✅ App won't hang or timeout

## Troubleshooting

### Deployment Failed?
```bash
# Check Firebase project
firebase use

# Should show: amen-5e359 (current)

# Check Node.js version
node --version
# Should be v18 or v20
```

### Function Not Triggering?
- Check Firebase Console → Functions → Logs
- Verify Firestore security rules allow writes to `moderationRequests`
- Check that function region matches (us-central1)

### Still Timing Out?
Increase timeout in `ContentModerationService.swift:231`:
```swift
for _ in 0..<10 { // Increase from 10 to 20
    try await Task.sleep(nanoseconds: 500_000_000)
    ...
}
```

## Cost Estimate
- **Firestore writes:** $0.18 per 100K writes
- **Cloud Function invocations:** $0.40 per 1M invocations
- **Each comment:** ~2 Firestore writes + 1 function call
- **1000 comments/day:** ~$0.01/day = $3.60/year

Very cheap! 💰

---
**Status:** ✅ Ready to Deploy
**Command:** `firebase deploy --only functions:moderateContent`

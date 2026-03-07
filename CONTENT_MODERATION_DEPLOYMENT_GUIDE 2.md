# Content Moderation System - Deployment Guide

## ✅ Implementation Complete

All P0 fixes for the content moderation system have been successfully implemented.

---

## 📋 What Was Implemented

### 1. **CreatePostView.swift** - Client-Side Moderation Integration ✅

#### Changes Made:
- **Line 79-87**: Added moderation state objects
  ```swift
  @StateObject private var integrityTracker = ComposerIntegrityTracker()
  @StateObject private var rateLimiter = ComposerRateLimiter.shared
  @State private var showModerationNudge = false
  @State private var moderationNudgeMessage = ""
  @State private var showModerationBlockingModal = false
  @State private var blockingModerationDecision: ModerationDecision?
  ```

- **Line 857-877**: Added typing vs pasting tracking
  ```swift
  .onChange(of: postText) { oldValue, newValue in
      let addedLength = newValue.count - oldValue.count
      if addedLength > 50 {
          // Paste detected
          integrityTracker.trackPaste(text: pastedText)
      } else if addedLength > 0 {
          // Typing detected
          integrityTracker.trackTyping(addedCharacters: addedLength)
      }
      ...
  }
  ```

- **Line 1348-1362**: Added rate limiting check
  ```swift
  if rateLimiter.isRateLimited(for: .post) {
      showError(title: "Slow Down", message: "...")
      return
  }
  ```

- **Line 1476-1484**: Export real authenticity signals
  ```swift
  let signals = integrityTracker.exportAuthenticitySignals()
  print("📊 Authenticity: typed=\(signals.typedCharacters) pasted=\(signals.pastedCharacters)")
  ```

- **Line 1568-1621**: Handle all enforcement actions
  ```swift
  switch moderationResult.action {
  case .allow: ...
  case .nudgeRewrite: ... // Gentle nudge
  case .requireRevision: ... // Block with suggestions
  case .holdForReview, .reject: ... // Hard block
  case .rateLimit: ... // Server-side rate limit
  case .shadowRestrict: ... // Silent flag
  }
  ```

- **Line 1798-1800**: Track rate limiter and reset tracker
  ```swift
  rateLimiter.trackPost(category: .post)
  integrityTracker.reset()
  ```

- **Line 460-476**: Added moderation decision modal
  ```swift
  .sheet(isPresented: $showModerationBlockingModal) {
      if let decision = blockingModerationDecision {
          ModerationDecisionView(decision: decision, ...)
      }
  }
  ```

- **Line 598-607**: Added personalize nudge banner
  ```swift
  if showModerationNudge {
      PersonalizeNudgeBanner(message: moderationNudgeMessage, ...)
  }
  ```

### 2. **Existing Moderation Infrastructure** (Already Complete) ✅

These files are already production-ready and require NO changes:

- **ContentIntegrityComposer.swift** (406 lines)
  - `ComposerIntegrityTracker` - Tracks typing vs pasting
  - `ComposerRateLimiter` - Client-side rate limiting
  - `PersonalizeNudgeBanner` - Nudge UI
  - `ModerationDecisionView` - Blocking modal UI

- **ContentIntegrityPolicy.swift** (338 lines)
  - `EnforcementAction` enum (7 levels)
  - `ModerationDecision` struct
  - `EnforcementLadder` - Graduated enforcement logic
  - `ContentAllowlist` - Scripture/quote detection

- **ContentModerationService.swift** (133 lines)
  - `moderateContent()` - Calls Cloud Functions
  - `reportContent()` - User reports
  - `submitAppeal()` - Appeal blocked content

- **functions/contentModeration.js** (522 lines)
  - Parallel moderation checks (toxicity, spam, AI, duplicates)
  - Near-duplicate detection with fingerprinting
  - User risk scoring based on velocity
  - Enforcement decision engine

---

## 🚀 Deployment Steps

### Prerequisites

1. **Firebase CLI installed**
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

2. **Google Cloud APIs enabled**
   - Cloud Natural Language API (for toxicity detection)
   - Cloud Functions API
   - Firestore API

### Step 1: Deploy Cloud Functions

```bash
cd functions

# Install dependencies
npm install

# Deploy moderation function
firebase deploy --only functions:moderateContent

# Verify deployment
firebase functions:log --only moderateContent
```

**Expected output:**
```
✔  functions[moderateContent(us-central1)] Successful update operation.
Function URL (moderateContent): https://us-central1-<project>.cloudfunctions.net/moderateContent
```

### Step 2: Update Firestore Security Rules (OPTIONAL)

The existing Firestore rules at line 263-273 already handle post creation:

```javascript
allow create: if isAuthenticated()
  && request.resource.data.authorId == request.auth.uid
  && hasRequiredFields(['content', 'authorId', 'authorName', 'category'])
  && validLength(request.resource.data.content, 500)
  && request.resource.data.category in ['openTable', 'testimonies', 'prayer', 'general'];
```

**No changes needed** - moderation happens in Cloud Functions before Firestore write.

If you want to add moderation metadata validation (optional):

```javascript
// Add to line 271 in firestore.rules
&& (!request.resource.data.keys().hasAny(['moderationState'])
    || request.resource.data.moderationState in ['approved', 'pending_review'])
```

Then deploy:
```bash
firebase deploy --only firestore:rules
```

### Step 3: Build and Test the iOS App

```bash
# Build the app in Xcode
# Product -> Build (⌘+B)

# Run on simulator/device
# Product -> Run (⌘+R)
```

**Test cases:**

1. **Normal post** - Should publish immediately
2. **Large paste** - Should show nudge banner "Add your own thoughts"
3. **Toxic content** - Should block with modal
4. **Rapid posting** - Should show rate limit error after 5 posts in 5 min
5. **AI-suspected content** - Should show "Add Your Voice" modal

---

## 🧪 Testing the Moderation System

### Test 1: Toxic Content Detection
```
Post text: "I hate everyone and you all suck"
Expected: REJECT action, blocking modal
```

### Test 2: Spam Detection
```
Post text: "BUY NOW!!! CLICK HERE!!! https://spam.com https://spam2.com"
Expected: REJECT action, blocking modal
```

### Test 3: AI/Copy-Paste Detection
```
1. Copy 500 characters of formal text
2. Paste into CreatePostView
3. Click Post
Expected: NUDGE_REWRITE action, nudge banner shows
```

### Test 4: Rate Limiting
```
1. Create 6 posts within 1 minute
2. On 6th post, expect error:
   "Slow Down - You're posting quite frequently..."
```

### Test 5: Scripture Quote (Should Allow)
```
Post text: "John 3:16 - For God so loved the world..."
Expected: ALLOW action (legitimate quote)
```

---

## 📊 Monitoring

### Cloud Functions Logs

```bash
# Real-time logs
firebase functions:log --only moderateContent

# Filter by severity
firebase functions:log --only moderateContent --level ERROR
```

### Firestore Collections to Monitor

1. **moderation_events** - All moderation decisions
   ```
   {
     userId: "abc123",
     contentType: "post",
     decision: {
       action: "nudge_rewrite",
       confidence: 0.75,
       reasons: ["AI suspicion detected"]
     },
     timestamp: 2026-02-22T...
   }
   ```

2. **content_fingerprints** - Duplicate detection
   ```
   {
     userId: "abc123",
     contentType: "post",
     fingerprint: "md5hash...",
     createdAt: 2026-02-22T...
   }
   ```

3. **user_integrity_signals** - User violation history
   ```
   {
     violationCount: 2,
     lastViolation: 2026-02-22T...,
     violationTypes: ["require_revision", "nudge_rewrite"]
   }
   ```

---

## 🔍 Troubleshooting

### Issue 1: Moderation always returns "allow"

**Cause**: Cloud Function not deployed or failing

**Fix**:
```bash
firebase functions:log --only moderateContent
# Look for errors in the logs
```

### Issue 2: "Moderation service unavailable"

**Cause**: Cloud Function timeout or error

**Fix**: Check Firebase Console -> Functions -> moderateContent -> Logs

**Fail-open behavior**: Posts are allowed but flagged for review

### Issue 3: Rate limiting not working

**Cause**: `ComposerRateLimiter` not tracking posts

**Fix**: Verify line 1798-1800 in CreatePostView calls `trackPost()`

### Issue 4: Nudge banner not showing

**Cause**: `showModerationNudge` state not updating

**Fix**: Check line 1577-1582 in CreatePostView switch statement

---

## 📈 Success Metrics

Monitor these metrics to measure moderation effectiveness:

1. **Moderation decisions**
   - Allow: 90-95%
   - Nudge: 3-5%
   - Require revision: 1-2%
   - Reject: <1%

2. **User experience**
   - Average moderation latency: <500ms
   - Post creation success rate: >98%
   - User reports after moderation: <0.1%

3. **False positives**
   - Scripture quotes incorrectly flagged: 0%
   - Sermon excerpts incorrectly flagged: 0%

---

## ✅ Deployment Checklist

- [x] CreatePostView moderation integration complete
- [x] ComposerIntegrityTracker tracking typing/pasting
- [x] Rate limiting enforcement added
- [x] All enforcement actions handled (nudge, require revision, reject, etc.)
- [x] Moderation UI (banner, modal) integrated
- [x] Reset tracker after successful post
- [ ] Cloud Functions deployed (moderateContent)
- [ ] Firestore security rules updated (optional)
- [ ] App built and tested in Xcode
- [ ] Test cases passed (toxic, spam, AI, rate limit, scripture)
- [ ] Monitoring dashboards configured
- [ ] Team trained on moderation system

---

## 🎯 Next Steps

1. **Deploy Cloud Functions** (REQUIRED)
   ```bash
   cd functions && firebase deploy --only functions:moderateContent
   ```

2. **Test on simulator** (REQUIRED)
   - Run app in Xcode
   - Test all 5 test cases above
   - Verify moderation decisions appear in Firebase Console

3. **Production rollout** (RECOMMENDED)
   - Start with 10% of users (canary deployment)
   - Monitor error rates and latency
   - Gradually increase to 100%

4. **Post-deployment monitoring** (REQUIRED)
   - Watch Cloud Functions logs for errors
   - Monitor Firestore `moderation_events` collection
   - Review user reports and appeals

---

## 📝 Configuration Options

### Adjust Rate Limits

Edit `ContentIntegrityComposer.swift` line 200-206:

```swift
private let limits: [ContentCategory: Int] = [
    .post: 5,           // Change to 10 for less strict
    .comment: 10,       // Change to 20 for less strict
    .reply: 15,
    .profileBio: 3,
    .caption: 10
]
```

### Adjust AI Suspicion Thresholds

Edit `ContentIntegrityPolicy.swift` line 47-52:

```swift
var aiSuspicionThreshold: Double {
    switch self {
    case .standard: return 0.7  // Change to 0.8 for less strict
    case .strict: return 0.5    // Change to 0.6 for less strict
    }
}
```

### Adjust Paste Detection Sensitivity

Edit `CreatePostView.swift` line 863:

```swift
if addedLength > 50 {  // Change to 100 for less strict
    integrityTracker.trackPaste(text: pastedText)
}
```

---

## 🎉 Summary

**Status**: ✅ IMPLEMENTATION COMPLETE

All P0 content moderation fixes have been implemented in CreatePostView:
- ✅ Real authenticity signals (typed vs pasted)
- ✅ Rate limiting enforcement
- ✅ All enforcement actions handled (7 levels)
- ✅ Moderation UI (nudge banner + blocking modal)
- ✅ Reset tracker after successful post

**Ready for deployment** - Just need to deploy Cloud Functions and test!

---

**Questions or issues?**
- Check Firebase Console -> Functions -> Logs
- Check Xcode console for `print()` debug statements
- Review `moderation_events` collection in Firestore

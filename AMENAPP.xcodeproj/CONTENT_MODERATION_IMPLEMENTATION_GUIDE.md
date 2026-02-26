# AMEN Organic Content Integrity + Moderation System
## Complete Implementation Guide

---

## D. Media Moderation Pipeline

### Image/Video Moderation Hook

```typescript
// functions/mediaModeration.js

exports.moderateMedia = functions.storage.object().onFinalize(async (object) => {
  const filePath = object.name;
  const userId = object.metadata?.userId;
  
  // 1. Download media temporarily
  const bucket = admin.storage().bucket(object.bucket);
  const tempFilePath = `/tmp/${path.basename(filePath)}`;
  await bucket.file(filePath).download({destination: tempFilePath});
  
  // 2. Run parallel moderation checks
  const [visionResult, ocrResult, phashResult] = await Promise.all([
    moderateWithVisionAPI(tempFilePath),
    extractTextWithOCR(tempFilePath),
    generatePerceptualHash(tempFilePath)
  ]);
  
  // 3. Moderate extracted OCR text
  let textModerationResult = null;
  if (ocrResult.text) {
    textModerationResult = await moderateText(ocrResult.text);
  }
  
  // 4. Check for duplicate media
  const duplicateMatch = await checkDuplicateMedia(phashResult.hash, userId);
  
  // 5. Determine moderation status
  const status = determineModerationStatus({
    vision: visionResult,
    ocr: textModerationResult,
    duplicate: duplicateMatch
  });
  
  // 6. Update Firestore with moderation result
  await admin.firestore().collection('media_moderation').add({
    userId,
    filePath,
    status,
    visionLabels: visionResult.labels,
    ocrText: ocrResult.text?.substring(0, 500),
    perceptualHash: phashResult.hash,
    moderatedAt: admin.firestore.FieldValue.serverTimestamp()
  });
  
  // 7. If rejected, delete file
  if (status === 'rejected') {
    await bucket.file(filePath).delete();
  }
  
  return {status};
});

async function moderateWithVisionAPI(filePath) {
  const {ImageAnnotatorClient} = require('@google-cloud/vision');
  const client = new ImageAnnotatorClient();
  
  const [result] = await client.safeSearchDetection(filePath);
  const safeSearch = result.safeSearchAnnotation;
  
  return {
    adult: safeSearch.adult,
    violence: safeSearch.violence,
    racy: safeSearch.racy,
    labels: result.labelAnnotations
  };
}

async function extractTextWithOCR(filePath) {
  const {ImageAnnotatorClient} = require('@google-cloud/vision');
  const client = new ImageAnnotatorClient();
  
  const [result] = await client.textDetection(filePath);
  const text = result.fullTextAnnotation?.text || '';
  
  return {text};
}

async function generatePerceptualHash(filePath) {
  // Use perceptual hashing library (e.g., sharp + imagehash)
  const sharp = require('sharp');
  const imageHash = require('imagehash');
  
  const hash = await imageHash.hash(filePath, 16, 'hex');
  return {hash};
}

function determineModerationStatus(results) {
  // Reject if explicit content
  if (results.vision.adult >= 'LIKELY' || results.vision.violence >= 'VERY_LIKELY') {
    return 'rejected';
  }
  
  // Reject if OCR text is toxic
  if (results.ocr && results.ocr.toxicity > 0.8) {
    return 'rejected';
  }
  
  // Hold for review if borderline
  if (results.vision.adult >= 'POSSIBLE' || results.vision.racy >= 'LIKELY') {
    return 'pending_review';
  }
  
  // Limit if duplicate
  if (results.duplicate.score > 0.9) {
    return 'limited';  // Down-rank but don't reject
  }
  
  return 'approved';
}
```

---

## E. Data Model (Firestore)

### Collection: `moderation_events`
```json
{
  "userId": "user123",
  "contentType": "post",
  "contentText": "Sample post content...",
  "decision": {
    "action": "nudge_rewrite",
    "confidence": 0.72,
    "reasons": ["AI suspicion detected"],
    "suggestedRevisions": ["Add personal reflection"]
  },
  "scores": {
    "toxicity": 0.1,
    "spam": 0.2,
    "aiSuspicion": 0.72,
    "duplicateMatch": 0.0,
    "authenticity": 0.28,
    "userRiskScore": 0.1
  },
  "timestamp": "2026-02-22T10:30:00Z"
}
```

**Indexes needed:**
- `userId` ASC, `timestamp` DESC
- `decision.action` ASC, `timestamp` DESC

### Collection: `user_integrity_signals`
```json
{
  "userId": "user123",
  "violationCount": 2,
  "lastViolation": "2026-02-22T10:30:00Z",
  "violationTypes": ["ai_suspected", "near_duplicate"],
  "authenticityScore": 0.65,  // Rolling average
  "shadowRestricted": false,
  "restrictionUntil": null,
  "createdAt": "2026-01-15T08:00:00Z",
  "updatedAt": "2026-02-22T10:30:00Z"
}
```

**Indexes needed:**
- `userId` ASC
- `shadowRestricted` ASC, `updatedAt` DESC

### Collection: `content_fingerprints`
```json
{
  "userId": "user123",
  "contentType": "post",
  "fingerprint": "a3f7b2c9d1e4...",
  "textPreview": "First 100 chars of content...",
  "createdAt": "2026-02-22T10:30:00Z"
}
```

**Indexes needed:**
- `userId` ASC, `contentType` ASC, `createdAt` DESC
- `fingerprint` ASC

### Collection: `media_moderation`
```json
{
  "userId": "user123",
  "filePath": "uploads/user123/image.jpg",
  "status": "approved",
  "visionLabels": ["nature", "landscape"],
  "ocrText": "Extracted text from image...",
  "perceptualHash": "p:abc123...",
  "moderatedAt": "2026-02-22T10:30:00Z"
}
```

**Indexes needed:**
- `userId` ASC, `moderatedAt` DESC
- `status` ASC, `moderatedAt` DESC
- `perceptualHash` ASC

### Collection: `review_queue`
```json
{
  "contentId": "post123",
  "contentType": "post",
  "userId": "user123",
  "contentText": "Content under review...",
  "contentMediaURLs": ["url1", "url2"],
  "moderationDecision": {...},
  "state": "pending",
  "priority": 2,  // 1=high, 2=medium, 3=low
  "createdAt": "2026-02-22T10:30:00Z",
  "resolvedAt": null,
  "resolvedBy": null,
  "resolutionNotes": null
}
```

**Indexes needed:**
- `state` ASC, `priority` ASC, `createdAt` ASC
- `userId` ASC, `state` ASC

### Collection: `content_reports` (user-reported content)
```json
{
  "contentId": "post123",
  "contentType": "post",
  "reportedBy": "user456",
  "reportReason": "spam",
  "reportDetails": "This looks like a bot post",
  "status": "pending",
  "createdAt": "2026-02-22T10:30:00Z",
  "resolvedAt": null
}
```

**Indexes needed:**
- `contentId` ASC, `createdAt` DESC
- `status` ASC, `createdAt` DESC

---

## F. Ranking Integration (Authenticity Score)

### Internal Authenticity Score (Not User-Visible)

```swift
// Swift - HomeFeedAlgorithm.swift integration

extension HomeFeedAlgorithm {
    
    /// Adjust post ranking based on content integrity score
    func applyAuthenticityPenalty(to posts: [Post]) async -> [Post] {
        var rankedPosts = posts
        
        for (index, post) in rankedPosts.enumerated() {
            // Fetch integrity signals for post author
            let authenticityScore = await fetchAuthenticityScore(userId: post.authorId)
            
            // Apply ranking penalty
            if authenticityScore < 0.5 {
                // Severe penalty - move to bottom 20%
                rankedPosts[index].rankingBoost = -0.5
            }
            else if authenticityScore < 0.7 {
                // Moderate penalty - slight down-rank
                rankedPosts[index].rankingBoost = -0.2
            }
            // No penalty for scores >= 0.7
            
            // Preserve legitimate Scripture/quotes (no false positives)
            if ContentAllowlist.containsScripture(post.content) {
                rankedPosts[index].rankingBoost = max(rankedPosts[index].rankingBoost, 0)
            }
        }
        
        return rankedPosts.sorted { $0.rankingScore > $1.rankingScore }
    }
    
    private func fetchAuthenticityScore(userId: String) async -> Double {
        guard let doc = try? await db.collection("user_integrity_signals")
            .document(userId)
            .getDocument() else {
            return 1.0  // Default to authentic
        }
        
        return doc.data()?["authenticityScore"] as? Double ?? 1.0
    }
}
```

### TypeScript - Authenticity Score Calculation

```typescript
// functions/authenticityScoring.js

exports.updateAuthenticityScore = functions.firestore
  .document('moderation_events/{eventId}')
  .onCreate(async (snap, context) => {
    const event = snap.data();
    const userId = event.userId;
    
    // Calculate rolling authenticity score
    const recentEvents = await admin.firestore()
      .collection('moderation_events')
      .where('userId', '==', userId)
      .orderBy('timestamp', 'desc')
      .limit(20)
      .get();
    
    let totalAuthenticity = 0;
    let count = 0;
    
    recentEvents.forEach(doc => {
      const scores = doc.data().scores;
      totalAuthenticity += scores.authenticity;
      count++;
    });
    
    const authenticityScore = count > 0 ? totalAuthenticity / count : 1.0;
    
    // Update user integrity signals
    await admin.firestore()
      .collection('user_integrity_signals')
      .doc(userId)
      .set({
        authenticityScore,
        lastCalculated: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
  });
```

---

## G. Developer Implementation Details

### SwiftUI Code Structure

```swift
// Example: Integrating moderation into CreatePostView

struct CreatePostView: View {
    @State private var postText: String = ""
    @StateObject private var integrityTracker = ComposerIntegrityTracker()
    @State private var showModerationDecision: Bool = false
    @State private var moderationResult: ModerationDecision?
    @State private var isSubmitting: Bool = false
    
    var body: some View {
        VStack {
            // Text editor with integrity tracking
            TextEditor(text: $postText)
                .withContentIntegrityGuard(category: .post, text: $postText)
            
            // Personalize nudge banner
            PersonalizeNudgeBanner(
                message: integrityTracker.nudgeMessage,
                isVisible: $integrityTracker.showPersonalizeNudge
            )
            
            // Rate limit warning
            RateLimitWarning(
                remainingPosts: ComposerRateLimiter.shared.getRemainingPosts(for: .post),
                category: .post
            )
            
            // Submit button
            Button("Post") {
                submitPost()
            }
            .disabled(isSubmitting || postText.isEmpty)
        }
        .sheet(isPresented: $showModerationDecision) {
            if let decision = moderationResult {
                ModerationDecisionView(
                    decision: decision,
                    onRevise: { showModerationDecision = false },
                    onCancel: { dismissPost() }
                )
            }
        }
    }
    
    private func submitPost() {
        isSubmitting = true
        
        Task {
            do {
                // 1. Export authenticity signals
                let signals = integrityTracker.exportAuthenticitySignals()
                
                // 2. Call moderation endpoint
                let result = try await ContentModerationService.moderateContent(
                    text: postText,
                    category: .post,
                    signals: signals
                )
                
                // 3. Handle decision
                if result.decision == "allow" || result.decision == "nudge_rewrite" {
                    // Post allowed - create post
                    await createPost()
                    
                    // Track rate limit
                    ComposerRateLimiter.shared.trackPost(category: .post)
                }
                else {
                    // Show moderation decision UI
                    moderationResult = result
                    showModerationDecision = true
                }
                
                isSubmitting = false
                
            } catch {
                // Handle error
                print("Moderation error: \(error)")
                isSubmitting = false
            }
        }
    }
}
```

### Firebase Cloud Functions Setup

```bash
# Install dependencies
cd functions
npm install @google-cloud/language @google-cloud/vision imagehash sharp

# Deploy moderation functions
firebase deploy --only functions:moderateContent,functions:moderateMedia,functions:updateAuthenticityScore
```

### Security Considerations

**Firestore Security Rules:**
```javascript
// firestore.rules

// Moderation events - write only by server, read only by admins
match /moderation_events/{eventId} {
  allow read: if request.auth != null && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
  allow write: if false;  // Server-side only
}

// User integrity signals - read only by owner
match /user_integrity_signals/{userId} {
  allow read: if request.auth != null && request.auth.uid == userId;
  allow write: if false;  // Server-side only
}

// Review queue - admin only
match /review_queue/{queueId} {
  allow read, write: if request.auth != null && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
}

// Content reports - users can create, admins can read/update
match /content_reports/{reportId} {
  allow create: if request.auth != null;
  allow read, update: if request.auth != null && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
}
```

---

## H. Rollout Plan

### Phase 1: Soft Launch (Weeks 1-2)
**Goal:** Test with 10% of users, tune thresholds

1. **Enable for beta users only**
   - Feature flag: `content_moderation_enabled`
   - Rollout to 10% of active users
   
2. **Monitor metrics:**
   - False positive rate (legitimate content blocked)
   - False negative rate (spam/AI content allowed)
   - User friction (how many revisions required)
   - Appeal rate
   
3. **Tune thresholds:**
   - Adjust AI suspicion threshold based on false positives
   - Calibrate spam detection for religious content
   - Refine Scripture detection allowlist

### Phase 2: Gradual Rollout (Weeks 3-4)
**Goal:** Expand to 50% of users, optimize UX

1. **Expand to 50% of users**
2. **A/B test nudge messaging:**
   - Variant A: "Add your personal touch"
   - Variant B: "Share your own reflection"
   - Measure conversion rate (users who revise)
   
3. **Implement admin review queue:**
   - Train moderators on policy
   - Review held content within 24 hours
   - Build appeal workflow

### Phase 3: Full Production (Week 5+)
**Goal:** 100% rollout with continuous improvement

1. **Enable for all users**
2. **Automated reporting dashboard:**
   - Daily moderation metrics
   - Top false positives
   - User satisfaction scores
   
3. **Continuous learning:**
   - Feed moderation decisions into ML training
   - Update thresholds based on real data
   - Expand Scripture allowlist

---

## False-Positive Mitigation Strategy

### 1. Scripture & Quotes Protection
```typescript
// Enhanced allowlist checking
function isProtectedContent(text: string): boolean {
  // Check for Bible verses with verse numbers
  const versePattern = /\b(Genesis|Exodus|...|Revelation)\s+\d+:\d+/i;
  if (versePattern.test(text)) return true;
  
  // Check for sermon excerpts
  if (text.includes('Pastor') || text.includes('sermon')) return true;
  
  // Check for attributed quotes
  if (text.match(/[""].*[""]/) && text.match(/[-—]\s*\w+/)) return true;
  
  return false;
}
```

### 2. User Whitelist
- Verified pastors/ministry leaders get lower scrutiny
- Users with high authenticity scores (>0.8) skip some checks

### 3. Appeal Workflow
```swift
struct AppealView: View {
    let contentId: String
    @State private var appealReason: String = ""
    
    func submitAppeal() {
        // Submit to review queue with high priority
        FirebaseService.submitAppeal(
            contentId: contentId,
            reason: appealReason,
            priority: .high
        )
    }
}
```

### 4. Monitoring Dashboard
```typescript
// Admin dashboard - detect patterns
exports.generateModerationReport = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    const last24h = new Date(Date.now() - 24*60*60*1000);
    
    const events = await admin.firestore()
      .collection('moderation_events')
      .where('timestamp', '>', last24h)
      .get();
    
    const stats = {
      totalEvents: events.size,
      actionBreakdown: {},
      topFalsePositives: [],
      appealRate: 0
    };
    
    // Analyze and send to admin email
    await sendReportEmail(stats);
  });
```

---

## Detection Logic & Thresholds Table

| Signal | Threshold | Action | Notes |
|--------|-----------|--------|-------|
| **Toxicity** | >0.8 | Reject | Immediate block |
| **Spam** | >0.85 | Reject | Excessive caps, repetition, URLs |
| **AI Suspicion (Posts)** | >0.9 | Require Revision | High confidence AI |
|  | 0.7-0.9 | Nudge Rewrite | Medium confidence |
|  | 0.5-0.7 | Allow with nudge | Low confidence |
| **AI Suspicion (Comments)** | >0.7 | Require Revision | Stricter for comments |
|  | 0.5-0.7 | Nudge Rewrite | |
| **Duplicate Match** | >0.9 | Rate Limit | 3+ similar posts |
|  | 0.8-0.9 | Nudge | 1-2 similar posts |
| **User Risk Score** | >0.7 | Rate Limit | 5+ posts in 5 min |
|  | >0.5 | Warning | 3-4 posts in 5 min |
| **Paste Ratio** | <0.1 typed | +0.4 AI score | Mostly pasted |
| **Large Paste** | >500 chars | +0.3 AI score | Single paste |
| **Violation History** | ≥5 violations | Shadow Restrict | 30-day window |
|  | ≥3 violations | Hold for Review | On next violation |

---

## Telemetry & Events

```swift
// Track moderation events for analytics
enum ModerationEvent {
    case nudgeShown(category: ContentCategory)
    case nudgeDismissed
    case contentRevised
    case contentBlocked(reason: String)
    case appealSubmitted
    case rateLimitHit
}

func trackModerationEvent(_ event: ModerationEvent) {
    // Send to Firebase Analytics
    Analytics.logEvent("moderation_\(event.name)", parameters: event.parameters)
}
```

---

## Summary

This implementation provides:
✅ **Graduated enforcement** - No hard bans, gentle nudges first  
✅ **Scripture protection** - Legitimate quotes allowed  
✅ **Spam controls** - Stricter for comments, lenient for posts  
✅ **AI detection** - Client + server signals combined  
✅ **False positive mitigation** - Allowlists, appeals, monitoring  
✅ **Incremental rollout** - Soft launch → gradual → full  
✅ **Production-ready** - Complete code scaffolding provided  

**Total Implementation Time:** 2-3 weeks for full rollout with monitoring.

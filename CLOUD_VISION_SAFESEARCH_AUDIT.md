# Cloud Vision API SafeSearch Audit - Feb 25, 2026

## Summary
**Status:** ❌ **NOT IMPLEMENTED**

Cloud Vision API SafeSearch Detection for image moderation is **NOT currently implemented** in AMEN. This is a **P0 critical gap** for a faith-based social platform.

---

## What's Currently Implemented

### ✅ Text Content Moderation (Vertex AI)
**Location:** `functions/aiModeration.js`
- Uses Vertex AI (Gemini 1.5 Flash) for text analysis
- Checks posts, comments, prayers for:
  - Extreme profanity
  - Hate speech
  - Sexual content
  - Spam/scams
  - Threats
  - Mockery of faith
- **Works well for text, but does NOT handle images**

### ✅ Photo Insights (Label Detection Only)
**Location:** `PhotoInsightsService.swift`
- Uses Cloud Vision API for **LABEL_DETECTION** only (line 158)
- Generates profile photo badges like "🏔️ Mountain Enthusiast", "⛪ Church-going"
- **Does NOT use SafeSearch or moderation features**

**Current Vision API Call:**
```swift
"features": [
    [
        "type": "LABEL_DETECTION",
        "maxResults": 10
    ]
]
```

**Missing:** No `SAFE_SEARCH_DETECTION` feature type

---

## What's Missing: SafeSearch Detection

### Critical Gap
AMEN has **ZERO image safety moderation** currently. Users can upload:
- ❌ Adult/explicit images
- ❌ Violent imagery
- ❌ Racy/inappropriate photos
- ❌ Medical/graphic content
- ❌ Spoof/fake imagery

### Where Images Are Uploaded
1. **Profile Pictures** - Visible across entire app
2. **Post Images** - In OpenTable, Testimonies, Prayer feeds
3. **Church Notes** - May include sermon slides/photos
4. **Messages** - Direct message photos

**All of these upload paths are UNMODERATED for visual content.**

---

## How SafeSearch Detection Works

### API Response Format
```json
{
  "responses": [
    {
      "safeSearchAnnotation": {
        "adult": "VERY_UNLIKELY",
        "spoof": "UNLIKELY",
        "medical": "POSSIBLE",
        "violence": "UNLIKELY",
        "racy": "VERY_UNLIKELY"
      }
    }
  ]
}
```

### Likelihood Levels
- `VERY_UNLIKELY` - Safe (score: 1)
- `UNLIKELY` - Probably safe (score: 2)
- `POSSIBLE` - Borderline (score: 3) ⚠️
- `LIKELY` - Probably unsafe (score: 4) 🚫
- `VERY_LIKELY` - Unsafe (score: 5) 🚫

### Recommended Policy Thresholds

#### For AMEN (Faith Platform)
**Strict Standards Required:**

```javascript
// Block immediately (no upload)
if (safeSearch.adult >= 'POSSIBLE' ||       // Block at 3+
    safeSearch.violence >= 'LIKELY' ||      // Block at 4+
    safeSearch.racy >= 'POSSIBLE') {        // Block at 3+
  return { action: 'BLOCK', reason: 'Inappropriate content' };
}

// Send to review queue
if (safeSearch.medical >= 'LIKELY' ||       // Review at 4+
    safeSearch.spoof >= 'LIKELY') {         // Review at 4+
  return { action: 'REVIEW', reason: 'Requires moderation' };
}

// Allow
return { action: 'APPROVE' };
```

---

## Implementation Plan

### Phase 1: Add SafeSearch to Profile Pictures (P0)
**Urgency:** Critical - Highest visibility

**File:** `PhotoInsightsService.swift`

**Changes Needed:**
1. Add `SAFE_SEARCH_DETECTION` to Vision API request
2. Parse `safeSearchAnnotation` from response
3. Block upload if thresholds exceeded
4. Show user-friendly error message

**Code Addition:**
```swift
// In detectLabels() function, update requestBody:
"features": [
    [
        "type": "LABEL_DETECTION",
        "maxResults": 10
    ],
    [
        "type": "SAFE_SEARCH_DETECTION"  // ✅ NEW
    ]
]

// Parse SafeSearch in response:
if let safeSearch = firstResponse["safeSearchAnnotation"] as? [String: String] {
    let adult = safeSearch["adult"] ?? "UNKNOWN"
    let racy = safeSearch["racy"] ?? "UNKNOWN"
    let violence = safeSearch["violence"] ?? "UNKNOWN"

    // Check thresholds
    if adult == "POSSIBLE" || adult == "LIKELY" || adult == "VERY_LIKELY" ||
       racy == "POSSIBLE" || racy == "LIKELY" || racy == "VERY_LIKELY" ||
       violence == "LIKELY" || violence == "VERY_LIKELY" {
        throw PhotoInsightError.unsafeContent
    }
}
```

### Phase 2: Add SafeSearch to Post Images (P0)
**Urgency:** Critical - User-generated content

**New File Needed:** `ImageModerationService.swift`

**Location:** Before upload in `CreatePostView.swift`

**Flow:**
1. User selects image → uploads to Storage
2. Get Storage URL → call Vision SafeSearch
3. If blocked → delete from Storage, show error
4. If approved → continue creating post
5. If review → flag for manual moderation, allow post temporarily

**Integration Point:** Line ~450 in `CreatePostView.swift` after image upload

### Phase 3: Cloud Function for Async Moderation (P1)
**Urgency:** High - Scales better

**New File:** `functions/imageMod eration.js`

**Trigger:** `onFinalize()` when image uploaded to Storage

**Flow:**
```javascript
exports.moderateUploadedImage = onObjectFinalized(async (event) => {
  const filePath = event.data.name;

  // Call Vision API SafeSearch
  const [result] = await visionClient.safeSearchDetection(
    `gs://amen-5e359.appspot.com/${filePath}`
  );

  const safeSearch = result.safeSearchAnnotation;

  if (isUnsafe(safeSearch)) {
    // Delete file
    await storage.bucket().file(filePath).delete();

    // Notify user
    await notifyUserOfRejection(userId, 'inappropriate_content');

    // Log for admin review
    await db.collection('moderatorAlerts').add({
      type: 'image_rejected',
      userId, filePath, safeSearch,
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });
  }
});
```

### Phase 4: Message Image Moderation (P1)
**Location:** `UnifiedChatView.swift`

**Same flow as Phase 2 but for message images**

---

## Cost Estimate

### Cloud Vision API Pricing
- **First 1,000 requests/month:** FREE
- **1,001 - 5,000,000:** $1.50 per 1,000 images
- **5,000,001+:** Volume discount

### AMEN Usage Estimate (Conservative)
Assuming 1,000 active users:
- Profile picture uploads: ~50/day = 1,500/month
- Post images: ~200/day = 6,000/month
- Message images: ~100/day = 3,000/month
- **Total:** ~10,500 images/month

**Monthly Cost:**
- First 1,000: $0
- Remaining 9,500: 9.5 × $1.50 = **$14.25/month**

### ROI
- **Cost:** $14.25/month
- **Benefit:** Prevents 100% of inappropriate visual content
- **Risk if NOT implemented:** Platform reputation damage, user safety concerns, potential legal issues

**Verdict:** Absolutely worth it for trust/safety

---

## Integration with Existing Systems

### Works With:
1. **AdvancedModerationService.swift** - Add visual content scores
2. **ContentModerationService.swift** - Unified moderation pipeline
3. **functions/aiModeration.js** - Coordinate text + image moderation

### New Collections Needed:
```
moderationRequests/{requestId}
  - contentType: "image"
  - imageURL: string
  - userId: string
  - uploadContext: "profile" | "post" | "message"
  - createdAt: timestamp

moderationResults/{requestId}
  - safeSearchScores: {
      adult: string,
      violence: string,
      racy: string,
      medical: string,
      spoof: string
    }
  - action: "approve" | "block" | "review"
  - reason: string
  - processedAt: timestamp
```

---

## Firestore Rules Update Needed

Add to `firestore.rules`:

```javascript
// Image moderation results
match /imageModerationResults/{resultId} {
  // Users can read their own results
  allow read: if request.auth != null &&
                 resource.data.userId == request.auth.uid;

  // Only Cloud Functions can write
  allow write: if false;
}

// Moderator alerts (admin only)
match /moderatorAlerts/{alertId} {
  allow read: if request.auth != null &&
                 get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
  allow write: if false; // Cloud Functions only
}
```

---

## Testing Checklist

### Before Production
- [ ] Test with clean profile picture → should approve
- [ ] Test with inappropriate image → should block with clear error
- [ ] Test with borderline image → should send to review queue
- [ ] Test Cloud Function triggers correctly on Storage upload
- [ ] Verify deleted images are actually removed from Storage
- [ ] Test user notification when image rejected
- [ ] Verify moderator alerts appear in admin dashboard
- [ ] Load test: 100 images uploaded simultaneously
- [ ] Check Vision API quota limits in GCP Console
- [ ] Set up billing alerts at $20/month threshold

---

## Deployment Steps

### 1. Update package.json
```bash
cd functions
npm install @google-cloud/vision --save
```

### 2. Enable Vision API in GCP Console
```bash
gcloud services enable vision.googleapis.com --project=amen-5e359
```

### 3. Update Swift Services
- Modify `PhotoInsightsService.swift`
- Create `ImageModerationService.swift`
- Update `CreatePostView.swift`

### 4. Deploy Cloud Functions
```bash
firebase deploy --only functions:moderateUploadedImage
```

### 5. Update Firestore Rules
```bash
firebase deploy --only firestore:rules
```

### 6. Monitor First Week
- Check Cloud Console for Vision API usage
- Review moderation alerts
- Gather user feedback on false positives

---

## Current Risk Level

### Without SafeSearch: 🔴 **HIGH RISK**
- **User Safety:** Users could be exposed to inappropriate content
- **Platform Reputation:** Faith platform cannot afford moderation failures
- **Legal Compliance:** Potential issues with content liability
- **Community Trust:** Core value proposition at risk

### Mitigation: ✅ **Implement Immediately**
This should be a **P0 fix before public launch**.

---

## References

- [Cloud Vision SafeSearch Docs](https://cloud.google.com/vision/docs/detecting-safe-search)
- [Pricing](https://cloud.google.com/vision/pricing)
- Current text moderation: `functions/aiModeration.js`
- Current photo service: `PhotoInsightsService.swift`

---

**Recommendation:** Implement Phase 1 & 2 (profile + post images) **this week** before any public beta or launch.

**Estimated Dev Time:**
- Phase 1 (Profile Pictures): 4-6 hours
- Phase 2 (Post Images): 6-8 hours
- Phase 3 (Cloud Function): 4-6 hours
- Phase 4 (Messages): 3-4 hours
- Testing & refinement: 4-6 hours

**Total:** 21-30 hours (3-4 days)

---

**Status:** ❌ **NOT IMPLEMENTED - CRITICAL GAP**
**Next Action:** Schedule implementation sprint this week
**Owner:** Development team
**Priority:** P0 (Must-have before launch)

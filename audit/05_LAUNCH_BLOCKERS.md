# Top 3 Launch-Blocking AI Findings

**Agent:** Agent 5 — AI Features Auditor  
**Severity:** P0 (CRITICAL)  
**Confidence:** HIGH  

---

## Finding 1: GUARDIAN Moderation Missing on Posts (Main Feed)

**Status:** NOT IMPLEMENTED | **Risk:** CRITICAL  

### What's Missing
The main feed displays user posts without any content moderation. The GUARDIAN moderation system is currently **only implemented for communal channels** (`channels/{id}/messages/{id}`), not for the primary feed.

### Evidence
- **File:** `cloud-functions/guardian.ts`
- **Trigger:** Only fires on `channels/{channelId}/messages/{messageId}` creation
- **Missing:** No Firestore trigger for `posts/{postId}` or equivalent posts collection
- **Impact:** Posts containing hate speech, harassment, or harmful content are delivered to the feed with zero review

### What Needs to Happen
1. Add Firestore `onCreate` trigger on posts collection
2. Call GUARDIAN classifier with post content + metadata
3. Route decisions to moderation queue (block, escalate, allow_with_support)
4. Mark posts with decision flags in Firestore (`isDelivered`, `isEscalated`)

### Fix Effort
**2–3 days** (boilerplate trigger + routing logic, covered by existing GUARDIAN classifier)

### Why It Blocks Launch
- Posts are the primary user-generated content surface
- Without moderation, the platform could host hateful/harmful content
- Regulatory and reputational risk

---

## Finding 2: GUARDIAN Moderation Missing on Prayer Requests

**Status:** NOT IMPLEMENTED | **Risk:** CRITICAL  

### What's Missing
Prayer requests are a sensitive surface where users share struggles, pain, and crises. There is **no moderation trigger** for prayers or prayer requests.

### Evidence
- **File:** `DailyVerseGenkitService.swift` references prayer context, but no corresponding moderation
- **Missing:** No Firestore trigger for `prayers/{prayerId}` or `prayerRequests/{requestId}`
- **Crisis Content Not Detected:** No automated detection of self-harm, suicidal ideation, or abuse disclosures
- **Impact:** Vulnerable users' distress signals reach the community without triggering support resource escalation

### What Needs to Happen
1. Identify prayer collection schema in Firestore
2. Add `onCreate` trigger for prayers/prayer requests
3. Call GUARDIAN with crisis detection scoring (self-harm keywords, suicidal language, abuse disclosures)
4. On crisis signals: route to support resources, escalate to moderators, never silence the user
5. On other violations: apply standard moderation (block, escalate)

### Fix Effort
**2–3 days** (trigger + routing logic; can reuse GUARDIAN classifier + crisis keyword list from `bereanChatProxyStream.ts`)

### Why It Blocks Launch
- Prayer requests are a high-trust surface
- Crisis detection is a legal/ethical obligation
- Missing this creates liability and undermines user trust

---

## Finding 3: ARISE/OUTPOUR (Short-form Video) Unimplemented

**Status:** DEAD/STUB | **Risk:** CRITICAL  

### What's Missing
No video backend exists. No iOS video player. No upload flow. No feed/recommendation algorithm.

### Evidence
- **Search Results:** No `*ARISE*`, `*OUTPOUR*`, or `*shortFormVideo*` files in main codebase
- **Missing Components:**
  - ❌ No `AVPlayer` or `VideoPlayer` implementation
  - ❌ No Firebase Storage upload flow
  - ❌ No video transcoding backend
  - ❌ No feed algorithm for video ranking/discovery
  - ❌ No analytics for watch time, engagement
- **UI Exists:** Marketing/design docs may reference the feature, but codebase is empty

### What Needs to Happen
**Option A: Remove the feature**
- Remove video-related UI, marketing claims, and feature flags
- Effort: 1 day

**Option B: Implement full pipeline**
1. iOS video player (AVPlayer + UI controls)
2. Upload flow (file picker, compression, Firebase Storage)
3. Transcoding backend (Firebase Functions or Cloud Run)
4. Feed integration (video collection in Firestore)
5. Recommendation algorithm (semantic or engagement-based)
6. Analytics (Crashlytics or custom logging)
7. Effort: **2–3 weeks**

### Why It Blocks Launch
- If video is promised to users/investors, shipping without it breaks trust
- If code exists but is unplugged, it creates a confusing broken experience
- Feature parity must be clear: ship the feature fully or remove it

---

## Remediation Roadmap

| Finding | Effort | Priority | Owner | Week |
|---------|--------|----------|-------|------|
| GUARDIAN on Posts | 2–3 days | P0 | Backend (TBD) | Week 1 |
| GUARDIAN on Prayers | 2–3 days | P0 | Backend (TBD) | Week 1 |
| ARISE/OUTPOUR (remove or ship) | 1 day (remove) or 2–3 weeks (ship) | P0 | Product/Eng Lead | Week 1 decision |

**Critical Path:** All three must be resolved before launch.  
**Estimated Total Effort:** 5–8 days for GUARDIAN fixes + decision on video.

---

## Confidence & Risk Assessment

| Finding | Confidence | Can Block Launch |
|---------|------------|------------------|
| GUARDIAN Posts | HIGH | YES — Moderation gap in primary surface |
| GUARDIAN Prayers | HIGH | YES — Safety/crisis liability |
| ARISE/OUTPOUR | HIGH | YES — Unfinished feature commitment |

All findings are **high confidence** based on direct code inspection of Firestore triggers, Cloud Functions, and iOS codebase.


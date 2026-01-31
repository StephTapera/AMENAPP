# Onboarding Testing Guide

## 🧪 Quick Test Scenarios

This guide helps you test all the new onboarding features quickly and thoroughly.

---

## ✅ **Pre-Test Checklist**

Before testing, ensure:
- [ ] Firebase project is configured
- [ ] `referralCodes` collection exists (with at least one test code)
- [ ] Firestore Security Rules are updated
- [ ] App builds successfully
- [ ] Test device has internet connection

---

## 🎯 **Test Scenario 1: Happy Path (Complete Flow)**

**Goal:** Complete entire onboarding successfully

### Steps:
1. Sign up with new account
2. Page 1 (Welcome): Wait for name to type, tap "Continue"
3. Page 2 (Values): Check "I understand and agree", tap "Continue"
4. Page 3 (Photo): Tap "Choose Photo", select image, tap "Continue"
5. Page 4 (Features): Read features, tap "Continue"
6. Page 5 (Interests): Select 3+ interests, tap "Continue"
7. Page 6 (Your Pace): Select time limit, toggle notifications, tap "Continue"
8. Page 7 (Goals): Select 2+ goals, tap "Continue"
9. Page 8 (Privacy): Check "I understand...", tap "Continue"
10. Page 9 (Prayer): Select prayer time, tap "Continue"
11. Page 10 (Referral): Enter "TEST123", tap "Continue"
12. Page 11 (Contacts): Tap "Find Friends" (grant/deny permission), tap "Continue"
13. Page 12 (Feedback): Rate 5 stars, add feedback, tap "Get Started"
14. Wait for "Saving..." overlay
15. Verify main app loads

### Expected Results:
✅ All pages animate smoothly  
✅ No crashes or errors  
✅ Saving overlay shows  
✅ Main app opens after completion  
✅ User profile saved to Firestore  

### Firestore Verification:
Check `users/{userId}` document has:
```javascript
{
  interests: [...],
  goals: [...],
  preferredPrayerTime: "Morning",
  profileImageURL: "https://...",
  referredBy: "referrer_id",
  referralCode: "TEST123",
  contactsPermissionGranted: true,
  onboardingRating: 5,
  onboardingFeedback: "...",
  hasCompletedOnboarding: true
}
```

---

## 🚨 **Test Scenario 2: Error Handling (Network Failure)**

**Goal:** Verify retry logic works

### Steps:
1. Complete onboarding to page 12
2. **Enable Airplane Mode** on device
3. Rate 4 stars, tap "Get Started"
4. Observe "Saving..." overlay
5. Wait for retry attempts (should take ~3 seconds)
6. Error dialog should appear
7. **Disable Airplane Mode**
8. Tap "Try Again" in dialog
9. Saving should succeed

### Expected Results:
✅ App shows "Saving..." overlay  
✅ After 3 retry attempts, error dialog appears  
✅ Error message is user-friendly  
✅ "Try Again" button re-attempts save  
✅ Second attempt succeeds with network restored  
✅ User data not lost  

### Console Output Should Show:
```
💾 Attempt 1/3 to save onboarding data...
⚠️ Attempt 1 failed: [network error]
💾 Attempt 2/3 to save onboarding data...
⚠️ Attempt 2 failed: [network error]
💾 Attempt 3/3 to save onboarding data...
⚠️ Attempt 3 failed: [network error]
❌ Failed to save onboarding data after retries
```

---

## ⏭️ **Test Scenario 3: Skip Everything**

**Goal:** Verify users can skip optional pages

### Steps:
1. Sign up with new account
2. Page 1 (Welcome): Tap "Continue"
3. Page 2 (Values): Check box, tap "Continue"
4. Page 3-11: Tap "Skip" button (top right)
5. Page 12 (Feedback): Tap "Get Started" (no rating)
6. Verify app loads

### Expected Results:
✅ Skip button visible on pages 3-11  
✅ Required pages (1, 2, 8) cannot be skipped  
✅ App loads successfully with minimal data  
✅ User profile created with defaults  

### Firestore Verification:
```javascript
{
  interests: [],              // Empty
  goals: [],                  // Empty
  preferredPrayerTime: "Morning", // Default
  profileImageURL: null,      // No photo
  hasCompletedOnboarding: true
}
```

---

## 🎁 **Test Scenario 4: Referral Code Validation**

**Goal:** Test referral code edge cases

### Setup:
Create test codes in Firestore:
- `VALID123` (userId: "test_user_1")
- `EXPIRED99` (userId: "test_user_2", expiresAt: past date)
- `MAXED789` (userId: "test_user_3", maxUses: 1, currentUses: 1)

### Test Cases:

#### A. Valid Code
**Steps:** Enter "VALID123" → tap Continue  
**Expected:** ✅ Green checkmark, "Referral code applied!"  

#### B. Invalid Code  
**Steps:** Enter "FAKE1234" → tap Continue  
**Expected:** ❌ Red error, "Invalid referral code"  

#### C. Own Code
**Steps:** Sign in as test_user_1 → Enter "VALID123"  
**Expected:** ❌ "Cannot use your own referral code"  

#### D. Empty Code
**Steps:** Leave field empty → tap Continue  
**Expected:** ✅ No error, continues normally (optional field)  

#### E. Expired Code (if implemented)
**Steps:** Enter "EXPIRED99"  
**Expected:** ❌ "This code has expired"  

#### F. Max Uses Reached (if implemented)
**Steps:** Enter "MAXED789"  
**Expected:** ❌ "Code has reached maximum uses"  

---

## 👥 **Test Scenario 5: Contact Permissions**

**Goal:** Test contact permission flow

### Test A: Grant Permission
**Steps:**
1. Navigate to page 11 (Find Friends)
2. Tap "Find Friends"
3. **Grant permission** in iOS dialog
4. Observe UI update

**Expected:**
✅ iOS permission dialog appears  
✅ On grant: Green checkmark shows  
✅ Button text changes to "Contacts access granted!"  
✅ Success haptic feedback  

### Test B: Deny Permission
**Steps:**
1. Navigate to page 11
2. Tap "Find Friends"  
3. **Deny permission** in iOS dialog
4. Observe UI

**Expected:**
✅ iOS permission dialog appears  
✅ On deny: No error shown (graceful)  
✅ Button remains "Find Friends"  
✅ Can still continue onboarding  

### Test C: Already Granted
**Steps:**
1. Grant contacts permission once
2. Sign out and sign up with new account
3. Navigate to page 11

**Expected:**
✅ Permission already granted (iOS remembers)  
✅ Shows "Contacts access granted!" immediately  

---

## ⭐ **Test Scenario 6: Feedback Collection**

**Goal:** Test feedback UI and data saving

### Test Cases:

#### A. Full Feedback
**Steps:**
1. Navigate to page 12
2. Tap 5 stars
3. Enter text feedback: "Great experience!"
4. Tap "Get Started"

**Expected:**
✅ Stars animate on tap  
✅ Selected stars are yellow  
✅ Text saved  
✅ Feedback saved to Firestore  

**Firestore Check:**
```javascript
// Collection: onboardingFeedback
{
  userId: "...",
  rating: 5,
  feedback: "Great experience!",
  timestamp: ...,
  interests: [...],
  goals: [...]
}
```

#### B. Rating Only (No Text)
**Steps:**
1. Navigate to page 12
2. Tap 3 stars
3. Leave text empty
4. Tap "Get Started"

**Expected:**
✅ Rating saved  
✅ Feedback field empty (allowed)  
✅ Continues successfully  

#### C. Skip Feedback
**Steps:**
1. Navigate to page 12
2. Don't tap stars
3. Tap "Get Started"

**Expected:**
✅ Can continue without feedback  
✅ Rating = 0 in database (or not saved)  

---

## 🎨 **Test Scenario 7: Personalized Recommendations**

**Goal:** Verify recommendation algorithm

### Test Matrix:

| Interests Selected | Goals Selected | Expected Recommendations |
|-------------------|----------------|-------------------------|
| AI & Faith | Grow in Faith | "Join #OPENTABLE", "Resources Library" |
| Prayer, Worship | Consistent Prayer | "Explore Prayer Circles", "Prayer reminders" |
| Bible Study | Daily Bible Reading | "Ask Berean AI", "Set up reminders" |
| None | None | Default: "Explore Prayer", "#OPENTABLE", "Berean AI" |

### Steps:
1. Complete onboarding with specific interests/goals
2. Navigate to page 12 (Feedback)
3. Observe recommendations

**Expected:**
✅ Shows 4 recommendations  
✅ Recommendations match interests/goals  
✅ Emojis display correctly  
✅ Text is readable  

---

## 📱 **Device-Specific Tests**

### iPhone SE (Small Screen)
- [ ] All text is readable
- [ ] Buttons are tappable (not too small)
- [ ] No content cut off
- [ ] Keyboard doesn't hide inputs

### iPhone Pro Max (Large Screen)
- [ ] Content centered properly
- [ ] No excessive white space
- [ ] Images scale correctly

### iPad
- [ ] Layout adapts to larger screen
- [ ] Text size appropriate
- [ ] Touch targets not too small

---

## ♿ **Accessibility Tests**

### VoiceOver
1. Enable VoiceOver
2. Navigate through onboarding
3. Verify all buttons are labeled
4. Check that content reads in logical order

### Dynamic Type
1. Settings → Display → Text Size → Largest
2. Open app
3. Verify all text scales
4. No text truncation

### Dark Mode
1. Enable Dark Mode
2. Complete onboarding
3. Check contrast ratios
4. Verify colors are legible

---

## 🐛 **Known Issues to Test**

### Issue #1: Image Upload Timeout
**Test:** Upload large (>10MB) photo  
**Expected Behavior:** Should compress before upload  
**Current Status:** May timeout  

### Issue #2: Rapid Page Navigation
**Test:** Quickly swipe through pages  
**Expected:** Animations smooth  
**Potential Issue:** State updates lag  

### Issue #3: Background State
**Test:** 
1. Start onboarding
2. Background app (home button)
3. Wait 1 minute
4. Return to app

**Expected:** Resume where left off  
**Potential Issue:** State reset  

---

## 📊 **Performance Tests**

### Memory Usage
- [ ] Monitor memory during onboarding
- [ ] Should stay under 200MB
- [ ] No memory leaks

### Animation Performance
- [ ] 60fps throughout
- [ ] No frame drops on page transitions
- [ ] Smooth scrolling

### Network Requests
- [ ] Only necessary requests made
- [ ] Images cached properly
- [ ] Offline mode handled gracefully

---

## ✅ **Regression Tests**

After any code changes, verify:

- [ ] Existing users (hasCompletedOnboarding=true) don't see onboarding
- [ ] Sign in flow still works
- [ ] Sign out and sign in again works
- [ ] Profile data persists after onboarding
- [ ] Notifications still work
- [ ] App usage tracking still works

---

## 🎯 **Success Criteria**

### Must Pass:
✅ All required pages enforce validation  
✅ Error handling works (retry logic)  
✅ Data saves successfully  
✅ No crashes or fatal errors  
✅ Referral codes validate correctly  
✅ Privacy permissions handled properly  

### Should Pass:
✅ Smooth animations (no jank)  
✅ Appropriate for all screen sizes  
✅ Accessible with VoiceOver  
✅ Works in poor network conditions  
✅ Feedback collection works  
✅ Recommendations are relevant  

### Nice to Have:
✅ Beautiful animations delight users  
✅ Loading states are informative  
✅ Error messages are helpful  
✅ Copy is clear and concise  

---

## 📝 **Bug Report Template**

```
**Title:** [Brief description]

**Steps to Reproduce:**
1. 
2. 
3. 

**Expected Result:**
[What should happen]

**Actual Result:**
[What actually happened]

**Device:**
- Model: iPhone 15 Pro
- iOS: 17.2
- App Version: 1.0

**Screenshots/Videos:**
[Attach if applicable]

**Console Logs:**
[Paste relevant logs]

**Severity:** Critical / High / Medium / Low
```

---

## 🚀 **Ready for Production Checklist**

Before releasing to production:

- [ ] All test scenarios pass
- [ ] No critical bugs
- [ ] Performance is acceptable
- [ ] Accessibility requirements met
- [ ] Error handling works
- [ ] Analytics tracking confirmed
- [ ] Firebase Security Rules tested
- [ ] Referral system functional
- [ ] User feedback collected in staging
- [ ] Documentation complete

---

**Last Updated:** January 31, 2026  
**Version:** 1.0

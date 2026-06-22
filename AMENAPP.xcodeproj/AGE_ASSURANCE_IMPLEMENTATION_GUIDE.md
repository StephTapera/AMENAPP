# Age Assurance Implementation Guide

## Overview

This guide explains AMEN's layered age assurance system, following Meta's Instagram/Threads pattern.

## Current Problem

The existing implementation shows the age gate **AFTER** the user is already signed in:
- `AMENAPPApp.swift:193-201` - Age gate appears post-authentication
- `AgeGateView.swift:76` - DOB is NOT stored (comment says "Do NOT store birthDate")
- No age-based feature gating
- No verification system for suspicious activity

## Meta's Pattern (Instagram/Threads)

Meta uses a **layered age assurance system**:

1. **Declared Age** — User enters DOB at sign-up (REQUIRED before account creation)
2. **Triggered Verification** — If suspicious (age change, AI flag), request ID/selfie
3. **AI Age Detection** — Background scoring to detect potential minors
4. **Feature Gating** — Restrict features for teens (DMs, sensitive content)

## New Implementation

### 1. Data Models (`AgeAssuranceModels.swift`)

**Age Tiers:**
- `underMinimum` (< 13): Blocked from sign-up
- `teen` (13-17): Restricted features
- `adult` (18+): Full access

**User Age Profile** (stored in `users/{uid}/private/age_assurance`):
```swift
struct UserAgeProfile {
    let dateOfBirth: Date           // Encrypted, private
    var tier: AgeAssuranceTier      // Computed from age
    var verificationStatus: AgeVerificationStatus
    var aiRiskScore: Double         // 0.0-1.0 (AI detection)
    // ... audit trail fields
}
```

**Age-Restricted Features:**
- Direct Messages (18+ only)
- Public Profiles (13+ only)
- Sensitive Content (18+ only)
- Commerce/IAP (18+ only)
- Live Streaming (18+ only)

### 2. Service Layer (`AgeAssuranceService.swift`)

**Core Methods:**

```swift
// Store DOB during sign-up (BEFORE account creation)
await AgeAssuranceService.shared.setDateOfBirth(
    userId: userId,
    dateOfBirth: selectedDate,
    countryCode: "US"
)

// Load tier on app launch / sign-in
await AgeAssuranceService.shared.loadTier(for: userId)

// Check feature access
let canDM = await AgeAssuranceService.shared.canAccess(
    feature: .directMessages,
    userId: userId
)

// Request verification (for age changes or AI flags)
try await AgeAssuranceService.shared.requestVerification(
    userId: userId,
    reason: "Age change from 17 to 18"
)
```

**Caching:**
- 5-minute cache for age profiles (reduce Firestore reads)
- Cache invalidated on updates

**Audit Trail:**
- All events logged to `age_verification_events` collection
- Tracks: age collected, age changed, verification requested, AI flags, feature blocks

### 3. UI Components

#### `DateOfBirthCollectionView.swift`
Modern DOB collection view for sign-up:
- Date picker with instant age validation
- Visual feedback for age tier (Teen/Adult)
- Privacy assurance ("birthday is private")
- Blocks under-13 with clear error message
- Matches AMEN's dark glassmorphic design

**Integration Point:**
This view should appear **during sign-up**, BEFORE the account is created in Firebase Auth.

### 4. Integration Steps

#### Step 1: Update Sign-Up Flow (SignInView.swift)

The sign-up flow should be:
1. Collect email/username/password
2. **→ Collect DOB (NEW)** ← BEFORE createUserWithEmailAndPassword
3. Validate age >= 13
4. Create Firebase Auth account
5. Store age profile in Firestore
6. Continue to onboarding

**Required Changes:**

```swift
// In SignInView.swift, add state:
@State private var showDOBCollection = false
@State private var dateOfBirth = Date()

// After validating email/username/password, show DOB sheet:
.sheet(isPresented: $showDOBCollection) {
    DateOfBirthCollectionView(
        dateOfBirth: $dateOfBirth,
        isPresented: $showDOBCollection
    ) { selectedDate in
        // DOB collected, now create account
        Task {
            await createAccountWithDOB(
                email: email,
                password: password,
                username: username,
                dateOfBirth: selectedDate
            )
        }
    }
}

// New method to create account WITH age verification:
func createAccountWithDOB(
    email: String,
    password: String,
    username: String,
    dateOfBirth: Date
) async {
    do {
        // 1. Validate age FIRST
        let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
        guard age >= AppConfig.Legal.minimumAge else {
            errorMessage = "You must be \(AppConfig.Legal.minimumAge) or older to create an account"
            showError = true
            return
        }
        
        // 2. Create Firebase Auth account
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let userId = result.user.uid
        
        // 3. Store age profile (CRITICAL: Do this immediately)
        try await AgeAssuranceService.shared.setDateOfBirth(
            userId: userId,
            dateOfBirth: dateOfBirth
        )
        
        // 4. Create user document with username
        // ... existing code ...
        
        // 5. Continue to onboarding
        // ... existing code ...
    } catch {
        // Handle errors
        errorMessage = error.localizedDescription
        showError = true
    }
}
```

#### Step 2: Update AMENAPPApp.swift

**Remove the post-auth age gate:**

```swift
// ❌ DELETE THIS (lines 193-201):
if !hasCompletedAgeVerification {
    Color.clear
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedAgeVerification },
            set: { _ in }
        )) {
            AgeGateView(isEligible: $ageGateEligible)
        }
}
```

**Add age tier loading:**

```swift
// In AMENAPPApp.swift, inside the startup task group:
group.addTask {
    if let userId = Auth.auth().currentUser?.uid {
        await AgeAssuranceService.shared.loadTier(for: userId)
    }
}
```

#### Step 3: Add Feature Gating

Use the `.ageGated()` modifier (already exists for DMs):

```swift
// In MessagesView (already implemented):
MessagesView()
    .ageGated(feature: .dms)
```

**Add to other features:**

```swift
// In settings, before showing "Become a Creator":
if await AgeAssuranceService.shared.canAccess(feature: .commerce) {
    // Show creator/monetization options
} else {
    // Show "Available at 18+"
}
```

#### Step 4: Handle Existing Users (Migration)

Create a Cloud Function to backfill age profiles for existing users:

```javascript
// functions/src/migrateUserAges.js
exports.migrateUserAges = functions.https.onCall(async (data, context) => {
    // Admin-only operation
    if (!context.auth?.token.admin) {
        throw new functions.https.HttpsError('permission-denied', 'Admin only');
    }
    
    const usersSnapshot = await admin.firestore().collection('users').get();
    const batch = admin.firestore().batch();
    
    for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        
        // Check if age profile exists
        const ageProfileDoc = await admin.firestore()
            .collection('users')
            .doc(userId)
            .collection('private')
            .doc('age_assurance')
            .get();
        
        if (!ageProfileDoc.exists) {
            // Default: assume adult (age 18) for existing users
            // In production, you might want to collect this properly
            const defaultAge = {
                dateOfBirth: new Date(new Date().getFullYear() - 18, 0, 1),
                tier: 'adult',
                verificationStatus: 'declared',
                verificationMethods: ['date_of_birth'],
                lastVerified: admin.firestore.FieldValue.serverTimestamp(),
                aiRiskScore: 0.0,
                verificationAttempts: 0,
                countryCode: 'US',
                parentalSupervisionEnabled: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            };
            
            batch.set(
                admin.firestore()
                    .collection('users')
                    .doc(userId)
                    .collection('private')
                    .doc('age_assurance'),
                defaultAge
            );
        }
    }
    
    await batch.commit();
    return { success: true, migrated: usersSnapshot.size };
});
```

### 5. Firestore Security Rules

Add rules for the age assurance subcollection:

```javascript
// firestore.rules
match /users/{userId}/private/age_assurance {
    // Only the user or admin can read their age profile
    allow read: if request.auth.uid == userId || hasAdminClaim();
    
    // Users can create their age profile once (during sign-up)
    allow create: if request.auth.uid == userId
                  && !exists(/databases/$(database)/documents/users/$(userId)/private/age_assurance);
    
    // Users cannot update their own age profile (prevents self-promotion to adult)
    // Only server-side Cloud Functions can update (via Admin SDK)
    allow update: if false;
    
    // Nobody can delete age profiles
    allow delete: if false;
}

// Age verification events (admin or server writes only)
match /age_verification_events/{eventId} {
    allow read: if hasAdminClaim();
    allow write: if false;  // Server-side only via Admin SDK
}

function hasAdminClaim() {
    return request.auth.token.admin == true;
}
```

### 6. Testing Checklist

#### Sign-Up Flow
- [ ] New user sees DOB collection BEFORE account creation
- [ ] Under-13 users are blocked with clear message
- [ ] 13-17 users see "Teen Account" indicator
- [ ] 18+ users see "Full Access" indicator
- [ ] DOB is stored in `users/{uid}/private/age_assurance`
- [ ] Age tier is set correctly (teen/adult)

#### Feature Gating
- [ ] Teen users cannot access DMs (blocked with explanation)
- [ ] Adult users can access all features
- [ ] Feature block events are logged

#### Age Changes
- [ ] Teens trying to change age to 18+ are prompted for verification
- [ ] Other age changes are allowed without verification

#### Existing Users
- [ ] Migration script creates default adult profiles
- [ ] Existing users are not blocked from app usage

## Future Enhancements

### Phase 2: Triggered Verification

1. **Government ID Upload**
   - Integrate with Yoti or Jumio for ID verification
   - Store verification result, delete ID images after 30 days
   - Update `verificationStatus` to `verified`

2. **Video Selfie Age Estimation**
   - Integrate with Yoti's age estimation API
   - Estimate age from facial features (no identification)
   - Use as fallback if user doesn't have ID

3. **Verification UI**
   ```swift
   struct AgeVerificationSheet: View {
       let reason: String
       @State private var selectedMethod: AgeVerificationMethod = .governmentID
       
       var body: some View {
           VStack {
               Text("Verify Your Age")
               Text(reason)
               
               // Method picker: Government ID / Video Selfie
               // Upload flow
               // Submit button
           }
       }
   }
   ```

### Phase 3: AI Age Detection

1. **Behavioral Signals**
   - Content patterns (teen slang, school references)
   - Social graph (connections to known teens)
   - Engagement patterns (typical teen usage times)
   - Profile setup choices

2. **AI Risk Scoring**
   - Run Cloud Function on content creation
   - Compute risk score 0.0-1.0
   - If > 0.6, flag for verification
   - Update `aiRiskScore` in age profile

3. **Auto-Flagging**
   ```javascript
   // Cloud Function: analyzeUserAgeRisk
   exports.analyzeUserAgeRisk = functions.firestore
       .document('posts/{postId}')
       .onCreate(async (snapshot, context) => {
           const post = snapshot.data();
           const userId = post.userId;
           
           // Get age profile
           const ageProfile = await getAgeProfile(userId);
           if (ageProfile.tier === 'adult') {
               // Run AI analysis
               const riskScore = await computeAgeRiskScore(userId, post);
               
               if (riskScore > 0.6) {
                   // Flag for verification
                   await flagUserForVerification(userId, riskScore);
               }
           }
       });
   ```

### Phase 4: Parental Supervision

For teens (especially under-16 in some regions):
1. Parent can approve/deny feature access
2. Parent receives notification of verification requests
3. Parent can view activity dashboard
4. Follows COPPA-style supervision model

## Summary

The new implementation follows Meta's best practices:

✅ **Declared Age at Sign-Up** — DOB collected BEFORE account creation  
✅ **Proper Storage** — Encrypted in private subcollection  
✅ **Age Tiers** — Teen vs Adult with different permissions  
✅ **Feature Gating** — DMs, commerce, etc. blocked for minors  
✅ **Audit Trail** — All events logged for compliance  
✅ **Extensible** — Ready for verification, AI detection, parental controls

**Next Step:** Integrate `DateOfBirthCollectionView` into `SignInView.swift` sign-up flow as shown in Step 1 above.

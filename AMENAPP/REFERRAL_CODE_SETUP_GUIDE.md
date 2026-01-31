# Referral Code Setup Guide

## 🎯 Quick Start

To enable the referral code system in your app, you need to set up the Firestore collections and optionally create initial codes.

---

## 📊 **Firestore Structure**

### 1. Create `referralCodes` Collection

```javascript
// Collection: referralCodes
// Document ID: The actual code (e.g., "FAITH2026")

{
  userId: "user_firebase_uid",        // The user who owns this code
  createdAt: Timestamp,               // When code was created
  expiresAt: Timestamp (optional),    // Optional expiration date
  maxUses: 100 (optional),            // Optional usage limit
  currentUses: 0 (optional),          // Track how many times used
  isActive: true,                     // Enable/disable codes
}
```

### 2. Create `referrals` Collection

```javascript
// Collection: referrals
// Document ID: Auto-generated

{
  referrerId: "referrer_user_id",     // Who referred
  referredUserId: "new_user_id",      // Who was referred
  code: "FAITH2026",                  // Code used
  timestamp: Timestamp,               // When referral happened
  status: "active",                   // active, redeemed, expired
}
```

### 3. Update `users` Collection

Add these fields to user documents:

```javascript
{
  // Existing fields...
  
  // For users who USED a referral code:
  referredBy: "referrer_user_id",     // Who referred them
  referralCode: "FAITH2026",          // Code they used
  referralAppliedAt: Timestamp,       // When they used it
  
  // For users who HAVE a referral code:
  myReferralCode: "USER123",          // Their personal code
  referralCount: 5,                   // How many people they referred
}
```

---

## 🔧 **Firebase Console Setup**

### Step 1: Create Initial Referral Codes

1. Go to Firebase Console → Firestore Database
2. Create collection: `referralCodes`
3. Add documents with code as ID:

**Example codes:**

```javascript
// Document ID: "WELCOME2026"
{
  userId: "admin_user_id",
  createdAt: now,
  isActive: true
}

// Document ID: "EARLYADOPTER"
{
  userId: "admin_user_id", 
  createdAt: now,
  maxUses: 500,
  currentUses: 0,
  isActive: true
}

// Document ID: "INVITE50"
{
  userId: "admin_user_id",
  createdAt: now,
  maxUses: 50,
  currentUses: 0,
  isActive: true,
  perks: ["early_access", "premium_features"]
}
```

### Step 2: Generate User-Specific Codes

When a user signs up, you can auto-generate their personal referral code:

```swift
func generateReferralCode(for userId: String) async throws {
    let db = Firestore.firestore()
    
    // Generate unique 8-character code
    let code = generateUniqueCode()
    
    // Save to referralCodes collection
    try await db.collection("referralCodes").document(code).setData([
        "userId": userId,
        "createdAt": Timestamp(date: Date()),
        "isActive": true
    ])
    
    // Save to user document
    try await db.collection("users").document(userId).updateData([
        "myReferralCode": code,
        "referralCount": 0
    ])
    
    print("✅ Generated referral code: \(code)")
}

func generateUniqueCode(length: Int = 8) -> String {
    let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Exclude confusing chars
    return String((0..<length).map { _ in letters.randomElement()! })
}
```

---

## 🔐 **Security Rules**

Update your Firestore Security Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Referral Codes - Read-only for users
    match /referralCodes/{code} {
      allow read: if request.auth != null;
      allow write: if false; // Only via Cloud Functions
    }
    
    // Referrals - Read own, write once
    match /referrals/{referralId} {
      allow read: if request.auth != null && 
                     (resource.data.referrerId == request.auth.uid ||
                      resource.data.referredUserId == request.auth.uid);
      allow create: if request.auth != null;
      allow update, delete: if false;
    }
    
    // Users - Can update own referral info
    match /users/{userId} {
      allow read: if request.auth != null;
      allow update: if request.auth.uid == userId &&
                       request.resource.data.keys().hasOnly([
                         'referredBy', 'referralCode', 'referralAppliedAt'
                       ]);
    }
  }
}
```

---

## ☁️ **Cloud Functions (Optional)**

For production, use Cloud Functions to manage referral codes:

```javascript
// functions/index.js

const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Generate referral code when user signs up
exports.generateReferralCode = functions.auth.user().onCreate(async (user) => {
  const db = admin.firestore();
  const code = generateCode(8);
  
  try {
    // Create referral code
    await db.collection('referralCodes').doc(code).set({
      userId: user.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isActive: true,
      currentUses: 0
    });
    
    // Update user document
    await db.collection('users').doc(user.uid).update({
      myReferralCode: code,
      referralCount: 0
    });
    
    console.log(`Generated code ${code} for user ${user.uid}`);
  } catch (error) {
    console.error('Error generating referral code:', error);
  }
});

// Validate and apply referral code
exports.applyReferralCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }
  
  const { code } = data;
  const userId = context.auth.uid;
  const db = admin.firestore();
  
  // Validate code
  const codeDoc = await db.collection('referralCodes').doc(code).get();
  
  if (!codeDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Invalid referral code');
  }
  
  const codeData = codeDoc.data();
  
  // Check if code is active
  if (!codeData.isActive) {
    throw new functions.https.HttpsError('failed-precondition', 'Code is inactive');
  }
  
  // Check max uses
  if (codeData.maxUses && codeData.currentUses >= codeData.maxUses) {
    throw new functions.https.HttpsError('resource-exhausted', 'Code has reached maximum uses');
  }
  
  // Check if user is trying to use own code
  if (codeData.userId === userId) {
    throw new functions.https.HttpsError('invalid-argument', 'Cannot use your own referral code');
  }
  
  // Apply referral
  const batch = db.batch();
  
  // Update user document
  batch.update(db.collection('users').doc(userId), {
    referredBy: codeData.userId,
    referralCode: code,
    referralAppliedAt: admin.firestore.FieldValue.serverTimestamp()
  });
  
  // Increment referrer's count
  batch.update(db.collection('users').doc(codeData.userId), {
    referralCount: admin.firestore.FieldValue.increment(1)
  });
  
  // Create referral record
  batch.set(db.collection('referrals').doc(), {
    referrerId: codeData.userId,
    referredUserId: userId,
    code: code,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    status: 'active'
  });
  
  // Update code usage count
  batch.update(db.collection('referralCodes').doc(code), {
    currentUses: admin.firestore.FieldValue.increment(1)
  });
  
  await batch.commit();
  
  return { success: true, message: 'Referral code applied successfully' };
});

function generateCode(length) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}
```

---

## 🎁 **Reward System (Optional)**

Track and reward users for successful referrals:

```javascript
// Add to users collection
{
  referralRewards: {
    points: 500,              // Points earned from referrals
    unlockedFeatures: [       // Features unlocked via referrals
      "early_access",
      "custom_themes"
    ],
    tier: "gold"              // bronze, silver, gold, platinum
  }
}
```

**Reward Tiers:**
- 🥉 Bronze (1-5 referrals): Thank you badge
- 🥈 Silver (6-15 referrals): Custom profile themes
- 🥇 Gold (16-50 referrals): Early feature access
- 💎 Platinum (51+ referrals): VIP support

---

## 📊 **Analytics Queries**

### Top Referrers

```javascript
db.collection('users')
  .orderBy('referralCount', 'desc')
  .limit(10)
  .get()
```

### Recent Referrals

```javascript
db.collection('referrals')
  .orderBy('timestamp', 'desc')
  .limit(20)
  .get()
```

### Most Used Codes

```javascript
db.collection('referralCodes')
  .where('isActive', '==', true)
  .orderBy('currentUses', 'desc')
  .limit(10)
  .get()
```

---

## 🧪 **Testing**

### Test Referral Flow

1. **Create Test Code:**
   ```
   Code: TEST123
   UserId: test_user_1
   ```

2. **Sign up new user** (test_user_2)

3. **Enter TEST123** during onboarding

4. **Verify in Firestore:**
   - test_user_2 has `referredBy: test_user_1`
   - test_user_1 has `referralCount: 1`
   - New document in `referrals` collection

### Test Error Cases

- Invalid code → "Invalid referral code"
- Own code → "Cannot use your own code"
- Expired code → "Code has expired"
- Max uses reached → "Code limit reached"

---

## 🚀 **Launch Checklist**

- [ ] Create `referralCodes` collection
- [ ] Create `referrals` collection
- [ ] Add fields to `users` collection
- [ ] Update Security Rules
- [ ] Deploy Cloud Functions (if using)
- [ ] Create initial promo codes
- [ ] Test complete referral flow
- [ ] Set up analytics dashboard
- [ ] Document reward structure
- [ ] Train support team

---

## 📞 **Support**

For issues with referral codes:
1. Check Firestore console for code existence
2. Verify Security Rules allow read access
3. Check user document for existing referral
4. Review Cloud Function logs (if applicable)

---

**Last Updated:** January 31, 2026  
**Version:** 1.0

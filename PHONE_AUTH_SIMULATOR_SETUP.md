# Phone Auth Testing in Simulator - Quick Setup Guide

## 🚨 Current Issue

You're seeing:
```
❌ Failed to send verification code: The interaction was cancelled by the user.
```

This happens because **the iOS Simulator cannot send real SMS messages**. The reCAPTCHA verification process opens, but fails to complete.

---

## ✅ Solution: Configure Test Phone Numbers in Firebase

### Step 1: Open Firebase Console
1. Go to https://console.firebase.google.com
2. Select your project: **AMEN** (amen-5e359)
3. Navigate to: **Authentication** → **Sign-in method**

### Step 2: Enable Phone Authentication (if not already)
1. Click on **Phone** provider
2. Ensure it's **Enabled**
3. Click **Save**

### Step 3: Add Test Phone Numbers
1. Scroll down to: **Phone numbers for testing**
2. Click **Add phone number**
3. Add test numbers:

| Phone Number | Verification Code |
|--------------|-------------------|
| `+1 650-555-1234` | `123456` |
| `+1 650-555-5678` | `654321` |
| `+1 720-305-2376` | `111111` |

4. Click **Add**
5. Click **Save**

### Step 4: Test in Simulator
1. Run app in simulator
2. Sign up with:
   - Email: `test@example.com`
   - Password: `Test123!`
   - Display Name: `Test User`
   - Username: `testuser`
   - **Phone: `(650) 555-1234`** ← Use test number
3. OTP modal appears
4. Enter code: `123456` ← Use test verification code
5. ✅ Should work without errors!

---

## 🔍 What's Happening in Console

### Before Fix:
```
⚠️ Unknown URL scheme: com.googleusercontent.apps...
❌ Failed to send verification code: The interaction was cancelled by the user.
```

### After Fix (with test numbers):
```
✅ Forwarded notification to Firebase Auth for phone verification
📱 Sending OTP to: (650) 555-1234
✅ Phone verification successful
```

---

## 📱 Alternative: Test on Physical Device

If you want to test with **real phone numbers**:

1. Connect iPhone via USB
2. Select your device in Xcode
3. Build and run
4. Enter your real phone number
5. Receive actual SMS with OTP code
6. Complete verification

---

## ⚠️ Why Simulator Fails

1. **No cellular radio** - Simulator can't send/receive SMS
2. **reCAPTCHA required** - Firebase requires bot verification
3. **Browser handoff** - Safari opens for reCAPTCHA, but simulator environment causes cancellation

Firebase provides test phone numbers specifically for this reason.

---

## 🧪 Testing Checklist

### With Test Phone Numbers
- [ ] Configure test numbers in Firebase Console
- [ ] Run app in simulator
- [ ] Enter test phone number during sign-up
- [ ] OTP modal appears
- [ ] Enter test verification code
- [ ] Success checkmark animation plays
- [ ] Proceed to onboarding
- [ ] Profile created with phone number

### With Real Phone (Physical Device)
- [ ] Build to physical iPhone
- [ ] Enter real phone number
- [ ] Receive SMS
- [ ] Enter real OTP code
- [ ] Complete sign-up

---

## 🔗 Firebase Documentation

- [Phone Auth iOS Setup](https://firebase.google.com/docs/auth/ios/phone-auth)
- [Test with Fictional Phone Numbers](https://firebase.google.com/docs/auth/ios/phone-auth#test-with-fictional-phone-numbers)
- [reCAPTCHA Verification](https://firebase.google.com/docs/auth/ios/phone-auth#enable-app-verification)

---

## ✅ URL Scheme Configuration (Already Done)

Your `Info.plist` already has the correct URL scheme:
```xml
<string>com.googleusercontent.apps.78278013543-ipl34cmeo3qrkcrma2scqc70o5pvh1f6</string>
```

The "Unknown URL scheme" warning is **benign** - it's just logging that the URL is being processed. Firebase Auth is handling it correctly.

---

## 🎯 Quick Summary

**Problem:** Simulator can't send real SMS
**Solution:** Use test phone numbers from Firebase Console
**How:** Add `+1 650-555-1234` with code `123456` in Firebase Console
**Result:** Phone auth works perfectly in simulator

---

**Last Updated:** February 25, 2026
**Status:** ✅ URL scheme configured, awaiting Firebase test numbers setup

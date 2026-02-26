# Phone Number Sign-Up User Flow

**Date**: February 25, 2026

---

## Complete User Journey - Phone Sign-Up

### 1. App Launch (First Time)
```
App Opens
  ↓
WelcomeScreenView shows for 1.3 seconds
  - AMEN logo
  - "Social Media, Re-ordered" tagline
  ↓
ContentView state resolves (1.4s delay)
  ↓
SignInView appears
```

### 2. Sign-Up Form
```
SignInView
  ↓
User taps "Sign Up" toggle
  ↓
Shows sign-up method toggle: [Email] [Phone]
  ↓
User selects "Phone" method
  ↓
Form shows only:
  - Display Name field
  - Username field (with availability check)
  - Phone Number field
  ↓
User fills in all fields
  ↓
Presses "Sign Up" button
```

**Files**: `SignInView.swift` lines 108-154 (toggle), 175-216 (conditional fields)

---

### 3. Phone Verification Code Sent
```
handleAuth() called
  ↓
signUpMethod == .phone detected
  ↓
viewModel.sendPhoneVerificationCode(phoneNumber)
  ↓
Firebase sends SMS with OTP
  ↓
OTPVerificationView sheet appears
```

**Files**: 
- `SignInView.swift` lines 664-674
- `AuthenticationViewModel.swift` `sendPhoneVerificationCode()` method

---

### 4. OTP Entry
```
OTPVerificationView shows:
  - 6 digit boxes
  - Phone number display
  - Resend timer (60 seconds)
  ↓
User enters 6-digit code
  ↓
Auto-verifies when 6 digits entered
  OR
User presses "Verify Code" button
```

**Files**: `SignInView.swift` lines 1668-1816 (OTPVerificationView)

---

### 5. OTP Verification & Account Creation
```
verifyOTP() called
  ↓
Checks:
  - OTP not expired (10 min limit)
  - Not too many attempts (5 max)
  ↓
For sign-up (isLogin = false):
  viewModel.verifyPhoneCode(otpCode, displayName, username)
  ↓
AuthenticationViewModel.verifyPhoneCode():
  1. Creates PhoneAuthCredential
  2. Signs in with Firebase Auth
  3. Creates user profile in Firestore:
     - userId
     - displayName
     - username (lowercase version saved)
     - phoneNumber
     - phoneVerified: true
     - createdAt timestamp
     - NO EMAIL (phone-only auth)
  4. Sets needsOnboarding = true
  ↓
Phone number saved to user document
  ↓
OTP sheet closes
```

**Files**:
- `SignInView.swift` lines 829-890 (verifyOTP)
- `AuthenticationViewModel.swift` `verifyPhoneCode()` method

---

### 6. Onboarding Flow
```
isAuthenticated = true
needsOnboarding = true
  ↓
ContentView shows OnboardingView
  ↓
User goes through 12 onboarding pages:
  1. Welcome to AMEN
  2. Everything You Need
  3. What interests you
  4. Notification preferences
  5. What are your goals
  6. Your data, your control
  7. Prayer reminders
  8. Secure your account (2FA - optional)
  9. Community covenant
  10. Daily time limit
  11. How did you hear about us
  12. You're all set!
  ↓
User presses "Complete Setup"
  ↓
All preferences saved to Firestore
```

**Files**: 
- `OnboardingOnboardingView.swift`
- `ContentView.swift` lines 127-135

---

### 7. Post-Onboarding Transition
```
Onboarding data saved successfully
  ↓
authViewModel.showWelcomeToAMENScreen() called FIRST
  ↓
Wait 0.1 seconds
  ↓
authViewModel.completeOnboarding() called
  - Sets needsOnboarding = false
  ↓
WelcomeToAMENView fullScreenCover appears
  - "Welcome to AMEN, [DisplayName]"
  - Animated entrance
  ↓
User dismisses welcome screen
  ↓
Main app (OpenTable) appears
```

**Files**: 
- `OnboardingOnboardingView.swift` lines ~273-284 (completion flow)
- `ContentView.swift` lines 147-150 (WelcomeToAMEN fullScreenCover)

---

## State Flow Chart

```
┌─────────────────────────────────────────────┐
│  AMENAPPApp.swift                           │
│  showWelcomeScreen = true (1.3s)            │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  ContentView.swift                          │
│  isResolvingAuthState = true (1.4s delay)   │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  !isAuthenticated → SignInView              │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  SignInView.swift                           │
│  - User selects "Phone" method              │
│  - Enters: displayName, username, phone     │
│  - Presses "Sign Up"                        │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  OTP Sent → OTPVerificationView             │
│  - User enters 6-digit code                 │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  AuthenticationViewModel                    │
│  verifyPhoneCode():                         │
│  - Firebase Auth sign-in                    │
│  - Create user profile in Firestore         │
│  - Set isAuthenticated = true               │
│  - Set needsOnboarding = true               │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  ContentView.swift                          │
│  needsOnboarding = true → OnboardingView    │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  OnboardingOnboardingView.swift             │
│  - 12 pages of preferences                  │
│  - User completes setup                     │
│  - Save all data to Firestore               │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Completion Flow:                           │
│  1. showWelcomeToAMENScreen()               │
│  2. Wait 0.1s                                │
│  3. completeOnboarding()                    │
│     (needsOnboarding = false)               │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  WelcomeToAMENView (fullScreenCover)        │
│  "Welcome to AMEN, [Name]!"                 │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Main App (OpenTable)                       │
│  User can start using AMEN                  │
└─────────────────────────────────────────────┘
```

---

## Key Files Involved

| File | Role |
|------|------|
| `AMENAPPApp.swift` | App entry point, shows initial welcome screen |
| `WelcomeScreenView.swift` | "AMEN" logo + "Social Media, Re-ordered" |
| `ContentView.swift` | Main routing logic, state resolution |
| `SignInView.swift` | Sign-up form with phone/email toggle |
| `AuthenticationViewModel.swift` | Firebase Auth logic, user creation |
| `OnboardingOnboardingView.swift` | 12-page onboarding flow |
| `WelcomeToAMENView.swift` | Post-onboarding welcome message |
| `firestore 18.rules` | Security rules (allows phone-only auth) |

---

## Firestore Document Created

```javascript
users/{userId} {
  displayName: "John Doe",
  username: "johndoe",
  usernameLowercase: "johndoe",
  phoneNumber: "+1234567890",
  phoneVerified: true,
  phoneVerifiedAt: Timestamp,
  createdAt: Timestamp,
  // NO EMAIL FIELD (phone-only auth)
  
  // Added during onboarding:
  interests: [...],
  notificationPreferences: {...},
  goals: [...],
  prayerTime: "morning",
  // etc.
}
```

---

## Important Notes

1. **No Email Required**: Phone sign-up does NOT require an email address
2. **Firestore Rules**: Allow phone-only auth via `sign_in_provider == 'phone'` check
3. **No Email Verification**: Phone users skip the EmailVerificationGateView
4. **2FA Optional**: Users can enable 2FA during onboarding (page 8)
5. **Smooth Transitions**: State resolution delays prevent flashing between screens

---

## Timing Breakdown

| Step | Duration |
|------|----------|
| Welcome screen (AMEN logo) | 1.3s |
| State resolution delay | 1.4s |
| Sign-up form (user input) | Variable |
| OTP send | ~2-5s |
| OTP entry (user input) | Variable |
| Account creation | ~1s |
| Onboarding (user input) | Variable |
| Onboarding save | ~1-2s |
| Welcome to AMEN screen | User dismisses |
| **Total automated time** | **~5-10 seconds** |

---

## Error Handling

- **OTP Expired**: 10-minute expiration, user must request new code
- **Too Many Attempts**: 5 failed OTP attempts blocks verification
- **Phone Already Used**: Firebase error if phone number already registered
- **Invalid Phone Format**: Client-side validation before sending
- **Network Errors**: Retry logic with exponential backoff
- **Firestore Permission Denied**: Rules allow phone-only auth

---

## Success Criteria

✅ User can sign up with ONLY phone number (no email)  
✅ OTP verification works in simulator (with test numbers) and production  
✅ User profile created in Firestore without email field  
✅ Onboarding flow completes smoothly  
✅ No screen flashing during transitions  
✅ Welcome message shows after onboarding  
✅ User lands on OpenTable (main feed)  

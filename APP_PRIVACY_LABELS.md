# App Store Privacy Nutrition Labels
**App:** AMEN
**Bundle ID:** tapera.AMENAPP
**Version:** 1.0 (build 5)
**Prepared by:** Agent 5, Launch Readiness Swarm
**Date:** 2026-06-11

---

> **Authority note:** This document is derived from code analysis of the production source tree (branch `safety-hardening`, HEAD `5525cf6e`). It supersedes `Docs/APP_STORE_PRIVACY_LABEL_MAPPING.md` as the submission-ready worksheet. Before uploading to App Store Connect, the release owner must verify every row against the live build.

---

## Data Collection Inventory (from code analysis)

### Location

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Precise location | YES | NO | NO | `CLLocationManager` in `FindChurchView.swift` (requestWhenInUseAuthorization), `ChurchChemistryService.swift` | Find nearby churches; church proximity features |
| Coarse location | YES | NO | NO | `INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription` — background location push entitlement (`com.apple.developer.location.push`) | Church proximity reminders when near saved churches |

**Info.plist strings confirmed:**
- `NSLocationWhenInUseUsageDescription`: "AMEN uses your location to find nearby churches and faith communities."
- `NSLocationAlwaysAndWhenInUseUsageDescription`: "We need your location to send you reminders when you're near your saved churches"

---

### Contact Info

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Email address | YES | YES | NO | Firebase Auth (email/password + Google Sign-In OAuth) | Account authentication and recovery |
| Name | YES | YES | NO | Profile creation flow | Display name shown on posts, prayer requests, DMs |
| Phone number | YES (optional) | NO | NO | `NSPrivacyCollectedDataTypePhoneNumber` in PrivacyInfo.xcprivacy (linked = false) | Optional 2FA / account verification |

---

### Health & Fitness

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Health data | YES | NO | NO | `HKHealthStore` in `SynapticStudioView.swift`, `BreathingExerciseView.swift`, `MovementWellnessView.swift` | Heart rate / activity read to craft personalized prayers and reflections in Synaptic Studio |
| Fitness data | YES | NO | NO | `NSPrivacyCollectedDataTypeFitness` declared in PrivacyInfo.xcprivacy | Log mindfulness minutes to Apple Health from prayer/meditation sessions |

**Info.plist strings confirmed:**
- `NSHealthShareUsageDescription`: "AMEN reads your heart rate and activity to help Synaptic Studio craft prayers and reflections that match how you feel right now. No health data is stored."
- `NSHealthUpdateUsageDescription`: "AMEN may log mindfulness minutes from prayer and meditation sessions to Apple Health..."

---

### Financial Info

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Purchase history | YES | YES | NO | StoreKit (in-app purchases) — `PremiumManager.swift`, `TwoFourTwoSubscriptionView.swift`, `AMENConnectMembership.swift`; Apple Pay merchant `merchant.com.amen.app` | Amen+, AmenPro, CreatorPro, ChurchPro subscription management |

---

### Photos & Videos

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Photos | YES | YES | NO | `PHPhotoLibrary` in `ProfilePhotoEditView.swift`, `Creator/Services/CreatorMediaImportService.swift`, `AMENPermissionsManager.swift` | Post media, profile photos, Creator media imports |
| Videos | YES | YES | NO | `AVCaptureSession` — `SingleCamCaptureService.swift`, `UnifiedChatView.swift` | Post media, video messages |

**Info.plist strings confirmed:**
- `NSPhotoLibraryUsageDescription`: "AMEN needs access to your photo library to share images in posts, messages, and your profile."
- `NSPhotoLibraryAddUsageDescription`: "AMEN saves shared photos and church media to your photo library."
- `NSCameraUsageDescription`: "AMEN uses the camera to take photos for posts, messages, and your profile picture."

---

### Audio

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Voice / sound recordings | YES | NO | NO | `AVAudioSession`/`AVAudioRecorder` in `ChurchNotesSermonCaptureService.swift`, `WhisperVoiceService.swift`, `VoiceStreamManager.swift`, `Feature06_VoiceDevotional.swift` | Sermon capture for Church Notes; voice post/prayer composition; voice devotional |

**Info.plist strings confirmed:**
- `NSMicrophoneUsageDescription`: "AMEN uses the microphone to let you compose posts, prayers, and messages by voice."

---

### Contacts

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Contacts | YES (on-device only) | NO | NO | `CNContactStore` in `ChurchChemistryService.swift` | Help find friends already on AMEN; no contact data stored on servers |

**Info.plist string confirmed:**
- `NSContactsUsageDescription`: "AMEN uses your contacts to help you find friends who are already on the app. No contact information is stored on our servers."

---

### User Content (Critical for UGC apps)

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Posts / messages | YES | YES | NO | Firestore `posts` collection; Firestore DM/chat collections | Social feed, DMs, UGC community features |
| Photos / videos (uploaded) | YES | YES | NO | Firebase Storage — media upload pipeline (quarantine/scan path) | Media posts, Creator media |
| Church notes | YES | YES | NO | Firestore `churchNotes` collection | Sermon note-taking feature |
| Prayer requests | YES | YES | NO | Firestore `prayers` collection | Prayer wall feature |
| Other user content | YES | YES | NO | Comments, reactions, Spaces posts, Creator content | Community features |

---

### Identifiers

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| User ID | YES | YES | NO | Firebase Auth UID | Account identity; all Firestore documents keyed by UID |
| Device ID | YES | YES | YES | FCM token (`PushNotificationManager.swift`); App Attest (`production` env in entitlements); `NSPrivacyCollectedDataTypeDeviceID` declared with Tracking=true in PrivacyInfo.xcprivacy | Push notifications; App Check / fraud prevention; analytics |
| Advertising ID (IDFA) | YES (if user grants ATT) | YES (if granted) | YES (if granted) | `ATTrackingManager.requestTrackingAuthorization` in `AppDelegate.swift` | Personalize experience; measure content effectiveness; ATT prompt shown at app launch |

---

### Usage Data

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| App activity (product interaction) | YES | YES | YES | Firebase Analytics — `AMENAPPApp.swift`, `FTUEManager.swift`, `CommunicationOSAnalyticsEvents.swift`; `NSPrivacyCollectedDataTypeProductInteraction` declared Tracking=true | Analytics; feature improvement |
| Search history | YES | NO | NO | `NSPrivacyCollectedDataTypeSearchHistory` declared in PrivacyInfo.xcprivacy | Improve search; Berean AI query history (user-clearable) |
| Crash data | YES | NO | NO | Firebase Crashlytics — `ScreenCrashLogger.swift` | Bug diagnosis |
| Performance data | YES | NO | NO | `NSPrivacyCollectedDataTypePerformanceData` declared in PrivacyInfo.xcprivacy | App performance monitoring |

---

### Sensitive Info

| Data type | Collected | Linked to user | Tracking | Purpose |
|---|---|---|---|---|
| Religious beliefs | YES (implied by app purpose) | YES | NO | Core faith community features — prayer requests, sermon notes, faith posts |

---

### Calendar & Reminders

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Calendar events | YES | YES | NO | `EKEventStore` in `CalendarProviderAdapter.swift`, `AmenCalendarService.swift` | Church event and service reminders |
| Reminders | YES | YES | NO | `NSRemindersUsageDescription` declared | Prayer commitment reminders; spiritual goals |

**Info.plist strings confirmed:**
- `NSCalendarsUsageDescription`: "AMEN adds church events and service reminders to your calendar so you never miss a moment."
- `NSRemindersUsageDescription`: "AMEN creates reminders for prayer commitments, church events, and spiritual goals."

---

### Biometrics / Authentication

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Face ID / Touch ID | YES (local only, not transmitted) | N/A (on-device) | NO | `LAContext` in `BiometricAuthService.swift`, `SignInView.swift` | Quick sign-in; account security |

**Info.plist string confirmed:**
- `NSFaceIDUsageDescription`: "AMEN uses Face ID to keep your account secure and let you sign in quickly."

---

### Motion

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Motion / activity | YES | NO | NO | `CMMotionManager` in `ChurchProximityEngine.swift`, `AmenContextOrchestrator.swift` | Detect driving to activate hands-free Berean Voice mode |

**Info.plist string confirmed:**
- `NSMotionUsageDescription`: "AMEN uses motion activity to detect when you're driving so it can activate hands-free Berean Voice mode."

---

### Speech Recognition

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Speech recognition | YES | NO | NO | `SFSpeechRecognizer` in `BereanToolbarExtras.swift`, `WhisperVoiceService.swift`, `ChurchNotesSermonCaptureService.swift` | Voice-to-text for posts, prayers, church note transcription |

**Info.plist string confirmed:**
- `NSSpeechRecognitionUsageDescription`: "AMEN uses speech recognition to let you compose posts, prayers, and messages by voice."

---

### Music

| Data type | Collected | Linked to user | Tracking | Source | Purpose |
|---|---|---|---|---|---|
| Apple Music access | YES | YES | NO | MusicKit — `NSAppleMusicUsageDescription` declared | Play worship songs in Church Notes |

---

## App Store Connect — Exact Answers Per Category

Use these when answering Apple's privacy questionnaire in App Store Connect:

| Apple Category | Subcategory | Collected? | Linked to User? | Tracking? |
|---|---|---|---|---|
| **Contact Info** | Email Address | YES | YES | NO |
| **Contact Info** | Name | YES | YES | NO |
| **Contact Info** | Phone Number | YES | NO | NO |
| **Health & Fitness** | Health | YES | NO | NO |
| **Health & Fitness** | Fitness | YES | NO | NO |
| **Financial Info** | Purchase History | YES | YES | NO |
| **Location** | Precise Location | YES | NO | NO |
| **Location** | Coarse Location | YES | NO | NO |
| **Sensitive Info** | Religious or Philosophical Beliefs | YES | YES | NO |
| **Contacts** | Contacts | YES | NO | NO |
| **User Content** | Other User Content | YES | YES | NO |
| **User Content** | Photos or Videos | YES | YES | NO |
| **User Content** | Audio Data | YES | NO | NO |
| **Identifiers** | User ID | YES | YES | NO |
| **Identifiers** | Device ID | YES | YES | YES |
| **Usage Data** | Product Interaction | YES | YES | YES |
| **Usage Data** | Search History | YES | NO | NO |
| **Diagnostics** | Crash Data | YES | NO | NO |
| **Diagnostics** | Performance Data | YES | NO | NO |
| **Purchases** | Purchase History | YES | YES | NO |

---

## Tracking Domains (NSPrivacyTrackingDomains — declared in PrivacyInfo.xcprivacy)

- `app-measurement.com` (Firebase Analytics measurement)
- `firebaselogging.googleapis.com` (Firebase logging)
- `firebase.googleapis.com` (Firebase core)

`NSPrivacyTracking` = **true** in PrivacyInfo.xcprivacy — ATT prompt is shown.

---

## Privacy Policy URL

**Action required (HUMAN):** Confirm the Privacy Policy URL is:
1. Set in App Store Connect under App Information
2. Accessible from within the app (Settings or sign-in screen link)

Suggested URL pattern: `https://amenapp.page.link/privacy` or your hosted policy URL.

---

## Third-Party SDKs / Processors (disclose in Privacy Policy)

| SDK / Service | Data processed | Purpose |
|---|---|---|
| Firebase Auth | Email, UID, Google OAuth token | Authentication |
| Firebase Firestore | All UGC, user profiles, settings | Backend storage |
| Firebase Storage | Media files | Media hosting |
| Firebase Analytics | Usage events, device ID | Analytics |
| Firebase Crashlytics | Crash logs | Bug tracking |
| Firebase App Check / App Attest | Device attestation | Fraud / abuse prevention |
| Firebase Cloud Functions | All callable backend logic | Backend processing |
| Google Sign-In | OAuth token, email, name, profile photo | Social sign-in |
| Apple Sign-In | Anonymous or email, name | Social sign-in |
| MusicKit | Apple Music playback | Church Notes music |
| HealthKit | Heart rate, activity, mindfulness | Synaptic Studio wellness |
| NeMo Guard (NVIDIA via Cloud Function) | Post/message text, image hashes | Content moderation |
| Google Vision API | Image content analysis | Image moderation |
| Algolia | Search queries, indexed content | Search |
| WeatherKit | Location-based weather | Daily Digest weather card |
| Stripe / Apple Pay | Payment tokens | Subscriptions and creator payments |

---

## Diff from Previous Listing

This is v1.0 — no prior App Store listing exists for this bundle ID.

---

## Sign-off Checklist

- [ ] Release owner reviewed all YES rows above against production build
- [ ] Legal/privacy reviewed sensitive data rows (health, religious beliefs, minors)
- [ ] Privacy policy URL confirmed accessible in-app and in App Store Connect
- [ ] ATT prompt confirmed shown before any IDFA access (verified in AppDelegate.swift)
- [ ] NSPrivacyTracking = true confirmed matches ATT behavior

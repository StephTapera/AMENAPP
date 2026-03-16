# CLAUDE.md — AMEN App Project Context

## Project
AMEN is a faith-centered social app designed for reflection, growth, and meaningful interaction rather than attention-driven engagement. Built as an iOS app in SwiftUI with a Firebase backend.

## Repository Structure

```
AMENAPP/
├── AMENAPP/                    # iOS app source (SwiftUI)
│   ├── *View.swift             # 174 SwiftUI views
│   ├── *Service.swift          # ~94 singleton services
│   ├── *ViewModel.swift        # ViewModels (ContentViewModel, AuthenticationViewModel, etc.)
│   ├── *Model*.swift           # Data models (Post, User, Message, Church, etc.)
│   ├── *Manager.swift          # Manager singletons (PostsManager, FirebaseManager, etc.)
│   ├── Assets.xcassets/        # Image and color assets
│   ├── GoogleService-Info.plist
│   ├── Info.plist
│   ├── AMENAPP.entitlements
│   ├── firestore-rules-backups/
│   ├── storage.rules
│   └── database.rules.json
├── AMENAPP.xcodeproj/          # Xcode project (no CocoaPods/SPM Package.swift)
│   ├── project.pbxproj
│   ├── Onboarding*.swift       # Onboarding flow views and coordinator
│   ├── DailyCheckIn*.swift     # Daily check-in feature
│   └── Extensions.swift
├── AMENAPPTests/               # XCTest unit tests
│   ├── AuthSecurityTests.swift
│   ├── ReliabilityAuditTests.swift
│   ├── SafetyGateTests.swift
│   └── ShabbatModeTests.swift
├── AMENShareExtension/         # iOS Share Extension
├── AMENWidgetExtension/        # iOS Widget Extension
├── functions/                  # Firebase Cloud Functions (Node.js, v7/2nd gen)
│   ├── index.js                # Main entry point — exports all functions
│   ├── pushNotifications.js    # Push notification handlers
│   ├── contentModeration.js    # Content moderation pipeline
│   ├── imageModeration.js      # Cloud Vision SafeSearch
│   ├── aiModeration.js         # AI-powered moderation
│   ├── aiChurchNotes.js        # AI church notes features
│   ├── aiPersonalization.js    # ML-powered feed/notification personalization
│   ├── twoFactorAuth.js        # 2FA OTP flows
│   ├── phoneAuthRateLimit.js   # Phone auth rate limiting
│   ├── accountDeletion.js      # Account deletion handler
│   ├── bereanFunctions.js      # Berean AI backend
│   ├── shabbatMiddleware.js    # Sunday/Shabbat mode enforcement
│   ├── rateLimiter.js          # Server-side rate limiting
│   ├── postAndCommentFunctions.js  # Post/comment pipeline
│   └── package.json            # Node 24, firebase-functions v7
├── cloud-functions/            # Cloud Functions 2nd gen (moderation/crisis)
│   ├── index.js
│   ├── moderation.js
│   ├── crisis-detection.js
│   └── package.json            # Node 20, firebase-functions v5
├── cloud-run/
│   ├── feed/                   # Feed ranking service (Express + TypeScript)
│   └── search/                 # Semantic search via Vertex AI embeddings (Express + TS)
├── genkit/                     # Genkit AI server (Bible study, TypeScript)
│   ├── berean-flows.ts
│   └── src/
├── genkit-deploy/              # Genkit deployment (JS)
├── firebase.json               # Firebase project config (Firestore, Storage, RTDB, Functions)
├── firestore.rules             # Firestore security rules
├── database.rules.json         # Realtime Database rules
└── .firebaserc                 # Firebase project aliases
```

### Note on Duplicate Files
There are ~71 duplicate `* 2.swift` files and ~242 loose `.swift` files at the repository root. These appear to be Xcode copy artifacts. The canonical source is always the file **without** the `" 2"` suffix inside `AMENAPP/`.

## Core Features

| Feature | Key Files |
|---------|-----------|
| **OpenTable** (main feed) | `ContentView.swift`, `ViewModelsContentViewModel.swift`, `PostsManager.swift`, `RealtimePostService.swift` |
| **Testimonies** | `QuickTestimonyView.swift`, `TestimonyCategoryDetailView.swift`, `FeaturedTestimoniesManager.swift` |
| **Prayer** | `PrayerView.swift`, `PrayerWallView.swift`, `ModernPrayerWallView.swift`, `PrayerTimerView.swift`, `PrayerGroupsView.swift`, `PrayerToolkitView.swift` |
| **Church Notes** | `ChurchNotesView.swift`, `ChurchNotesService.swift`, `ChurchNotesShareHelper.swift` |
| **Berean AI** | `BereanAIAssistantView.swift`, `BereanAnswerEngine.swift`, `BereanIntegrationService.swift`, `BereanFastMode.swift`, `BereanIntentRouter.swift` (~19 files) |
| **Messages** | `Message.swift`, `MessageModels.swift`, `MessagingCoordinator` (in ContentView), `FirebaseMessagingService+TypingIndicators.swift` |
| **Notifications** | `NotificationsView.swift`, `NotificationService.swift`, `PushNotificationHandler.swift`, `SmartNotificationEngine.swift` |
| **People Discovery** | `PeopleDiscoveryView.swift`, `FindFriendsView.swift`, `FindFriendsOnboardingView.swift` |
| **Profile** | `ProfileView.swift`, `UserProfileView.swift`, `ProfilePhotoEditView.swift`, `ProfilePhotoService.swift` |
| **Find Church** | `FindChurchView.swift`, `ChurchProfileView.swift`, `ChurchDataService.swift`, `ChurchSearchService.swift` |
| **AMEN Connect** (dating) | `AmenConnectView.swift`, `ChristianDatingView.swift`, `DatingModels.swift`, `DatingAPIClient.swift` |
| **Premium / IAP** | `PremiumUpgradeView.swift`, `PremiumManager.swift` |
| **Books** | `BooksViewModel.swift`, `EssentialBooksViewModel.swift`, `BooksAPIService.swift` |
| **AI Features** | `AIBibleStudyView.swift`, `AIDailyVerseView.swift`, `AISearchComponents.swift`, `AIToneGuidanceService.swift`, `AINoteSummarizationService.swift` |

## Tech Stack

### iOS App
- **Language:** Swift / SwiftUI
- **Min target:** iOS (check Info.plist for version)
- **UI framework:** SwiftUI with Combine for reactive state
- **Auth:** Firebase Auth (email, phone OTP, Google Sign-In, 2FA)
- **Database:** Firestore (primary), Firebase Realtime Database (presence, typing indicators)
- **Storage:** Firebase Storage (profile photos, media)
- **Push:** Firebase Cloud Messaging (FCM)
- **Remote Config:** Firebase Remote Config (AI API keys, feature flags)
- **Search:** Algolia (via `AlgoliaSearchService.swift`)
- **In-App Purchases:** StoreKit
- **Media:** AkamaiMediaService for CDN

### Backend
- **Cloud Functions** (`functions/`): Node.js 24, Firebase Functions v7 (2nd gen). Handles notifications, moderation, auth, Berean AI, personalization.
- **Cloud Functions** (`cloud-functions/`): Node.js 20, Firebase Functions v5. Handles moderation and crisis detection.
- **Cloud Run** (`cloud-run/feed/`): Express + TypeScript. Server-side feed ranking.
- **Cloud Run** (`cloud-run/search/`): Express + TypeScript. Semantic search via Vertex AI embeddings.
- **Genkit** (`genkit/`): AI-powered Bible study server using Google Generative AI.
- **GCP Services:** Vertex AI (embeddings, generative), Cloud Vision (image moderation), Cloud Natural Language.

### Firebase Config
- **Project:** `amen-5e359` (see `.firebaserc`)
- **Firestore:** `(default)` database, `nam5` location
- **Storage:** `amen-5e359.firebasestorage.app`, `us-west1`
- **Rules:** `firestore.rules`, `AMENAPP/storage.rules`, `AMENAPP/database.rules.json`

## Architecture Patterns

### Singleton-heavy MVVM
The app uses a **singleton-heavy MVVM** pattern:
- **148 singleton services** accessed via `ServiceName.shared`
- ViewModels use `@StateObject` / `@ObservedObject` in views
- State flows via `@Published` properties and Combine
- `ContentView` is the root — manages tab navigation, auth state, badge counts
- `AMENAPPApp.swift` is the `@main` entry point; configures Firebase via `AppDelegate`

### Key Singletons to Know
- `PostsManager.shared` — Post CRUD, feed management, real-time listeners
- `FirebaseManager.shared` — Firebase client wrapper
- `AuthenticationViewModel` — Auth state, sign-in/out flows
- `NotificationService.shared` / `PushNotificationHandler` — In-app and push notifications
- `BlockService.shared` — User blocking logic
- `ModerationService.shared` / `ContentModerationService.shared` — Content safety
- `SessionTimeoutManager.shared` — Session/inactivity management
- `CacheManager.shared` — URL and data caching
- `BereanAnswerEngine.shared` — Scripture-grounded AI assistant

### Concurrency
- Modern Swift concurrency (`async/await`) used extensively (~287 files)
- Combine publishers for reactive UI updates (~144 files)
- `@MainActor` for UI-bound state
- `Task` blocks for async work launched from views
- Performance-conscious: URLCache pre-warmed to 64MB RAM / 256MB disk

### Navigation
- Tab-based navigation managed in `ContentView`
- `ContentViewModel` handles tab selection and deep linking
- `NotificationNavigationDestinations.swift` for notification-driven navigation
- `ChurchDeepLinkHandler` for church-related deep links

## Product/UX Standards
- Threads / Instagram-like UX behavior for notifications, messaging, and profile/follow flows
- Real-time updates should be consistent across the app
- No duplicate actions (posts, messages, follows, notifications)
- Private account / follow requests / blocking rules must be enforced everywhere
- Messages should drive Messages badge, not spam Notifications feed
- Fast, premium UX: smooth scrolling, responsive buttons, no lag

## UI / Motion Design Standards
- Liquid Glass design language
- `AmenColorScheme.swift` defines the app's color palette
- iOS-style animations: fast, subtle, premium
- `AnimationSystem 2.swift` / haptics via `HapticManager`
- Avoid heavy blur/material on every feed cell if it causes lag
- Buttons must have immediate pressed feedback and clear loading/disabled states
- Collapse/expand effects should be smooth and not jittery

## Engineering Standards
- Prefer targeted fixes over full rewrites
- Preserve existing product behavior unless explicitly asked to change it
- Single source of truth for shared UI state (e.g., follow state per author across all posts)
- Idempotent writes and safe retry behavior
- Avoid duplicate listeners and repeated fetch loops
- Keep heavy work off the main thread
- Use lazy rendering and pagination for large lists/chats/comments
- All files are flat in `AMENAPP/` — no subdirectory hierarchy for Swift sources
- Naming convention: `FeatureNameView.swift`, `FeatureNameService.swift`, `FeatureNameViewModel.swift`, `FeatureNameModels.swift`

## Reliability Requirements
- No crashes from rapid taps, poor network, background/foreground transitions
- No duplicate notifications (push/in-app/badge)
- Real-time listeners must not duplicate rows/items
- Loading/error/success states must be clear and recoverable

## Build & Deploy

### iOS App
- Open `AMENAPP.xcodeproj` in Xcode
- No CocoaPods or SPM Package.swift — dependencies managed via Xcode project settings (Firebase SDK likely added via SPM through Xcode)
- Build target: `AMENAPP`
- Test target: `AMENAPPTests`
- Extensions: `AMENShareExtension`, `AMENWidgetExtension`

### Cloud Functions
```bash
cd functions
npm install
firebase deploy --only functions
```

### Cloud Run Services
```bash
# Feed ranking
cd cloud-run/feed
npm install && npm run build
# Deploy via gcloud or Cloud Build

# Semantic search
cd cloud-run/search
npm install && npm run build
```

### Genkit AI Server
```bash
cd genkit
npm install
npm start
```

### Firebase Rules
```bash
firebase deploy --only firestore:rules
firebase deploy --only storage
firebase deploy --only database
```

## Testing
- Unit tests in `AMENAPPTests/` using XCTest
- Key test suites: `AuthSecurityTests`, `ReliabilityAuditTests`, `SafetyGateTests`, `ShabbatModeTests`
- Cloud Functions: `firebase-functions-test` available but minimal test coverage
- Run iOS tests: `Cmd+U` in Xcode or `xcodebuild test`

## Preferred Output Format for Audits
When auditing a feature, return:
1. P0 issues (crash, duplication, privacy leak, data loss)
2. P1 issues (lag, stale UI, broken flows)
3. P2 issues (polish/inconsistencies)
4. Root cause + targeted fix approach
5. Stress test script (step-by-step)
6. Acceptance criteria checklist

## Key Conventions for AI Assistants
1. **Read before editing** — Always read the file first. The flat file structure means names can be misleading.
2. **Check for duplicates** — Many files have `" 2"` copies; always edit the canonical (non-duplicate) version.
3. **Singleton access** — Use `ServiceName.shared` for existing services; don't create new instances.
4. **Firebase operations** — All Firestore/RTDB/Storage operations go through existing service singletons.
5. **No new files at root** — New Swift files belong in `AMENAPP/`, not at the repository root.
6. **Cloud Functions** — The primary functions directory is `functions/` (Node 24, v7). `cloud-functions/` is a secondary set for moderation.
7. **Test your assumptions** — With 148 singletons and 412 Swift files, features may be spread across multiple files. Search before modifying.
8. **Preserve behavior** — This is a production app with TestFlight users. Don't change existing behavior unless explicitly asked.

# AMEN Privacy Data Map
Generated: 2026-06-16 | Phase 6 Audit | Branch: feature/berean-island-w0

---

## Overview

AMEN is a faith-centered social network. This map summarises every data type
collected or processed, how it flows to storage and third parties, and the
consent path required before collection begins.

NSPrivacyTracking is `true` in PrivacyInfo.xcprivacy, meaning the app uses
data for cross-app tracking. ATT prompt is shown on first launch via
`ATTrackingManager.requestTrackingAuthorization`.

---

## Data Map Table

| Data Type | Collected? | Purpose | Storage | Retention | Third-Party | AI Provider | Consent Path |
|---|---|---|---|---|---|---|---|
| Display name | Yes (linked) | Profile, social graph | Firestore `users/{uid}` | Account lifetime | Firebase | None | Account creation |
| Email address | Yes (linked) | Authentication, account recovery | Firebase Auth | Account lifetime | Firebase | None | Account creation |
| Phone number | Optional (not linked) | SMS 2FA | Firebase Auth | Account lifetime | Firebase, Twilio (optional) | None | Opt-in at sign-in |
| Profile photo | Yes (linked) | Profile display | Firebase Storage `profileImages/` | Account lifetime | Firebase | None | Account creation |
| Posts / media | Yes (linked) | Social feed, community sharing | Firestore `posts/`, Storage `media/` | Account lifetime | Firebase | Anthropic Claude (content moderation), Google Vertex AI (Vision) | Post creation |
| Prayer requests | Yes (linked) | Prayer chain feature, AI-assisted prayer composition | Firestore `prayerChains/`, `churchReflections/` | Account lifetime | Firebase | Anthropic Claude (assemblePrayerChain CF) | `consentCreatorAI` UserDefaults gate + legal document in-app |
| Church notes / sermon audio | Yes (linked, on-demand) | Church Notes feature, voice transcription | Firestore + Storage | Account lifetime | Firebase | Google Speech-to-Text (SFSpeechRecognizer on-device) | Microphone + Speech permissions; feature flag `churchNotes_enabled` |
| Voice recordings | Optional (not linked) | Voice prayer capture, Berean voice queries | Storage `audio/` | Session + user lifecycle | Firebase | Google Speech (on-device) | Microphone permission dialog |
| Direct messages | Yes (linked) | Peer communication | Firestore `directMessages/{uid}/threads/` | Account lifetime | Firebase | Not routed to AI (BereanPersonalContextProvider explicitly excludes Tier P paths) | Recipient consent implied; DM feature is opt-in |
| Location (coarse) | Optional (not linked) | Church discovery, local community content | Not persisted; used transiently in-app | Session only | None | None | `NSLocationWhenInUseUsageDescription` dialog |
| Location (precise) | Optional (not linked) | Church proximity geofencing | CLCircularRegion in-memory; no Firestore persistence | Session only | None | None | `NSLocationWhenInUseUsageDescription` dialog |
| Contacts | Optional (not linked) | Emergency contact export (offline, on-device only) | On-device file only — explicitly user-exported | User action | None | None | `NSContactsUsageDescription` dialog; user-initiated export only |
| Calendar events | Optional (not linked) | Community events integration (IntegrationOS) | Not stored; read-only access | Session only | None | None | `NSCalendarsUsageDescription` dialog (added Phase 6) |
| Health / Fitness data | Optional (not linked) | Spiritual Rhythm OS wellness correlation | HKHealthStore local; summary in Firestore | Session / account lifetime (summary) | None | None | `NSHealthShareUsageDescription` dialog (added Phase 6) |
| Device ID / IDFA | Yes (linked, tracking) | Analytics, attribution | Firebase Analytics | Firebase retention policy | Firebase, Google | None | ATT dialog before IDFA access |
| Product interaction | Yes (linked, tracking) | Feature analytics, formation tracking | Firebase Analytics + Firestore `analytics/` | Firebase retention policy | Firebase, Google | None | ATT dialog |
| Crash data | Yes (not linked) | Stability / bug fixes | Firebase Crashlytics | Firebase retention policy | Firebase, Google | None | Privacy label disclosure only |
| Performance data | Yes (not linked) | App performance monitoring | Firebase Performance | Firebase retention policy | Firebase, Google | None | Privacy label disclosure only |
| Purchase history | Yes (linked) | Subscription tier (Amen+, AmenPro, etc.) | StoreKit + Firestore `entitlements/{uid}` | Account lifetime | Apple (StoreKit), Stripe (future) | None | StoreKit purchase flow |
| Search history | Optional (not linked) | In-app scripture / content search | Local only (not persisted to Firestore) | Session only | Algolia (search queries) | None | Implied by feature use |
| Berean AI session / query metadata | Yes (linked) | AI quality, safety monitoring | Firestore `bereanPipelineTraces/`, `bereanFeedback/` | 90-day rolling (by design) | Firebase | Anthropic Claude | `consentCreatorAI` UserDefaults gate |
| Spiritual formation journal | Yes (linked) | Reflection, midweek reminder | Firestore `churchReflections/{uid}` | Account lifetime | Firebase | Anthropic Claude (generateReflectionSeedFromNotes CF, on-demand only) | Feature is opt-in; individual AI call is on-demand |
| User ID | Yes (linked) | Authentication, all feature operations | Firebase Auth + Firestore | Account lifetime | Firebase | None | Account creation |

---

## Third-Party SDK / API Summary

| Provider | Purpose | Data Received | Data Sent Offshore? | Docs |
|---|---|---|---|---|
| Firebase / Google | Auth, Firestore, Storage, Analytics, Crashlytics, Push, Remote Config | All platform data | Yes (Google infra) | Firebase Privacy |
| Anthropic (Claude) | Berean AI pipeline, prayer chain assembly, content moderation | User queries, post text, prayer content (consent-gated) | Yes (Anthropic API) | anthropic.com/privacy |
| OpenAI (GPT) | Daily verse generation (generateDailyVerse CF) | Date + holiday context only; no PII | Yes (OpenAI API) | openai.com/privacy |
| Google Vertex AI | Video content explanation, Vision content moderation | Video frames, post images | Yes (Google Cloud) | cloud.google.com/privacy |
| Apple (StoreKit) | In-app purchases, subscription management | Purchase events | No (on-device) | apple.com/privacy |
| Algolia | Scripture and content search | Search queries (no PII) | Yes (Algolia infra) | algolia.com/privacy |
| Spotify | Music integration (IntegrationOS) | Music playback metadata | Yes (Spotify API) | spotify.com/privacy |
| LiveKit | Real-time audio/video in Spaces | Audio/video streams | Yes (LiveKit infra) | livekit.io/privacy |

---

## AI Provider Disclosure Status

| Surface | AI Provider | Consent Gate | UI Disclosure |
|---|---|---|---|
| Berean Pipeline (Ask/Discern/Build/Guard/Reflect) | Anthropic Claude | `consentCreatorAI` UserDefaults; throws `BereanError.consentRequired` if absent | `AIDisclosureSheet` bottom sheet; `AILabelPill` on all AI-generated content |
| Berean Chat Proxy (stream) | Anthropic Claude | Same `consentCreatorAI` gate upstream | AI indicator in chat UI |
| Daily Verse generation | OpenAI GPT | Feature-level (no explicit per-user gate beyond feature flag) | No per-call disclosure — **YELLOW item** |
| Prayer Chain Assembly | Anthropic Claude | `AMENFeatureFlags.shared.prayerChains` flag; no per-user AI consent check | No UI disclosure on prayer chain AI step — **YELLOW item** |
| Church Reflection AI summary | Anthropic Claude (via CF) | On-demand — user taps "Generate AI summary" button | Button label implies AI use; no explicit provider disclosure |
| Video content explanation | Anthropic Claude Haiku | Firebase App Check; no explicit user consent | No per-call UI disclosure — **YELLOW item** |

---

## Consent Architecture

- **Primary gate:** `consentCreatorAI` (`UserDefaults` key), toggled in Settings > AI & Privacy (`PrivacySettingsView`). Read by `BereanPipelineClient` and `AmenAIFeaturesService` before any Berean AI call.
- **ContextBus consent edges:** `ConsentStore` (Core/Consent/) manages granular edges (e.g. `activityToRhythm`, `notesToMatching`). All edges default OFF except `activityToRhythm`.
- **Legal document:** `AmenLegalDocumentModels.swift` contains in-app Privacy Policy stating AI features require explicit opt-in; consent revocable from Settings > AI & Privacy.
- **Missing:** Prayer chain assembly CF (`assemblePrayerChain`) and daily verse generation CF (`generateDailyVerse`) do not check a per-user AI consent flag server-side.

---

## Notes and Gaps

1. `NSCalendarsUsageDescription` was absent from `AMENAPP/Info.plist` despite `EventKitCalendarAdapter` requesting full calendar access — **added in Phase 6 GREEN fix**.
2. `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` were absent despite `HealthKitAdapter` calling `requestAuthorization` — **added in Phase 6 GREEN fix**.
3. `NSPrivacyTracking` is `true` in PrivacyInfo.xcprivacy but the tracking domains list (`app-measurement.com`, `firebaselogging.googleapis.com`, `firebase.googleapis.com`) does not include `algolia.net` or LiveKit domains — should be reviewed if those SDKs are listed in App Store Connect.
4. `generateDailyVerse` CF calls OpenAI with date/holiday context only (no PII), but no user-facing disclosure exists.
5. `assemblePrayerChain` CF sends prayer text (user-authored) to Anthropic without a server-side consent gate check — only gated by a feature flag.

# AMEN iOS App — Configuration & Feature Flags

**Configuration Sources:** AppConfig.swift, Remote Config (Firebase), Info.plist, Hardcoded constants  
**Last Updated:** 2026-06-07  

## Feature Flags (Remote Config)

**Namespace:** Firebase Console → AMEN-5e359 project → Remote Config

| Key | Type | Default | Purpose | Lifecycle |
|-----|------|---------|---------|-----------|
| `enable_berean_formations` | Boolean | true | Toggle daily formation cards | Always A/B test |
| `enable_sabbath_mode` | Boolean | true | Toggle Sabbath/Sunday focus | Always on (production) |
| `enable_simple_mode` | Boolean | true | Toggle accessibility mode | Always on |
| `enable_spaces` | Boolean | true | Toggle Spaces feature (connect hubs) | Always on (production) |
| `enable_catalog` | Boolean | true | Toggle catalog/knowledge network | Always on (production) |
| `enable_live_sessions` | Boolean | true | Toggle AMEN Live streaming | Always on |
| `max_posts_per_day` | Number | 10 | Daily posting limit (free tier) | Rate control |
| `max_dm_per_hour` | Number | 30 | DM rate limit | Rate control |
| `post_character_limit` | Number | 5000 | Max post length | Content gating |
| `comment_character_limit` | Number | 1000 | Max comment length | Content gating |
| `prayer_character_limit` | Number | 2000 | Max prayer request length | Content gating |
| `notification_batch_size` | Number | 5 | Notifications per batch | Backend optimization |
| `feed_pagination_size` | Number | 20 | Posts per feed page | Performance tuning |

## SKU & Pricing Configuration

### iOS In-App Purchases (StoreKit 2)

**Product IDs:**
- `com.amen.pro.monthly` — $9.99/month (or regional equivalent)
  - Includes: Unlimited posts, Berean assistant calls
  - Region: US only (Stripe for global)
- `com.amen.pro.yearly` — $79.99/year (or regional equivalent)
  - Same features as monthly
  - Region: US only
- `com.amen.pro.lifetime` — $199.99 one-time
  - Permanent unlock (no recurrence)
  - Region: US only
- `com.amen.spaces.member.monthly` — $4.99/month
  - Space membership (1 space)
- `com.amen.spaces.founding.monthly` — $9.99/month
  - Founding member (unlimited spaces)

### Stripe SKUs (Fallback for non-US)

**Pricing Structure:**
- Base subscription: $9.99 USD/month equivalent
- Regional variants: Stripe manages currency conversion
- Discount: 30% off for annual commitment (auto-applied)
- Commission rate: TBD (Stripe handles)

**Entitlement Mapping:**
- `premiumTier: "PRO"` → corresponds to monthly/yearly/lifetime
- `hasPlusAccess: true` → allows Berean+ features
- `hasProAccess: true` → allows Pro-only features (live studio, creator analytics)

## Numeric Limits & Rate Limits

### Content Limits (AppConfig.swift, PostValidator.swift)

| Limit | Value | Enforced By | Notes |
|-------|-------|-------------|-------|
| Post character limit | 5000 | Firestore rule I-5 + AppConfig | Hard cap on creation |
| Comment character limit | 1000 | AppConfig | UI validation, not rule-enforced |
| Prayer request length | 2000 | AppConfig | UI validation |
| Church note length | 10000 | AppConfig | Sermon notes longer |
| Profile bio length | 500 | AppConfig | Bio field |
| Hashtag limit per post | 10 | PostViewModel | Max hashtags |
| Mention limit per post | 20 | PostViewModel | Max @mentions |
| Image attachments per post | 5 | AppConfig | Max media items |
| Video length per post | 10 minutes | AppConfig | Max video duration |
| Audio length per post | 30 minutes | AppConfig | Max audio duration |

### Rate Limits (AppConfig.swift, rateLimiter.js)

| Limit | Value | Window | Enforced At | Consequence |
|-------|-------|--------|-------------|-------------|
| Posts per user | 10 | 24 hours | Client + CF | Post blocked until window expires |
| Comments per user | 50 | 1 hour | CF rate limiter | 429 Too Many Requests |
| DMs per user | 30 | 1 hour | CF rate limiter | DM blocked |
| Reactions per post | 1 per user | Instant | AppConfig | Deduplicated client-side |
| Report submissions | 5 | 24 hours | CF rate limiter | Report rejected |
| Account creation | 1 per email | Instant | Firebase Auth | Duplicate email error |
| Sign-in attempts | 5 failed | 15 minutes | Firebase Auth | Account locked (security hold) |
| 2FA code attempts | 3 failed | 24 hours | twoFactorAuth.js | 2FA locked |
| Phone auth | 3 attempts | 24 hours | phoneAuthRateLimit.js | Phone blocked |

### Cache & Performance

| Setting | Value | File | Notes |
|---------|-------|------|-------|
| URL cache memory | 200 MB | AppConfig.swift | URLCache.shared init |
| URL cache disk | 500 MB | AppConfig.swift | URLCache.shared init |
| Feed page size | 20 posts | AppConfig.swift | Pagination batch size |
| Notification batch size | 5 notifications | Remote Config | Batched delivery |
| Session timeout | 15 minutes | SessionTimeoutManager | Logout after inactivity |
| FCM token refresh | On auth change | AppDelegate.swift | Token write to Firestore |
| Firestore offline cache | Enabled | AppDelegate.init() | Persistent local cache for reads |
| Image optimization | 80% JPEG quality | MediaService | Compression on upload |

## Hardcoded Constants

### Background Tasks

| Identifier | Purpose | File |
|-----------|---------|------|
| `com.amen.app.refresh` | Feed refresh (registered in Info.plist) | BGTaskScheduler in AMENAPPApp.swift |
| `com.amen.app.notification-batch` | Batch notifications (if implemented) | (future) |

### Color Tokens (AmenColorScheme.swift, purged for system colors)

**Migration (C3 Design Contract):** All custom brand colors replaced with system colors
- `amenDarkPrimary` → `Color.systemGroupedBackground`
- `amenDarkSecondary` → `Color.systemGroupedBackground`
- `amenDarkTertiary` → `Color.systemGroupedBackground`
- `amenGold` → `Color.systemBlue` (system accent)
- `cosmic` gradients → Removed (no longer used)

**Retained:** Text color tokens (primary, secondary, tertiary, quaternary) now adaptive via AmenTheme

### Age Tiers (Firestore rules, MinorSafetyService.swift)

| Tier | Age Range | Restrictions |
|------|-----------|--------------|
| `under_minimum` | < 13 (US COPPA) | Completely blocked (no posts, no DMs, no spaces) |
| `teen` | 13-17 (US) | Private by default, public posts require confirmation, no jobs, mutual-follow DM gate |
| `adult` | 18+ | Full access |
| (EU variant) | < 16 (GDPR-K) | May apply stricter rules (TBD by T&S Lead) |

**OPEN-1 (Firestore rules §6):** EU GDPR-K may require raising teen threshold from 13 to 16 for some data categories

### Minor Safety Guards

| Guard | Enforced By | Effect |
|-------|-------------|--------|
| Public post confirmation | Firestore rule I-3 (client + CF) | Minors must set `publicConfirmed=true` before posting publicly |
| Discussion privacy | Firestore rule (onCreate check) | Minors cannot post public discussions (default private) |
| Prayer privacy | Firestore rule (onCreate check) | Minors' prayers default to private (can be church/space) |
| Space verification | Firestore rule (ContentView gate) | Minors can only join church-verified spaces |
| DM mutual-follow | Firestore rule C-MINOR-DM | Minors can only DM mutual-followers |
| Job hiding | Firestore rule I-5 (read denied) | Minors cannot read /jobs collection |
| Connector access | Firestore rule B-3 | Minors cannot access Berean connectors (integrations) |

## Feature Gating (A/B Tests & Experiments)

### Satellite Tests (Remote Config)

| Experiment | Key | Variants | Duration |
|-----------|-----|----------|----------|
| Feed ranking algo | `feed_ranking_v2_rollout` | baseline (legacy), v2-ranked | ongoing |
| Intelligence brief timing | `digest_delivery_time` | immediate, daily-9am, weekly | 4 weeks |
| Spaces monetization | `spaces_paywall_enabled` | control, variant (paywall on) | 8 weeks |

## Integration Keys & Environment Variables

### Stored in Remote Config (Production)

| Key | Usage | Rotation Policy |
|-----|-------|-----------------|
| `stripe_secret_key` | Stripe payment processing | Quarterly (automatic) |
| `stripe_signing_secret` | Webhook verification | Quarterly (automatic) |
| `ncmec_api_key` | NCMEC CyberTipline reporting | Annual (manual) |
| `algolia_app_id` | Search indexing | As needed |
| `algolia_api_key` | Search indexing (write-only) | As needed |

### Stored in .env.local (Local Emulator, Gitignored)

```bash
# Copy to .env.local for local emulator testing
# .env.local is gitignored — NEVER commit
BEREAN_LLM_KEY=your-gemini-api-key-here
EMBEDDING_KEY=your-gemini-api-key-here
```

### Hardcoded in Source (Search Conducted)

**Finding:** NO API keys found hardcoded in Swift source or public JavaScript files  
**Verification:** 
- Grepped for "secret", "key", "token" → only comments and Remote Config references found
- Stripe keys are ONLY in Remote Config, never in APK/source
- Firebase project ID is in GoogleService-Info.plist (public, expected)

## Entitlements (AMENAPP.entitlements)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>aps-environment</key>
  <string>production</string>  <!-- Push Notifications -->
  <key>com.apple.developer.applesignin</key>
  <array>
    <string>Default</string>
  </array>  <!-- Sign in with Apple -->
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>applinks:amenapp.com</string>  <!-- Universal Links -->
  </array>
  <key>com.apple.developer.usernotifications.communication</key>
  <true/>  <!-- Focus Mode -->
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.com.amenapp</string>  <!-- Notification Extension, Widgets -->
  </array>
</dict>
</plist>
```

## Info.plist Configuration

**Key Settings:**
- **App Bundle ID:** com.amenapp
- **Version:** 1.0 (matches Firebase Remote Config app version checks)
- **Build Number:** Incremented per release (CI/CD managed)
- **Minimum iOS Version:** 15.0 (SwiftUI + async/await requirement)
- **Background Modes Enabled:** 
  - Remote Notification (push)
  - Background Fetch (manual feed refresh)
- **BGTaskSchedulerPermittedIdentifiers:**
  - com.amen.app.refresh (declared + registered at runtime in AMENAPPApp.init)

---

## Routing & Navigation Config

### Deep Link Schemes

| Scheme | Handler | Target |
|--------|---------|--------|
| `amenapp://` | NotificationDeepLinkRouter | Routes to post/prayer/user/etc based on query params |
| `com.amenapp://` | Same | Alias scheme for Apple ecosystem |
| Universal Links | applinks:amenapp.com | AASA file on domain, routes to content |

### Push Notification Routing

**Service:** NotificationDeepLinkRouter.shared + NotificationTapBootstrapper

| Notification Type | Route | Deep Link |
|------|-------|-----------|
| New post from follower | PostDetailView | `/posts/{postId}` |
| New comment | PostDetailView (scroll to comment) | `/posts/{postId}#comment-{commentId}` |
| New prayer response | PrayerDetailView | `/prayers/{prayerId}` |
| New message | ConversationView | `/conversations/{conversationId}` |
| Follow notification | ProfileView | `/users/{userId}` |
| Church activity | ChurchDetailsView | `/churches/{churchId}` |
| Space event | SpaceDetailsView | `/spaces/{spaceId}` |
| Formation card ready | WhatNeedsAttentionView (intelligence tab) | `/intelligence?card={cardId}` |

---

## Compliance & Legal

### GDPR/CCPA Configuration

- **Data Subject Rights:** deleteAccount() + auditTrail/{uid}/events/{eventId} (append-only)
- **Consent Tracking:** stored in users/{uid}/consents (NOT user preferences — consent records)
- **Right to Be Forgotten:** 30-day grace period before permanent deletion (accountDeletion.js)

### COPPA (US Minors)

- **Age Gate:** hasCompletedAgeVerification (@AppStorage, persistent across launches)
- **Threshold:** 13 years (US COPPA floor)
- **EU Override:** GDPR-K may require 16 (T&S Lead must configure)

### NCMEC CyberTipline

- **Automation:** CSAM detection → ncmecReporter.js → automatic filing (no human gate)
- **Mandatory Reporting:** Set by US law, not configurable
- **Log:** crisisEscalations/{uid}/{ts} (human-readable timestamp)

---

## Summary

- **Feature Flags:** 13 boolean/numeric flags in Remote Config
- **SKUs:** 5 IAP product IDs (iOS) + Stripe fallback (global)
- **Rate Limits:** 9 active limits (posts, DMs, reports, auth attempts, etc)
- **Hardcoded Limits:** 15+ character/length limits in AppConfig
- **Age Tiers:** 3 tiers (under_minimum, teen, adult) + EU variant TBD
- **Integration Keys:** 0 hardcoded, 5 in Remote Config, 2 in .env.local (emulator only)
- **NO P0 Secrets Found:** All keys are in gitignored files or Remote Config


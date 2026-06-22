# Implementation Audit — Berean Chat + Platform Infrastructure

Date: 2025-02-14
Scope: Berean chat experience + platform-wide Action Threads / Compound Identity Graph / Proof of Human + Proof of Care.

## Berean Chat (Current State)

### Primary View
- `AMENAPP/AMENAPP/BereanChatView.swift`
  - Owns `BereanChatViewModel` (message list, streaming, Firestore persistence).
  - Message streaming via `ClaudeService.shared.sendMessage(...)` with per-token updates.
  - `ScrollView` with `ScrollViewReader` + `PreferenceKey` for scroll offset.
  - Auto-scrolls to bottom on `messages.count` and `messages.last?.content` changes (can yank user during manual scroll).
  - Hero section + quick action cards on empty state.
  - Header is already scroll-reactive (blur intensity based on `scrollOffset`).
  - Input uses `BereanFocusedComposer` when `AMENFeatureFlags.shared.bereanChatRedesignEnabled` is true; otherwise uses a compact composer in the same file.

### Existing Composer / Liquid Glass Systems
- `AMENAPP/AMENAPP/BereanFocusedComposer.swift`
  - Current “enhanced” composer in BereanChatView. Static glass pill, no scroll-aware compression.
- `AMENAPP/AMENAPP/BereanLiquidComposerView.swift`
  - Safari-like liquid composer, has scroll-aware compact mode via `BereanComposerState`.
- `AMENAPP/AMENAPP/BereanEnhancedComposerWrapper.swift`
  - Integrates Liquid Glass composer with follow-up suggestions and response mode chips.
  - Uses `BereanComposerViewModel` for scroll/compact state.
- `AMENAPP/AMENAPP/BereanComposerState.swift`
  - State machine for composer: idle/focused/typing/scrollingCompact/streaming/etc.
  - `updateScroll(_:)` provides compacting logic.
- `AMENAPP/AMENAPP/BereanDesignSystem.swift`
  - Liquid Glass modifiers and tokens for consistent white/black theme.

### Existing Study/Reasoning/Structured Content
- `AMENAPP/AMENAPP/BereanStructuredResponseView.swift`
- `AMENAPP/AMENAPP/BereanStructuredCardView.swift`
- `AMENAPP/AMENAPP/BereanFollowUpChips.swift`
- `AMENAPP/AMENAPP/BereanSuggestionChipsView.swift`
- `AMENAPP/AMENAPP/BereanScriptureCitationViews.swift`
- `AMENAPP/AMENAPP/BereanStructuredResponseView.swift`
  - These can be reused for Study Mode surfaces and post-response actions without replacing existing message rendering.

### Services / Integration
- `ClaudeService.swift` (streaming response).
- `Berean*` services: `BereanCoreService`, `BereanOrchestrator`, `BereanConversationService`, `BereanIntentRouter`, `BereanIntegrationService`, `BereanAnswerEngine`, `BereanConversationSafetyService`.
- Feature flags: `AMENFeatureFlags`.

### Key Constraints Found
- Auto-scroll logic is aggressive; will yank on token streaming.
- Scroll offset updates via `PreferenceKey` on entire content can be chatty.
- `BereanChatView` owns a large amount of UI. Modularization needed to add Study Mode surface without re-architecture.

## Platform Infrastructure (Existing Systems)

### Safety / Moderation / Trust
- `AntiHarassmentEngine.swift`
- `ConversationRiskEngine.swift`
- `AMENTrustScoreService.swift`
- `SafetyOrchestrator.swift`, `ModerationService.swift`, `ContentModerationService.swift`, `ContentSafetyShieldService.swift`, `SafetyPolicyFramework.swift`
- `MessageSafetyGateway.swift`, `AMENMessageSafetyEngine.swift`, `SafeMessagingService.swift`
- These provide baseline policy, safety, and risk scoring mechanics to integrate with Proof of Human/Care and Action Threads.

### Social / Post / Comment Services
- `PostCard.swift`, `PostDetailView.swift`, `CreatePostView.swift`
- `PostCardServices.swift`, `FirebasePostService.swift`, `CommentService.swift`
- Notifications: `NotificationService.swift` (if present), `SmartNotificationRouter.swift`
- Existing flows for prayer/testimony: `PrayerToActionCompanion.swift`, `TestimoniesView.swift`, `SpiritualCheckInService.swift`

### Existing Feature Flags / Config
- `AMENFeatureFlags.swift` for staged rollouts.
- Firestore rules: `AMENAPP/AMENAPP/firestore 18.rules`

## Reuse Candidates
- Berean composer system (`BereanLiquidComposerView`, `BereanComposerViewModel`, `BereanEnhancedComposerWrapper`).
- Liquid glass modifiers in `BereanDesignSystem.swift`.
- Existing safety engines + trust scoring services for Proof of Human/Care foundation.
- Existing follow-up chips and structured response components for Study Mode evidence surfaces.

## Gaps For Requested Work
- No existing Study Mode evidence surface (structured reasoning UI) in BereanChatView.
- No wallpaper manager/contrast engine used in Berean chat.
- Scroll state coordination is ad-hoc; needs a coordinator to avoid jitter and yanking.
- No Action Threads domain models or services found.
- No Compound Identity Graph model/service found.
- No Proof of Human/Proof of Care internal scoring pipeline found.

## Do Not Touch (Without Explicit Approval)
- Any existing post/feed UI or navigation structure.
- Existing safety policies and moderation enforcement order.
- Existing backend contracts for chat streaming, unless strictly required.

## Proposed Next Steps (Pending Approval)
1) Berean Chat enhancement pass (UI + behavior changes).
2) Action Threads + Compound Identity Graph + Proof of Human/Care domain model + service layer (no UI changes yet, feature-flagged).

Note: UI changes require explicit approval per operating rules. I will request approval before any visible UI changes.

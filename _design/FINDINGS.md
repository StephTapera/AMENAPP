# Findings — Design Audit Pass 2026-05-30

Populated by Phase 1 domain agents. Source of truth: MANIFEST.md · DESIGN-STANDARD.md

| Domain | Screen/Component | File:Line | Surface Type | Issue | Severity | Status |
|--------|-----------------|-----------|--------------|-------|----------|--------|
| Feed | HeyFeedControlsSheet | HeyFeedControlsSheet.swift:11 | overlay | Flat opaque background; no `.regularMaterial`; no reduce-transparency fallback | HIGH | QUEUE |
| Messages | LiquidGlassMessagesView | LiquidGlassMessagesView.swift:43 | hero-chrome | Partial glass; missing `accessibilityReduceTransparency` fallback on primary surface | HIGH | QUEUE |
| Wellness | BreathingExerciseView | BreathingExerciseView.swift:76 | hero-chrome | Full-screen hero with no glass chrome; no `.lightContent` status bar; no reduce-transparency | HIGH | QUEUE |
| Wellness | MovementWellnessView | MovementWellnessView.swift:59 | hero-chrome | Same pattern as BreathingExerciseView — no glass header, no status bar spec | HIGH | QUEUE |
| Crisis | CrisisSupportCard | CrisisSupportCard.swift:15 | hero-chrome | No glass on any surface; opaque fills; no accessibility fallbacks | HIGH | QUEUE-GUARDIAN |
| Wellness | WellnessSupportSheet | WellnessRiskLayer.swift:895 | hero-chrome | Partial glass; no reduce-transparency fallback | HIGH | QUEUE-GUARDIAN |
| Crisis | WellnessCrisisSheet | WellnessRiskLayer.swift:952 | hero-chrome | Partial glass; no reduce-transparency fallback; GUARDIAN-critical path | HIGH | QUEUE-GUARDIAN |
| Feed | PersonalizedGreetingView | PersonalizedGreetingView.swift:137 | hero-chrome | Uses solid `Color(.systemGray6)` background instead of `.ultraThinMaterial`; no reduce-transparency | MEDIUM | Queued |
| Feed | SpotlightCard | SpotlightCard.swift:314 | reading-surface | Dark glass card (`Color(white:0.14)` fill) — hardcoded opaque substituting for material; no reduce-transparency fallback | MEDIUM | Queued |
| Feed | PostDetailView | PostDetailView.swift:15 | hero-chrome | Hero header present but status bar not forced `.lightContent`; legibility scrim missing | MEDIUM | Queued |
| Inbox | AMENInbox List | AMENInbox.swift:1 | hero-chrome | Hero header uses partial glass; `accessibilityReduceTransparency` partially wired but not on all sub-surfaces | MEDIUM | Queued |
| Chat | ModernChatInputBar | MessagingComponents.swift:614 | control | `.background(Color(.systemGray6))` — opaque fill; should be `.ultraThinMaterial` capsule | MEDIUM | Queued |
| Chat | DiaChatView | MessagingComponents.swift:806 | hero-chrome | Partial glass; `accessibilityReduceTransparency` partially wired | MEDIUM | QUEUE |
| Prayer | PrayerView Actions | PrayerView.swift:N/A | hero-chrome | Action row has no `accessibilityReduceTransparency` fallback | MEDIUM | Queued |
| Wellness | WellnessDetailView | WellnessDetailView.swift:3 | reading-surface | Flat `Color(.systemBackground)` used on card surfaces; `.thinMaterial` appropriate per spec | MEDIUM | Queued |
| Disaster | DisasterAlertCard | DisasterAlertCard.swift:78 | overlay | Glass present but no `accessibilityReduceTransparency` fallback | MEDIUM | Queued |
| Spaces | AmenSpacesDiscussionDiscoveryView | AmenSpacesDiscussionDiscoveryView.swift:127 | reading-surface | Glass used but no `accessibilityReduceTransparency` fallback | MEDIUM | Queued |
| Support | SupportChipsRow | SupportSurfaceIntegration.swift:278 | control | Chips use flat `Color(.systemGray5)` fill; should be `.ultraThinMaterial` capsule per control spec | MEDIUM | Queued |
| Berean | BereanLandingView Hero | BereanLandingView.swift:96 | hero-chrome | Hero chrome partial; legibility scrim needs gradient spec; statusBar behavior undefined | MEDIUM | Queued |
| Berean | BereanVoiceCompanionView | BereanVoiceCompanionView.swift:90 | overlay | Partial glass; some surfaces use opaque `Color(.tertiarySystemBackground)` | MEDIUM | Queued |
| Berean | BereanSelectionOverlay | BereanSelectionOverlay.swift | overlay | `.background(.ultraThinMaterial)` present but no `accessibilityReduceTransparency` fallback | MEDIUM | Queued |
| Berean | BereanPulseView | BereanPulseView.swift:144 | overlay | Glass orb animations fire with no `accessibilityReduceMotion` guard | MEDIUM | Queued |
| Church Notes | ChurchNotesView | ChurchNotesView.swift:125 | hero-chrome | Header chrome partially glass; toolbar controls use solid `Color(.systemGray6)` | MEDIUM | Queued |
| Church Notes | ChurchLiveModeView | ChurchLiveModeView.swift:166 | overlay | Dark overlay uses `Color(.systemGray6)` for pill buttons; should be `.ultraThinMaterial` | MEDIUM | Queued |
| Berean | AmenSyncStudioView | AmenSyncStudioView.swift:72 | overlay | Partial glass; sheet doesn't use `.regularMaterial` per sheet spec | MEDIUM | Queued |
| Find Church | ChurchHeroHeader (new) | FindChurchView.swift:6617 | hero-chrome | Hero added this session; `accessibilityReduceTransparency` fallback missing on glass circles | MEDIUM | Queued |
| Find Church | ChurchNotesOnboardingView | ChurchNotesOnboardingView.swift:214 | hero-chrome | Feature cards use `Color(.systemGray6)` instead of `.ultraThinMaterial` | MEDIUM | Queued |
| Find Church | GlassAIRecommendationModule | FindChurchGlassComponents.swift:671 | overlay | `.onAppear` animation has no `guard !reduceMotion else { return }` | MEDIUM | Queued |
| Legacy | LegacyStudioView | LegacyStudioView.swift:237 | hero-chrome | Header glass present; no `accessibilityReduceTransparency` fallback | MEDIUM | Queued |
| Legacy | FaithReelStudioView | FaithReelStudioView.swift:165 | hero-chrome | Dark glass cards with `Color(white:0.08)` fill; no reduce-transparency fallback | MEDIUM | Queued |
| Legacy | FaithReelMainCard | FaithReelStudioView.swift:145 | reading-surface | `Color(white:0.08)` fill — opaque dark background; should be `.thinMaterial` | MEDIUM | Queued |
| Creator | AmenCreatorKitHome | AmenCreatorKitHome.swift:12 | hero-chrome | Glass sections missing `accessibilityReduceTransparency` fallback | MEDIUM | Queued |
| CarPlay | BereanDriveSetupView | CarPlay/BereanDriveSetupView.swift:20 | form | Minimal glass; form uses `Color(.systemGray6)` rows; partial accessibility wiring | MEDIUM | Queued |
| AccessPass | AmenAccessPassLandingView | AmenAccessPassLandingView.swift:235 | overlay | Partial glass; no `accessibilityReduceTransparency` fallback on glass card | MEDIUM | Queued |
| AccessPass | AmenAccessRequestInboxView | AmenAccessRequestInboxView.swift:75 | list | List rows use `Color.white.opacity(0.05)` — non-adaptive in light mode | MEDIUM | Queued |
| Settings | SettingsView | SettingsView.swift:18 | form | Dark `Color(.systemGray6)` sections; no `accessibilityReduceTransparency` | MEDIUM | Queued |
| Glass Kit | AmenGlassSurface | AmenGlassComponents.swift:22 | overlay | Core shared component missing `accessibilityReduceTransparency` fallback — affects every caller | MEDIUM | Queued |
| Glass Kit | AmenGlassIconButton | AmenGlassComponents.swift:58 | control | Missing `accessibilityReduceTransparency` fallback | MEDIUM | Queued |
| Glass Kit | BereanActionChip | AmenGlassComponents.swift:107 | control | Missing `accessibilityReduceTransparency` fallback | MEDIUM | Queued |
| Glass Kit | AmenGlassButtonSystem | AmenGlassButtonSystem.swift:99 | control | Missing `accessibilityReduceTransparency` fallback on `AmenGlassTokens.resolve()` | MEDIUM | Queued |
| Feed | OpenTable Feed Header | OpenTableView.swift:88 | hero-chrome | Status bar not forced `.lightContent`; legibility scrim below spec (< 0.35 opacity) | MEDIUM | Queued |
| Shared | AmenGlass3DIcon | EmptyStateView.swift:34 | control | Glass icon uses hardcoded `Color(white:0.20)` fill instead of `.thinMaterial` | LOW | OK |
| Feed | PostCard | PostCard.swift:21 | list | `Color(.systemBackground)` row — correct; note: avoid switching to glass on feed cells (lag risk) | LOW | OK |
| Groups | GroupCatchUpView | GroupCatchUpView.swift:117 | overlay | Glass section missing `accessibilityReduceTransparency` — minor; single surface | LOW | Queued |
| Verge | VergeCreatorStudioView | VergeCreatorStudioView.swift:391 | overlay | Dark overlay; minor `accessibilityReduceTransparency` gap | LOW | Queued |
| Verge | VergeCreateRoomSheet | VergeCreateRoomSheet.swift:340 | overlay | Sheet uses `.regularMaterial` — OK; missing drag handle color token (`Color.tertiary` vs hardcoded) | LOW | Queued |
| Social | FollowButton | FollowButton.swift:148 | control | Partial glass — uses `Color.clear`; glass pill would improve but not required | LOW | OK |
| Tip | TipView | TipView.swift:29 | overlay | Dark overlay; `accessibilityReduceTransparency` present; corner radius 20 vs spec 24 | LOW | Queued |
| Messages | ModernMessageBubble | MessagingComponents.swift:141 | control | Message bubbles use glass — correct; `.thinMaterial` per Reading Surface rule | LOW | OK |
| Inbox | Inbox Empty State | AMENInbox.swift:462 | overlay | Glass present; reduce-transparency wired — OK | LOW | OK |
| Berean | BereanSelahModeView | BereanSelahModeView.swift:40 | hero-chrome | Minimal glass — appropriate per Reading Surface rule | LOW | OK |
| Selah | SelahScriptureReaderView | SelahScriptureReaderView.swift:137 | reading-surface | Reading surface — glass correctly NOT applied to body text; chrome glass OK | LOW | OK |
| Profile | ProfilePhotoEditView | ProfilePhotoEditView.swift:40 | overlay | Glass present and correctly wired | LOW | OK |
| Notifications | SmartNotificationBanner | SmartChurchNotifications.swift:154 | overlay | Correct glass spec; well-implemented | LOW | OK |

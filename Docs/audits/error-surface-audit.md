# Error Surface Audit — AMEN iOS SwiftUI App

**Audit Date:** May 28, 2026  
**Scope:** iOS 17.0+ deployment minimum  
**Reference Standard:** `/docs/audits/liquid-glass-standard.md`  
**Status:** Phase 0 Design Standard Canonical

---

## Summary

| Metric | Count |
|--------|-------|
| **Total Error Surfaces Catalogued** | 87 |
| **Conforms to Glass Design** | 8 |
| **Deviates (Custom Styling)** | 18 |
| **Missing Glass (Native/Plain Text)** | 61 |
| **Native `.alert()` Calls** | 58 |
| **Native `.confirmationDialog()` Calls** | 11 |
| **Custom Error/Empty State Views** | 15 |
| **Toast/Banner Implementations** | 3 |

### Verdict
**61% of error surfaces do NOT use the Liquid Glass design standard.** The app has conflicting error presentation patterns:
- ✅ New code uses `.amenAlert()` modal cards (glass-compliant)
- ❌ Majority of existing code uses native `.alert()` (no glass styling)
- ⚠️ Custom error views have **inconsistent design language** — some use `.amenGlassSurface`, others use plain `RoundedRectangle` fills

---

## High-Priority Offenders (Prioritized Fix List)

### Tier 1: High-Stakes Flows (Data Loss, Payments, Auth)

| File | Line | Trigger | Current | Issue | Priority |
|------|------|---------|---------|-------|----------|
| `CreatePostView.swift` | 1421 | Safety check rejection | `.alert("Safety check", ...)` | ⚠️ User revising post after AI rejection — needs glass card for prominence | **P0** |
| `CreatePostView.swift` | 1507 | Post publication error | `.alert(errorTitle, ...)` | ⚠️ Network/upload failure with retry — plain alert loses context | **P0** |
| `CreatePostView.swift` | 1528 | AI content rejection | `.alert("Share Your Own Voice", ...)` | ⚠️ Content policy violation — educational message needs emphasis | **P0** |
| `CreatePostView.swift` | 1634 | Draft recovery | `.alert("Recover Draft?", ...)` | ⚠️ Data preservation — user may accidentally reject draft loss | **P0** |
| `CreatePostView.swift` | 7465 | Custom tag paywall | `.alert("Custom tag limit reached", ...)` | ⚠️ Premium feature upsell — weak visual signal for upgrade flow | **P1** |
| `SignInView.swift` | 92 | Auth errors (injected via modifier) | `.alert()` in `AlertsModifier` | ⚠️ First-time auth failure — critical user impression | **P0** |
| `TwoFactorAuthView.swift` | TBD | 2FA setup errors | `.alert()` pattern (native) | ⚠️ Security-critical setup flow — confusion on error likely | **P0** |
| `CommunityCovenantView.swift` | 233 | Covenant agreement submission | `.alert("Error", ...)` | ⚠️ Onboarding gate failure — blocks user progression | **P0** |
| `StudioPaymentService.swift` | N/A (backend) | Stripe payout failure | Error enum only; UI TBD | ⚠️ Financial transaction failure — must use glass card | **P0** |

### Tier 2: Mid-Frequency User Flows

| File | Line | Trigger | Current | Issue | Priority |
|------|------|---------|---------|-------|----------|
| `PostDetailView.swift` | TBD | Comments fetch error | `commentsErrorView` | ⚠️ Inline error view — matches custom pattern | **P1** |
| `BereanChatView.swift` | 1146 | Attachments unavailable | `.alert("Attachments unavailable", ...)` | Plain alert; inconsistent with glass design | **P1** |
| `BereanChatView.swift` | 1151 | Voice input disabled | `.alert("Voice input is off", ...)` | Plain alert; low severity but inconsistent | **P2** |
| `BereanChatView.swift` | 1188 | Report confirmed | `.alert("Thank you", ...)` | Success alert — should use glass card for consistency | **P2** |
| `ReportContentView.swift` | 132 | Report submission success | `.alert("Report Submitted", ...)` | Success confirmation — plain alert, no glass | **P1** |
| `ReportContentView.swift` | 139 | Report submission error | `.alert("Error", ...)` | Generic error — no context on what failed | **P1** |
| `GroupChatCreationView.swift` | 134 | Group creation error | `.alert("Couldn't Create Group", ...)` | Plain alert; user loses chat context | **P1** |
| `SavedPostsView.swift` | 130 | Loading error | `.alert("Error", ...)` | Generic — no recovery suggestion | **P2** |
| `QuoteComposerView.swift` | 69 | Post composition error | `.alert("Unable to Post", ...)` | Plain alert; no retry mechanism | **P1** |

### Tier 3: Lower-Frequency / Informational

| File | Line | Trigger | Current | Issue | Priority |
|------|------|---------|---------|-------|----------|
| `AmenSpaceBannerRail.swift` | 842 | Banner save failed | `.alert("Could not save banner size", ...)` | Plain alert; no context on retry | **P2** |
| `PrayerSuggestedRailView.swift` | 44 | "Why am I seeing this?" | `.alert("Why am I seeing this?", ...)` | Explanatory modal — could use glass | **P3** |
| `PrivacyDashboardView.swift` | 133 | Data export requested | `.alert("Export Requested", ...)` | Success confirmation — plain | **P2** |
| `ResourcesView.swift` | 1987 | Open Bible App prompt | `.alert("Open Bible App?", ...)` | Navigation intent — plain OK/Cancel | **P3** |
| `ResourcesView.swift` | 2089 | Open Pray.com prompt | `.alert("Open Pray.com?", ...)` | Navigation intent — plain OK/Cancel | **P3** |
| `JobSearchView.swift` | 82 | Clear all filters | `.alert("Clear all filters?", ...)` | Destructive action — no glass emphasis | **P2** |
| `AccountLinkingView.swift` | 332 | Unlink account | `.alert("Unlink Account?", ...)` | Destructive intent — should use glass | **P1** |
| `AccountLinkingView.swift` | 345 | Account linking error | `.alert("Error", ...)` | Generic error; no actionable message | **P2** |
| `ChurchChemistryService.swift` | 183 | Contacts permission | `.alert("AMEN Connection Check", ...)` | System permission gate — plain alert | **P2** |
| `BereanToolbarExtras.swift` | 90 | Microphone access required | `.alert("Microphone Access Required", ...)` | System permission — plain alert | **P2** |
| `AMENAPPApp.swift` | 196 | Version update required | `.alert("Update Required", ...)` | Kill switch — critical user message | **P0** |

---

## Existing Glass-Compliant Surfaces (Do NOT Change)

These 8 surfaces already conform to the Liquid Glass standard:

| Component | Location | Pattern | Verdict |
|-----------|----------|---------|---------|
| `LiquidGlassAlert` | `LiquidGlass/LiquidGlassAlert.swift` | `.amenAlert()` modifier | ✅ **CANONICAL** |
| `CreatorEmptyStateView` | `Creator/Views/CreatorEmptyStateView.swift` | `.amenGlassSurface()` | ✅ Conforms |
| `BereanErrorBanner` | `BereanErrorView.swift` | `Color(red:green:blue:)` fill + border | ✅ Custom glass-like |
| `ToastNotificationView` | `ToastNotificationView.swift` | `.ultraThinMaterial` + accent border | ✅ Glass pattern |
| `ErrorBannerView` | `ErrorBannerView.swift` | `.ultraThinMaterial` implementation | ✅ Glass pattern |
| `SmartCommunitySearchErrorState` | `SmartCommunitySearch/SmartCommunitySearchErrorState.swift` | Button-focused layout | ⚠️ Deviates (uses system accent, not glass) |

---

## Deviating Patterns (Custom But Not Glass-Standard)

These 18 views have custom error styling but **do not match** the canonical glass tokens:

| Component | Location | Issue |
|-----------|----------|-------|
| `BereanPulseErrorStateView` | `AMENAPP/BereanPulse/BereanPulseErrorStateView.swift` | Custom icon color scheme; no glass material |
| `AmenConversationOSErrorView` | `AMENAPP/ConversationOS/AmenConversationOSSurfaces.swift` | Custom layout; diverges from glass spec |
| `AmenObjectHubErrorState` | `AMENAPP/ObjectHub/AmenObjectHubView.swift` | One-off error handling; not reusable |
| `ChatEmptyState` | `ChatIdentityCard.swift` | Inline empty state; no glass styling |
| `CommandPaletteErrorView` | `AMENAPP/CommunicationOS/AmenSmartCommandPaletteView.swift` | Feature-specific error view |
| Multiple `.confirmationDialog()` | Various files (11 total) | Native system dialogs; no glass treatment |
| Inline error `Text` | Multiple validation contexts | Raw red/orange text; no background container |

---

## Complete Error Surface Inventory

### By Category

#### 1. Native `.alert()` Calls (58 total)

**⚠️ These MUST migrate to `.amenAlert()`:**

```
ChurchChemistryService.swift:183 — "AMEN Connection Check"
GroupChatCreationView.swift:134 — "Couldn't Create Group"
SavedPostsView.swift:130 — "Error"
Creator/AMENCreatorHomeView.swift:77 — "Creator" error binding
Media/Faith/VersePicker.swift:78 — "Error"
AmenSpaceBannerRail.swift:842 — "Could not save banner size"
ReportContentView.swift:132 — "Report Submitted" (success)
ReportContentView.swift:139 — "Error"
PrayerSuggestedRailView.swift:44 — "Why am I seeing this?"
PrivacyDashboardView.swift:133 — "Export Requested"
ResourcesView.swift:1987 — "Open Bible App?"
ResourcesView.swift:2089 — "Open Pray.com?"
QuoteComposerView.swift:69 — "Unable to Post"
JobSearchView.swift:82 — "Clear all filters?"
CommunityCovenantView.swift:233 — "Error"
BereanChatView.swift:1146 — "Attachments unavailable"
BereanChatView.swift:1151 — "Voice input is off"
BereanChatView.swift:1188 — "Thank you" (success)
AMENAPPApp.swift:196 — "Update Required"
BereanToolbarExtras.swift:90 — "Microphone Access Required"
CreatePostView.swift:1421 — "Safety check"
CreatePostView.swift:1507 — errorTitle (dynamic)
CreatePostView.swift:1528 — "Share Your Own Voice"
CreatePostView.swift:1634 — "Recover Draft?"
CreatePostView.swift:7465 — "Custom tag limit reached"
CreatePostView.swift:7476 — "Could not create tag"
AccountLinkingView.swift:332 — "Unlink Account?"
AccountLinkingView.swift:345 — "Error"
[+ ~30 more in secondary features]
```

#### 2. Native `.confirmationDialog()` Calls (11 total)

**⚠️ These should use glass action sheets:**

```
Moderation/ModerationCaseDetailView.swift:29 — "Confirm Action"
TestimonyViralSheet.swift:159 — "Platform" picker
SuggestedAccountPeekSheet.swift:50 — "Unfollow @handle?"
Crisis/AnonCrisisPostCard.swift:19 — "Report this post"
ChatIdentityCard.swift:425 — "More Options"
MessagesViewFix.swift:77 — "Delete Conversation"
TestimoniesView.swift:1240 — "Delete this testimony?"
BereanChatView.swift:1113 — "Berean mode" picker
CreatePostView.swift:1084 — "Save Draft?" (hidden title)
WorkflowDetailView.swift:54 — "Delete workflow?"
[+ 1 more in secondary features]
```

#### 3. Custom Error State Views (15 total)

**Status:** Mixed. Some use glass patterns, others diverge.

```
✅ GLASS-ALIGNED:
  - CreatorEmptyStateView (uses .amenGlassSurface)
  - BereanErrorBanner (custom but glass-like)
  - ErrorBannerView (uses .ultraThinMaterial)
  - ToastNotificationView (glass material + accent border)

⚠️ DEVIATING:
  - BereanPulseErrorStateView — custom colors, no glass
  - AmenConversationOSErrorView — custom layout
  - AmenObjectHubErrorState — feature-specific
  - SmartCommunitySearchErrorState — system accent colors
  - ChatEmptyState — inline, no container
  - CommandPaletteErrorView — feature-specific
  - ActivityFeedView.feedErrorState — inline Text
  - ScriptureInsightView.scriptureErrorView — inline
  - PostDetailView.commentsErrorView — inline
  - AmenMediaErrorStateView — custom colors
```

#### 4. Toast / Banner Implementations (3 total)

```
✅ ToastNotificationView — uses .ultraThinMaterial, glass-aligned
✅ ErrorBannerView — uses .ultraThinMaterial, glass-aligned
⚠️ GuideMyFeedConfirmationToast — component exists, audit pending
```

#### 5. Empty State Views (20+ total)

**Status:** Highly scattered. No canonical pattern.

```
FOUND:
  - EmptyStateView (ComponentsSharedUIComponents.swift)
  - CreatorEmptyStateView (glass-aligned)
  - ChatEmptyState (inline, no glass)
  - TopicFeedView.emptyState (inline)
  - CreationEmptyState (AmenSyncStudioView.swift)
  - BereanPulseEmptyStateView (custom)
  - PinEmptyStateCard (Features/Profile/PinnedPosts)
  - Inline "No X" Text throughout (20+ places)
```

---

## Feature Area Breakdown

### Authentication & Onboarding (HIGH STAKES)

| View | Error Type | Current | Verdict |
|------|-----------|---------|---------|
| `SignInView.swift` | Email validation, password reset, OTP verification | `.alert()` via `AlertsModifier` | ❌ **MISSING GLASS** — first-time user impression |
| `TwoFactorAuthView.swift` | 2FA setup, verification errors | `.alert()` pattern (inferred) | ❌ **MISSING GLASS** — security-critical |
| `CommunityCovenantView.swift` | Agreement submission failure | `.alert("Error", ...)` line 233 | ❌ **MISSING GLASS** — onboarding gate |
| `DateOfBirthCollectionView.swift` | Age assurance validation | TBD (fullScreenCover) | ⚠️ Needs audit |
| `EmailVerificationGateView.swift` | Email verify gate error | TBD | ⚠️ Needs audit |

**Action Required:** Migrate all auth flows to `.amenAlert()` with proper error recovery messaging.

---

### Post Creation & Publishing (HIGH FREQUENCY)

| View | Error Type | Current | Verdict |
|------|-----------|---------|---------|
| `CreatePostView.swift` | AI safety checks, draft recovery, upload errors, tag limits | 5× `.alert()` calls | ❌ **MISSING GLASS** — data loss risk on draft recovery |
| `EditPostSheet.swift` | Post edit errors | TBD | ⚠️ Needs audit |
| `QuoteComposerView.swift` | Quote post composition | `.alert("Unable to Post")` | ❌ **MISSING GLASS** |
| `AmenSyncStudioView.swift` | Draft sync errors | Custom `CreationEmptyState` | ⚠️ Partially aligned |

**Action Required:** Update CreatePostView's 5 alerts; add retry affordance for network errors.

---

### Payments & Giving (HIGH STAKES)

| View | Error Type | Current | Verdict |
|------|-----------|---------|---------|
| `StudioPaymentService.swift` | Stripe errors: auth, invalid response, account status | Error enum defined; UI TBD | ❌ **MISSING GLASS** — must implement using `.amenAlert()` |
| `AmenCovenantPaywallView.swift` | Paywall purchase errors | TBD | ⚠️ Needs audit |
| `GivingIntentFlowView.swift` | Donation errors | TBD | ⚠️ Needs audit |
| `ManageSubscriptionView.swift` | Subscription management errors | TBD | ⚠️ Needs audit |

**Action Required:** All payment UX must use glass cards for error confirmation and success states.

---

### Social Interactions (MEDIUM FREQUENCY)

| View | Error Type | Current | Verdict |
|------|-----------|---------|---------|
| `BereanChatView.swift` | Attachments unavailable, voice disabled, report confirmed | 3× `.alert()` calls | ❌ **MISSING GLASS** |
| `ReportContentView.swift` | Report submit success/error | 2× `.alert()` calls | ❌ **MISSING GLASS** |
| `GroupChatCreationView.swift` | Group creation error | `.alert("Couldn't Create Group")` | ❌ **MISSING GLASS** |
| `CommentsView.swift` | Comment load/post errors | TBD | ⚠️ Needs audit |

**Action Required:** Migrate social interaction alerts to glass modals.

---

### Account & Settings (MEDIUM STAKES)

| View | Error Type | Current | Verdict |
|------|-----------|---------|---------|
| `AccountLinkingView.swift` | Unlink account, linking errors | 2× `.alert()` calls | ❌ **MISSING GLASS** |
| `AccountSettingsView.swift` | Password, email, account changes | TBD | ⚠️ Needs audit |
| `DeleteAccountView.swift` | Account deletion confirmation | TBD | ⚠️ Needs audit |
| `PrivacyDashboardView.swift` | Data export success | `.alert("Export Requested")` | ⚠️ Success alert, but plain |

**Action Required:** Destructive account actions should use glass cards with emphasis.

---

### Discovery & Search (LOW FREQUENCY, INFORMATIONAL)

| View | Error Type | Current | Verdict |
|------|-----------|---------|---------|
| `SmartCommunitySearchView.swift` | Search failure | `SmartCommunitySearchErrorState` | ⚠️ Custom view, not fully glass-aligned |
| `PostsSearchView.swift` | Search result errors | TBD | ⚠️ Needs audit |
| `DiscoverSearchComponents.swift` | Discovery errors | Inline `emptyState` | ⚠️ Needs glass treatment |

**Action Required:** Ensure all search error states use glass material background.

---

### Permissions & System (LOW-MEDIUM PRIORITY)

| View | Error Type | Current | Verdict |
|------|-----------|---------|---------|
| `ChurchChemistryService.swift` | Contacts permission | `.alert("AMEN Connection Check")` | ❌ **MISSING GLASS** |
| `BereanToolbarExtras.swift` | Microphone permission | `.alert("Microphone Access Required")` | ❌ **MISSING GLASS** |
| `NotificationPermissionView.swift` | Notification permission gate | TBD | ⚠️ Needs audit |

**Action Required:** System permission gates should use glass modals for consistency.

---

### App-Level / Critical (BLOCKER)

| View | Error Type | Current | Verdict |
|------|-----------|---------|---------|
| `AMENAPPApp.swift` | Version update required (kill switch) | `.alert("Update Required")` | ⚠️ **Plain but critical** — should use glass for emphasis |

**Action Required:** Kill switch alert should use `.amenAlert()` with clear "Update Now" CTA.

---

## Recommendations

### Immediate (P0)

1. **Migrate CreatePostView alerts (5)** → Use `.amenAlert()` with proper error recovery:
   - Safety check rejection: add "Edit & Continue" button
   - Post upload errors: add "Retry" button
   - Draft recovery: use destructive tone for "Discard" to prevent data loss

2. **Migrate auth flow (SignInView + TwoFactorAuthView)** → `.amenAlert()` for all error states

3. **Migrate CommunityCovenantView error** → `.amenAlert()` (onboarding gate)

4. **Implement StudioPaymentService UI** → Use `.amenAlert()` for all payment errors + success confirmations

5. **Update AMENAPPApp version alert** → `.amenAlert()` with high-prominence "Update Now" button

### Short-term (P1)

6. **Migrate all `.confirmationDialog()` calls (11)** → Use `.amenSmartSheet()` or custom glass action sheet component (design pending)

7. **Migrate BereanChatView alerts (3)** → `.amenAlert()` for consistency

8. **Migrate ReportContentView alerts (2)** → `.amenAlert()` with success confirmation

9. **Migrate social interaction alerts (GroupChat, etc.)** → `.amenAlert()`

10. **Migrate destructive account actions (Unlink, Delete)** → `.amenAlert()` with `.destructive` tone button

### Medium-term (P2)

11. **Audit and align all custom error state views** → Ensure consistent use of `.amenGlassSurface()` or `.ultraThinMaterial` + border pattern

12. **Create canonical empty state component** → Reuse `CreatorEmptyStateView` pattern across all "No X" surfaces

13. **Standardize inline validation errors** → Instead of raw `Text("Error...")`, wrap in glass card or use `.amenAlert()`

14. **Migrate permission gate alerts** → System permission requests should use glass modals

15. **Document error pattern** → Add section to Design Standard for consistency going forward

### Long-term (P3)

16. **Consider glass action sheet variant** → `.confirmationDialog()` replacements need design spec (similar to `.amenAlert()` but with horizontal button layout)

17. **Implement error recovery state machine** → Network errors should include context (retry count, offline detection) with glass UI

---

## Mapping: Which Alerts Must Become `.amenAlert()`

### Must Migrate (High Impact)

```swift
// ❌ Before (native alert)
.alert("Error", isPresented: $showError) {
    Button("OK") {}
} message: {
    Text(errorMessage)
}

// ✅ After (glass card)
.amenAlert(isPresented: $showError, config: LiquidGlassAlertConfig(
    title: "Something went wrong",
    message: errorMessage,
    icon: "exclamationmark.triangle",
    primaryButton: LiquidGlassAlertButton("OK", tone: .primary) {
        // handle dismiss
    }
))
```

### Pattern for Recoverable Errors

```swift
// ✅ Network error with retry
.amenAlert(isPresented: $showNetworkError, config: LiquidGlassAlertConfig(
    title: "Connection Lost",
    message: "Unable to post. Check your connection and try again.",
    icon: "wifi.slash",
    primaryButton: LiquidGlassAlertButton("Retry", tone: .primary) {
        retryPostPublish()
    },
    secondaryButton: LiquidGlassAlertButton.cancel {
        dismissError()
    }
))
```

### Pattern for Destructive Actions

```swift
// ✅ Account deletion with warning
.amenAlert(isPresented: $showDeleteConfirm, config: LiquidGlassAlertConfig(
    title: "Delete Account?",
    message: "This action cannot be undone. All your data will be permanently removed.",
    icon: "exclamationmark.triangle.fill",
    primaryButton: LiquidGlassAlertButton("Delete", tone: .destructive) {
        deleteAccount()
    },
    secondaryButton: LiquidGlassAlertButton.cancel()
))
```

---

## Files Requiring Migration (By Priority)

| Priority | Files | Estimated Alerts | Effort |
|----------|-------|------------------|--------|
| **P0** | CreatePostView, SignInView, TwoFactorAuthView, CommunityCovenantView, AMENAPPApp | 12 | High |
| **P1** | BereanChatView, ReportContentView, GroupChatCreationView, QuoteComposerView, AccountLinkingView, and 8 others | 25 | Medium |
| **P2** | AmenSpaceBannerRail, PrivacyDashboardView, JobSearchView, ResourcesView (2 alerts), and 12 others | 18 | Low-Medium |
| **P3** | Informational alerts, system permissions, minor flows | 6 | Low |
| **Audit Pending** | AmenCovenantPaywallView, GivingIntentFlowView, ManageSubscriptionView, CommentsView, AccountSettingsView, DeleteAccountView, NotificationPermissionView, and 6 others | ~15 | TBD |

---

## Consistency Checklist for Phase 1–9 Implementation

When migrating error surfaces to Liquid Glass, ensure:

- [ ] Use `.amenAlert()` modifier from `LiquidGlassAlert.swift` (do NOT create custom variants)
- [ ] Set appropriate `LiquidGlassAlertButton.Tone`:
  - `primary` (gold) for "Confirm" / "Retry" / "Continue"
  - `destructive` (red) for "Delete" / "Discard" / data loss
  - `dismiss` (glass) for "Cancel" / "Close"
  - `spiritual` (purple) for spiritual/affirmation actions
- [ ] Always provide an `icon` (system SF Symbol) for visual context
- [ ] Keep message text concise (<150 chars) and actionable
- [ ] For network errors, include "Retry" button; for unrecoverable, use single "OK" button
- [ ] Test on both light and dark modes; accessibility with reduced transparency
- [ ] Verify animations match `Motion.adaptive()` patterns from design standard

---

## Test Checklist

Before deploying error surface migrations:

```
[ ] Render all alerts in light mode (day and night backgrounds)
[ ] Render all alerts in dark mode
[ ] Test with reduce motion enabled
[ ] Test with reduce transparency enabled
[ ] Verify button tap target size (46pt minimum)
[ ] Verify text contrast ratios (WCAG AA min 4.5:1)
[ ] Test rapid alert dismissal (edge case: user fast-taps)
[ ] Verify no layout overflow on smaller devices (iPhone SE)
[ ] Test with long error messages (100+ chars)
[ ] Verify animation timing matches design standard (0.34s spring)
```

---

## Appendix: Files by Error Surface Type

### Inline Validation Text (No Container)
- Multiple instances in form views (sign-up, profile edit, etc.)
- **Action:** Wrap in glass card or use error alert instead

### Empty State Views (20+ locations)
- TopicFeedView, SavedPostsView, DraftsView, EmptyFeedView, etc.
- **Status:** Inconsistent — some use plain Text, others use custom structs
- **Action:** Standardize on `CreatorEmptyStateView` pattern (uses `.amenGlassSurface()`)

### Modal Sheets with Errors (Custom Overlays)
- DateOfBirthCollectionView (fullScreenCover)
- Various bottom sheets with internal error states
- **Action:** Audit and apply glass material to sheet backgrounds

---

**Document Created:** May 28, 2026  
**Audit Completed By:** Error Surface Audit Agent  
**Next Review:** After Phase 1 implementation (estimated July 2026)

---

**End of Audit Document**

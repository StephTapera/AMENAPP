# Frontend Wiring & Dead Code Audit

**Date:** 2026-05-28  
**Auditor:** Claude Sonnet 4.6  
**Branch:** audit/2026-05-28  
**Files read:** ~45 Swift source files + backend functions directory

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| `Features/MessageActions/MessageActionService.swift:102-179` | **Blocker** | Stub service — all actions throw `.notImplemented` | `FirebaseMessageActionService` (the shared singleton used in production) is a 25-method stub. Every message action (react, copy, save, forward, pray, mute, edit, delete, report) throws `MessageActionError.notImplemented`. Users who tap any message context-menu action get an error. |
| `Spaces/Shell/SpaceDetailView.swift:316-326` | **Blocker** | Placeholder tab destination | `.bibleStudy` and `.announcement` Space types show `Text("Study coming from Agent D")` and `Text("Announcements")` as their body. No view behind these tab destinations. |
| `Spaces/Shell/SpaceDetailView.swift:342-343` | **High** | Empty NavigationLink destination | "Manage Space" toolbar button navigates to `EmptyView()`. Space settings page does not exist. |
| `Spaces/Chat/ThreadDetailView.swift:343-345` | **High** | Placeholder purchase sheet | Unlock sheet for paid Spaces shows `Text("Purchase sheet coming in Agent E.")` instead of `SpacesPurchaseSheet`. |
| `Spaces/Shell/SpacesListView.swift:106-108` | **High** | TODO unlock wiring | `LockedPreviewShell`'s `onUnlock` closure just sets `lockedSpaceTarget = nil` (dismisses sheet) instead of presenting `SpacesPurchaseSheet`. |
| `CarPlay/BereanDriveSessionService.swift:109-234` | **Blocker** | All 5 CarPlay CFs missing from backend | `bereanDriveRespond`, `bereanDriveSummarize`, `bereanDrivePrayerSession`, `bereanDriveChurchSearch`, `bereanDriveMessageSafetyReview` are called by the iOS client but have **zero** corresponding `exports.` in any backend `.js` file. Every CarPlay Berean interaction will throw a "function not found" error. |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:14-95` | **Blocker** | 6 CreatorSpaces CFs missing | `processMediaUpload`, `getDailyPortion`, `recordEditEvent`, `runSafetyCheck`, `queryMemoryGraph`, `createCreatorSpacePaidListing`, `createCreatorSpaceCheckoutSession`, `checkCreatorSpaceEntitlement` are called by iOS but not exported from any CF file. Creator Spaces upload/entitlement flow is entirely non-functional. |
| `Creator/Services/CreatorVideoProcessingService.swift:18,29` | **Blocker** | `processVideoProxy` / `generateThumbnail` CFs missing | Called in iOS; no corresponding backend exports found. Creator video processing is broken. |
| `AmenDailyDigestService.swift:68` | **Blocker** | `getAmenDailyDigest` CF missing | No `exports.getAmenDailyDigest` found in any functions file. The Daily Digest feature will always fail on fetch. |
| `Integrations/AmenIntegrationsService.swift:23-84` | **High** | 4 integration CFs missing | `getAmenIntegrationAccounts`, `startIntegrationOAuth`, `revokeAmenIntegrationAccount`, `createAmenMeeting` not exported from any backend file. |
| `SpatialSocial/EnvironmentContextService.swift:56` | **High** | `classifyEnvironment` CF missing | Not in any backend export. Spatial social environment-detection will always fail silently. |
| `SpatialSocial/SmartGatheringDetectionService.swift:30,62` | **High** | `detectNearbyGatherings` / `createEphemeralLiveSpace` CFs missing | Both backend functions absent. Smart Gathering detection is non-functional. |
| `SpatialSocial/SmartRelationshipService.swift:75` | **High** | `getSmartIntroductions` CF missing | Not in any backend export. Smart introductions never load. |
| `AmenCompanion/AskAmenCompanionRouter.swift:25` | **High** | `askAmenCompanion` CF missing | No backend export found. Ask Amen companion returns error. |
| `AMENAPP/LeadershipGuidanceView.swift:448-456` | **High** | Simulated CF call — no real backend | `sendRequest()` ignores `createLeaderConnection` CF (which also doesn't exist) and runs a 1-second fake timer with a hardcoded success. Users appear to submit but nothing is written to Firestore. |
| `GivingInAppSheet.swift:277-279,401-403` | **High** | Stripe never called | Non-Apple Pay "Donate with Card" path skips Stripe entirely and immediately shows `showSuccess = true`. Apple Pay `didAuthorizePayment` logs success but never POSTs payment token to any backend. Real money movements are not processed. |
| `ProfileView.swift:6624,6654` | **High** | Placeholder profile/hashtag views | `UserProfileViewWrapper` shows `"User profile view coming soon..."` and `HashtagSearchViewWrapper` shows `"Hashtag search view coming soon..."`. Tapping a username or hashtag in certain flows lands on these stubs. |
| `PostFollowUpService.swift:365-496` | **High** | All persistence TODOs — local-only service | `scheduleFollowUps`, `fetchPendingFollowUps`, `dismissFollowUp`, `completeFollowUp` all operate only in memory. No Firestore writes. Data is lost on app restart. Comment tension/theme analysis functions also stub-only. |
| `AmenSpacesDiscussionDiscoveryView.swift:115,680` | **Med** | Empty button actions | Header icon buttons (`Button { }`) and "View" organization CTA (`Button { }`) have completely empty action closures. Tapping them does nothing. |
| `MessagingComponents.swift:1187` | **Med** | Empty "+" button | `demoInputBar` plus button has empty closure (`Button {} label: {}`). No attachment or action is triggered. |
| `AMENAPP/Giving/Views/StewardshipDashboardView.swift:327` | **Med** | Dead quick-action buttons | All stewardship quick-action grid buttons (`Button {}`) have empty closures. Tapping Monthly Planner, Allocation, Recurring Gifts, Tax Center, Journal, Annual Review does nothing. |
| `AMENAPP/Giving/Views/BereanGivingCounselView.swift:335` | **Med** | Dead "Save for later" button | Empty closure on Berean Giving Counsel "Save for later" action. |
| `AMENAPP/GetReadyView.swift:845` | **Med** | Dead "Church Notes ready" card button | `GetReadyChurchNotesCard` button (`Button {} label:`) has empty action. Card is tappable-looking but does nothing. |
| `ChurchEditProfileView.swift:584` | **Med** | Profile save discards all changes | `handleSave()` has `// TODO: Persist changes to service layer` and only calls `dismiss()`. Church/business profile edits are never written to Firestore. |
| `MilestoneManager.swift:158,198,218,240` | **Med** | Milestone primary actions are no-ops | `primaryAction` closures for First Post, Testimony, Prayer, and Community milestones only call `dlog()`; navigation to the relevant content is a `// TODO`. Users tapping milestone CTAs land nowhere. |
| `PostCard.swift:2534-2536` | **Med** | FIXME: ThreadResurfacingExplanationSheet removed | `.sheet` is still wired to `$showLifecycleExplanation` but presents `EmptyView()`. The sheet can be triggered but shows a blank modal. |
| `PostCard.swift:3073,3160-3161` | **Med** | FIXME: inline content tokens removed | `inlineContentTokens` field and `AMENAnalyticsEvent.postInlineActionImpression` are both gone but code references remain (commented). Inline action impression tracking is silently dead. |
| `ReviewPromptManager.swift:134` | **Med** | Hardcoded "YOUR_APP_STORE_ID" | `openAppStoreForReview()` constructs a URL with the literal string `"YOUR_APP_STORE_ID"`. Opens a broken App Store URL. |
| `UserProfileView.swift:5219,5320,5335,5342,5373` | **Med** | Profile notification toggle, analytics, and cache are all stubs | `performNotificationToggle` logs only; `fetchProfileAnalytics`, `cacheProfileData`, and `loadCachedProfile` are empty comment-only stubs. |
| `PostSearchView.swift:237-238` | **Med** | Recent searches not persisted | `// TODO: Implement recent searches persistence`. "Recent Searches" section always shows "Start typing to search posts." |
| `SavedSearchNotificationIntegration.swift:149-150` | **Med** | Push notification deep-link unimplemented | Saved-search push notification tap handler logs but does not navigate to `SavedSearchesView`. |
| `GroupAdminView.swift:299` | **Med** | "Search in Conversation" not implemented | Admin action button has `// TODO: Implement search` with empty body. |
| `HelixNodeDetailSheets.swift:160,180` | **Med** | Edit and Delete buttons are placeholders | Co-creation canvas node detail sheet: "Edit" button has comment `// placeholder: navigate to edit` (empty closure); "Delete" button dismisses the sheet but does not delete the node. |
| `ChurchLiveModeView.swift:142` | **Med** | Flag message does not report | `flagMessage(id:)` removes the message locally (`chatMessages.removeAll`) but never sends a moderation report. Comment says `// TODO: Send flag report to moderation service`. |
| `LiveChurchModeService.swift:514-540` | **Med** | `generateLiveSessionRecap` CF stubbed out | Callable is commented out; function returns hardcoded placeholder recap text. Admins publishing a recap will always get the same boilerplate. |
| `ScriptureDNAView.swift:278` | **Low** | "Word Map" concept clustering is a placeholder text | Visual semantic map shows `"Visual semantic map for \(reference) — concept clustering coming soon."` |
| `Creator/Views/CreatorMediaPickerView.swift:4-6` | **Low** | Entire media picker is a placeholder | `Text("Media picker placeholder")` — no actual media picker UI. |
| `PostToSpaceSheet.swift:225` | **Low** | Photo upload coming soon | Space post sheet photo zone shows `"Photo upload coming soon"` overlay instead of a real image picker. |
| `DailyPrayerView.swift:491` | **Low** | "Weekly prayer themes coming soon" | Section of the prayer view shows coming-soon text instead of real content. |
| `InAppReviewPromptView.swift:139-140,185` | **Low** | Placeholder app icon + missing low-rating flow | App icon in review prompt uses `Image(systemName: "flame.fill")` with `// TODO: Replace with actual app icon asset`. Low-rating feedback flow is also a `// TODO`. |
| `BereanLiveActivityManager.swift:17` | **Low** | ActivityKit / Dynamic Island fully disabled | Entire implementation wrapped in `#if false`. Berean Drive Dynamic Island never activates on any device. |
| `UnifiedChatView.swift:2631,2654` | **Low** | "Translate" and "Summarize" context menu items disabled | Both appended with `isEnabled: false` — visible in the menu but permanently greyed out. |
| `PostInteractionsViewModel.swift:216` | **Low** | `startListeningToSavedPosts()` is an empty no-op | Method body is `{}`. Saved posts state never begins a live listener via this path. |
| `AMENAPP/Discover/DiscoverViewModel.swift:97-99` | **Low** | Discover "Add to Library" does nothing | `func add(_ item: FeaturedItem) { // TODO: add to saved library }`. Library save action silently discarded. |
| `ClaudeAPIService.swift:158-163` | **Low** | Streaming is word-by-word simulation, not real SSE | Streaming emits a full response word-by-word with 15ms sleep. Acceptable for now, but labeled as simulation — upgrade path when actual streaming proxy is ready. |
| `AMENAPP/AMENAPP/AmenLibraryCatalogProvider.swift:80-102` | **Low** | Library catalog wiring not complete | 3 TODOs: `amenLibrary/{bookId}` collection not wired, Apple Books affiliate link not resolved, full-text search always returns `[]`. |

---

## Not Fully Wired

### UI Buttons / Actions With Empty Closures

| Location | Button Label | Issue |
|----------|-------------|-------|
| `AmenSpacesDiscussionDiscoveryView.swift:115` | Header icon buttons | `Button { }` — no action |
| `AmenSpacesDiscussionDiscoveryView.swift:680` | "View" organization card CTA | `Button { }` — no action |
| `MessagingComponents.swift:1187` | "+" in demo input bar | `Button {} label:` — no action |
| `StewardshipDashboardView.swift:327` | All 6 quick-action grid items | `Button {}` — no action |
| `BereanGivingCounselView.swift:335` | "Save for later" | `Button {}` — no action |
| `GetReadyView.swift:845` | "Church Notes ready" card | `Button {}` — no action |
| `HelixNodeDetailSheets.swift:160` | "Edit" node button | Empty closure — no navigation |
| `SpaceDetailView.swift:342` | "Manage Space" toolbar | `NavigationLink` to `EmptyView()` |
| `AmenSmartReplyBar.swift:359` | Dismiss (×) button in preview | `Button { }` — preview only, but same structure used in live bar |

### Navigation to Placeholder / Non-Existent Views

| Location | Description |
|----------|-------------|
| `SpaceDetailView.swift:316-326` | `.bibleStudy` and `.announcement` Space tabs show raw `Text()` placeholders |
| `SpaceDetailView.swift:342-343` | "Manage Space" → `EmptyView()` |
| `ThreadDetailView.swift:343-345` | Paid Space unlock sheet → `Text("Purchase sheet coming in Agent E.")` |
| `SpacesListView.swift:17-39` | `SpaceCreationWizardPlaceholder`, `SpacesChatViewPlaceholder`, `SpaceLockedPlaceholder` all display static text |
| `ProfileView.swift:6624` | `UserProfileViewWrapper` → `"User profile view coming soon..."` |
| `ProfileView.swift:6654` | `HashtagSearchViewWrapper` → `"Hashtag search view coming soon..."` |
| `CreatorMediaPickerView.swift:4` | `Text("Media picker placeholder")` |
| `PostToSpaceSheet.swift:225` | `"Photo upload coming soon"` overlay in photo zone |

### Service-Layer TODOs / Stub Implementations

| File | Functions Affected | Impact |
|------|-------------------|--------|
| `Features/MessageActions/MessageActionService.swift` | All 25 `FirebaseMessageActionService` methods | Every message action throws `.notImplemented` at runtime |
| `PostFollowUpService.swift` | `scheduleFollowUps`, `fetchPendingFollowUps`, `dismissFollowUp`, `completeFollowUp`, `detectCommentTension`, `summarizeCommentThemes` | Local-only; all data lost on restart |
| `ChurchEditProfileView.swift:584` | `handleSave()` | Changes never persisted |
| `MilestoneManager.swift:158,198,218,240` | 4 milestone `primaryAction` closures | CTAs are no-ops |
| `UserProfileView.swift` | `performNotificationToggle`, `fetchProfileAnalytics`, `cacheProfileData`, `loadCachedProfile` | All stubs |
| `AMENAPP/Discover/DiscoverViewModel.swift:97` | `add(_:)` | Library save silently discarded |
| `PostInteractionsViewModel.swift:216` | `startListeningToSavedPosts()` | Listener never started |
| `LeadershipGuidanceView.swift:446-456` | `sendRequest()` | Fake 1-second timer, no CF call, no Firestore write |

### Cloud Functions Called in iOS With No Backend Export

The following `httpsCallable` names are invoked in Swift but have **no matching `exports.*` in any `.js` file** in the `functions/` directory:

| Swift Call Site | Function Name | Feature Broken |
|----------------|--------------|----------------|
| `CarPlay/BereanDriveSessionService.swift:109` | `bereanDriveRespond` | CarPlay Berean Q&A |
| `CarPlay/BereanDriveSessionService.swift:136` | `bereanDriveSummarize` | CarPlay answer condensing |
| `CarPlay/BereanDriveSessionService.swift:165` | `bereanDrivePrayerSession` | CarPlay guided prayer |
| `CarPlay/BereanDriveSessionService.swift:201` | `bereanDriveChurchSearch` | CarPlay church finder |
| `CarPlay/BereanDriveSessionService.swift:234` | `bereanDriveMessageSafetyReview` | CarPlay message review |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:14` | `processMediaUpload` | Creator media upload |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:28` | `getDailyPortion` | Creator daily feed |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:65` | `recordEditEvent` | Creator edit history |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:73` | `runSafetyCheck` | Creator pre-publish check |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:85` | `queryMemoryGraph` | Creator memory graph |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:95` | `createCreatorSpacePaidListing` | Spaces paid listing |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:111` | `createCreatorSpaceCheckoutSession` | Spaces checkout |
| `CreatorSpaces/Shared/CreatorSpacesService.swift:124` | `checkCreatorSpaceEntitlement` | Spaces entitlement check |
| `Creator/Services/CreatorVideoProcessingService.swift:18` | `processVideoProxy` | Creator video processing |
| `Creator/Services/CreatorVideoProcessingService.swift:29` | `generateThumbnail` | Creator thumbnails |
| `AmenDailyDigestService.swift:68` | `getAmenDailyDigest` | Daily Digest feature |
| `Integrations/AmenIntegrationsService.swift:23` | `getAmenIntegrationAccounts` | Integrations listing |
| `Integrations/AmenIntegrationsService.swift:37` | `startIntegrationOAuth` | Integration OAuth |
| `Integrations/AmenIntegrationsService.swift:59` | `revokeAmenIntegrationAccount` | Integration revocation |
| `Integrations/AmenIntegrationsService.swift:84` | `createAmenMeeting` | Meeting creation |
| `SpatialSocial/EnvironmentContextService.swift:56` | `classifyEnvironment` | Spatial environment detection |
| `SpatialSocial/SmartGatheringDetectionService.swift:30` | `detectNearbyGatherings` | Smart gathering detection |
| `SpatialSocial/SmartGatheringDetectionService.swift:62` | `createEphemeralLiveSpace` | Ephemeral live spaces |
| `SpatialSocial/SmartRelationshipService.swift:75` | `getSmartIntroductions` | Smart introductions |
| `AmenCompanion/AskAmenCompanionRouter.swift:25` | `askAmenCompanion` | Ask Amen companion |
| `AMENAPP/LeadershipGuidanceView.swift:448` | `createLeaderConnection` | Leader connection request |

### Hardcoded Credentials / IDs That Must Be Replaced

| File | Value | Impact |
|------|-------|--------|
| `ReviewPromptManager.swift:134` | `"YOUR_APP_STORE_ID"` | App Store review link opens broken URL |
| `GivingInAppSheet.swift:363` | `"merchant.com.amen.giving"` | Must be registered in Apple Developer Portal; may differ from actual merchant ID |

### Feature Flags Effectively Dead (`#if false`)

| File | What Is Disabled |
|------|-----------------|
| `BereanLiveActivityManager.swift:17` | Entire ActivityKit / Dynamic Island implementation; will never activate |

### Disabled Menu Items (Permanently `isEnabled: false`)

| File:Line | Item | Feature |
|-----------|------|---------|
| `UnifiedChatView.swift:2631` | "Translate" context menu action | Message translation in DMs |
| `UnifiedChatView.swift:2654` | "Summarize" context menu action | Message summarization in DMs |

---

## Fix Recommendations

### P0 — Ship Blockers

**1. `FirebaseMessageActionService` — wire or replace the stub (all 25 methods)**
- File: `Features/MessageActions/MessageActionService.swift`
- Each method currently throws `.notImplemented`. Implement the Firebase writes for the highest-frequency actions first: `react`, `copyText`, `deleteOwn`, `report`. The remaining 21 can follow in a second pass.
- Pattern to follow: `CloudFunctionsService.sendMessage` (already implemented).

**2. Deploy missing CarPlay Cloud Functions**
- Create `functions/bereanDriveFunctions.js` exporting `bereanDriveRespond`, `bereanDriveSummarize`, `bereanDrivePrayerSession`, `bereanDriveChurchSearch`, `bereanDriveMessageSafetyReview`.
- All five can proxy through `bereanGenericProxy` with a `mode: "drive"` safety constraint until full implementations are ready.

**3. Deploy missing CreatorSpaces Cloud Functions**
- `processMediaUpload`, `getDailyPortion`, `recordEditEvent`, `runSafetyCheck`, `queryMemoryGraph` — create `functions/creatorSpacesFunctions.js`.
- `createCreatorSpacePaidListing`, `createCreatorSpaceCheckoutSession`, `checkCreatorSpaceEntitlement` — create `functions/spacesMonetizationFunctions.js` wrapping Stripe/RevenueCat.

**4. Deploy `getAmenDailyDigest` Cloud Function**
- The Daily Digest is surfaced prominently in the UI. Create the CF and register in `index.js`.

### P1 — Broken User Flows

**5. Giving flow — wire Stripe**
- `GivingInAppSheet.swift:401-403`: After Apple Pay authorization, POST `payment.token.paymentData` to a `processGift` Cloud Function (or the existing `stripeFunctions.js` pattern).
- Non-Apple Pay fallback: present `SFSafariViewController` or a Stripe mobile SDK `PaymentSheet` instead of immediately triggering the success view.

**6. Spaces — wire `SpacesPurchaseSheet` into `SpacesListView` and `ThreadDetailView`**
- `SpacesListView.swift:106-108`: Replace `lockedSpaceTarget = nil` in the `onUnlock` closure with `SpacesPurchaseSheet` presentation.
- `ThreadDetailView.swift:343-345`: Replace the placeholder `Text(...)` sheet body with `SpacesPurchaseSheet(space: space, userId: uid, isPresented: $showPurchaseSheet)`.

**7. Spaces — replace `.bibleStudy` / `.announcement` placeholder bodies**
- `SpaceDetailView.swift:316-326`: Create `StudyBlocksView` and `AnnouncementFeedView` (even minimal versions) and replace `Text(...)` stubs.

**8. Spaces — wire "Manage Space" NavigationLink**
- `SpaceDetailView.swift:342-343`: Replace `EmptyView()` with a `SpaceSettingsView` or at minimum a `Form`-based stub for name/description editing.

**9. Fix `LeadershipGuidanceView.sendRequest()`**
- Remove fake timer; deploy `createLeaderConnection` CF (Firestore write to `users/{uid}/leaderConnections`) and call it from `sendRequest()`.

**10. `PostFollowUpService` — persist to Firestore**
- Replace all four `// TODO` comment blocks with actual Firestore batch writes to `followUps/{id}`.

**11. `ChurchEditProfileView.handleSave()` — write to Firestore**
- Replace `// TODO: Persist changes to service layer` with a Firestore `updateData` call on `churches/{churchId}`.

**12. Milestone CTAs — add navigation**
- `MilestoneManager.swift:158,198,218,240`: Route each `primaryAction` closure through the app's `NavigationCoordinator` or `NotificationCenter` post to switch to the correct tab + push the relevant view.

### P2 — Degraded UX / Polish

**13. Replace placeholder views accessed via navigation**
- `ProfileView.swift:6624,6654`: `UserProfileViewWrapper` and `HashtagSearchViewWrapper` should route to the real `UserProfileView` and `PostSearchView` respectively.

**14. Wire AmenSpacesDiscussionDiscoveryView buttons**
- Both `Button { }` instances (header icons + organization "View" CTA) need actions: header icons should open search/notifications; "View" should navigate to the organization/community detail.

**15. Wire StewardshipDashboard quick-action grid**
- Each `Button {}` should navigate to its corresponding section view (planner, allocation, etc.) rather than doing nothing.

**16. Set real App Store ID**
- `ReviewPromptManager.swift:134`: Replace `"YOUR_APP_STORE_ID"` with the actual App Store app ID before submission.

**17. Enable / implement "Translate" and "Summarize" in chat context menu**
- `UnifiedChatView.swift:2631,2654`: Either remove these items if unbuilt, or implement them using `TranslateButton` / `AIThreadSummarizationService` (already present in the codebase).

**18. `startListeningToSavedPosts()` — implement Firestore listener**
- `PostInteractionsViewModel.swift:216`: Method is called from the outside (stop has an implementation) but start is empty. Add a `Firestore.firestore().collection("savedPosts")...addSnapshotListener` matching the pattern in `SavedPostsService`.

**19. `DiscoverViewModel.add(_:)` — save to library**
- Implement Firestore write to `users/{uid}/library/{ref}` following the `AmenHealthyImmersiveMediaSystem.saveToMediaQueue` pattern.

**20. `ReviewPromptManager` / `InAppReviewPromptView` — implement low-rating feedback flow**
- Replace `// TODO: Implement feedback flow for low ratings` with a sheet presenting a short feedback form or a mailto link to support@amenapp.com.

**21. Deploy missing Integrations and Spatial Social CFs or gate behind feature flags**
- If `classifyEnvironment`, `detectNearbyGatherings`, `createEphemeralLiveSpace`, `getSmartIntroductions`, `askAmenCompanion`, and all Integrations CFs are not shipping in this release, add early-return guards gated on the relevant `AMENFeatureFlags` values so the callables are never invoked. Without guards these will produce user-visible errors.

**22. Remove or implement `ChurchLiveModeView.flagMessage` backend call**
- Add a `submitReport` callable invocation (already implemented in `ContentModerationService`) so flagged messages are actually reported, not just removed from the local array.

**23. `PostSearchView` — implement recent searches persistence**
- Write tapped/submitted queries to `UserDefaults` (or `@AppStorage`) and read them back in `recentSearchesView`.

**24. `SavedSearchNotificationIntegration` — navigate on deep link**
- Replace `// TODO: Present SavedSearchesView` with a `NotificationCenter.default.post(name: .navigateToSavedSearch, object: query)` and handle it in the tab coordinator.

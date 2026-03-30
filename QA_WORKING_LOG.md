# AMEN QA Working Log

## Entry 1
1. Current phase
   Discovery / build baseline
2. What I tested
   Ran `xcodebuild -list`, `xcrun simctl list devices available`, `xcrun simctl list runtimes`, `rg -n "PRODUCT_BUNDLE_IDENTIFIER|PRODUCT_NAME|MARKETING_VERSION|CURRENT_PROJECT_VERSION" AMENAPP.xcodeproj/project.pbxproj`, and `find . -name "*.xcworkspace" -o -name "*.xcodeproj"`.
   Built the app with discovered values: project `AMENAPP.xcodeproj`, scheme `AMENAPP`, destination `platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4`.
3. What failed
   Initial attempts failed because earlier placeholder values did not match this repo or this Xcode install.
4. Root cause
   The real shared scheme is `AMENAPP`, not `AMEN`.
   The installed simulators do not include `iPhone 16 Pro`; the best available iPhone target is `iPhone 17 Pro Max` on iOS 26.4, already booted.
5. Files changed
   `QA_WORKING_LOG.md`
6. Fix applied
   Switched to discovery-first execution and rebuilt using only discovered project and simulator values.
7. Validation result
   `xcodebuild` completed with `** BUILD SUCCEEDED **`.
   Built app path observed in DerivedData: `/Users/stephtapera/Library/Developer/Xcode/DerivedData/AMENAPP-ghfyeznloxhirmexqskyjgwmolof/Build/Products/Debug-iphonesimulator/AMENAPP.app`
8. Remaining risks / next target
   Need runtime validation from cold start.
   Need to install, launch, stream logs, and identify startup/runtime blockers.
   Build emitted a warning that `AMENWidgetExtensionExtension` has `IPHONEOS_DEPLOYMENT_TARGET = 26.4`, which exceeds Xcode's supported simulator deployment target max `26.2.99`.

## Entry 2
1. Current phase
   Phase 1 — app startup / stability
2. What I tested
   Launched `tapera.AMENAPP` from a cold reinstall using `xcrun simctl launch --console-pty --terminate-running-process booted tapera.AMENAPP`.
   Observed authenticated startup, feed preload, and listener attachment behavior in app stdout/stderr.
3. What failed
   `HeyFeedService` attached Firestore listeners on every sign-in during app launch and immediately produced permission-denied errors for `heyfeed_resonance`, `heyfeed_requests`, and `pastoral_care_signals`.
4. Root cause
   `AMENAPPApp` eagerly called `HeyFeedService.shared.startListening()` on auth state changes even though Hey Feed is not a required startup dependency and its Firestore collections are not readable for the current user/session.
5. Files changed
   `AMENAPP/AMENAPPApp.swift`
   `AMENAPP/HeyFeedActiveRequestsView.swift`
   `AMENAPP/HeyFeedComposerView.swift`
   `AMENAPP/HeyFeedPostCardBadge.swift`
6. Fix applied
   Removed eager Hey Feed listener startup from the global auth listener.
   Started Hey Feed listeners lazily from Hey Feed surfaces only, preserving feature behavior while keeping startup clean.
7. Validation result
   Pending rebuild and relaunch to confirm Hey Feed permission errors no longer appear during cold start.
8. Remaining risks / next target
   Need to rebuild, reinstall, and relaunch from cold state.
   Need to confirm there are no regressions in feed startup or tab initialization.
   Need to continue to the next runtime blocker after startup logs are cleaner.

## Entry 3
1. Current phase
   Phase 1 — app startup / stability
2. What I tested
   Rebuilt, reinstalled, and cold-launched after the Hey Feed fix.
   Revalidated launch logs from app stdout/stderr.
3. What failed
   A background post profile image migration still ran during launch and attempted to update posts client-side, producing Firestore permission errors for posts the client cannot mutate.
4. Root cause
   `ContentView` automatically kicked off `runPostProfileImageMigrationIfNeeded()` on startup.
   That routine calls `PostProfileImageMigration.shared.migrateAllPosts()`, which is a global backfill over the `posts` collection and is not appropriate for normal client permissions.
5. Files changed
   `AMENAPP/ContentView.swift`
6. Fix applied
   Removed the automatic global post profile image migration from the startup task.
   Left targeted/manual migration paths intact for admin/debug tooling and per-user profile updates.
7. Validation result
   Pending rebuild and relaunch to confirm startup no longer emits post migration permission errors.
8. Remaining risks / next target
   Need to retest cold launch again.
   Remaining startup warnings include App Check debug-token exchange failures and a deployment-target warning for the widget extension.
   After startup is clean enough, continue into feed, comments, reactions, Church Notes, notifications, and navigation.

## Entry 4
1. Current phase
   Phase 2 — auth / entry stabilization
2. What I tested
   Rebuilt, reinstalled, and cold-launched after removing the post migration.
   Observed the authenticated startup path and the first routed screen after auth restoration.
3. What failed
   The app pushed the cached authenticated user into onboarding because the Firestore user document was missing.
   Concurrent startup services also logged `User document not found`, which means profile-dependent flows were running against broken auth state.
4. Root cause
   `FirebaseManager.fetchUserDocument(userId:)` threw `documentNotFound` when the authenticated user’s Firestore profile doc was absent.
   `AuthenticationViewModel.checkOnboardingStatus` treated that as a fallback-to-cache case, which led to `needsOnboarding=true` with no actual user profile document behind the session.
5. Files changed
   `AMENAPP/FirebaseManager.swift`
6. Fix applied
   Added a self-healing bootstrap path for the current authenticated user.
   When that user’s Firestore document is missing, the app now creates a minimal profile document plus a placeholder username index entry, then returns the repaired data to callers.
7. Validation result
   Pending rebuild and relaunch to confirm the missing-user-document path self-heals and the app no longer falls into a broken onboarding/profile state.
8. Remaining risks / next target
   Need to verify the repaired user document removes `User document not found` startup noise.
   Need to confirm the post-auth destination is now stable.
   After auth recovery is stable, continue into feed, comments, reactions, Church Notes, notifications, and navigation.

## Entry 5
1. Current phase
   Phase 2 — auth / entry stabilization
2. What I tested
   Cold-launched with the first self-heal in place.
   Observed that the missing user doc was repaired, but the repaired document still routed the authenticated user into onboarding.
3. What failed
   Returning sessions with a repaired placeholder profile were still treated as incomplete onboarding, causing the app to tear down feed listeners and switch to onboarding after startup.
4. Root cause
   The initial repair logic always wrote `hasCompletedOnboarding = false`.
   Existing repaired docs then looked identical to incomplete new-user profiles during `checkOnboardingStatus`.
5. Files changed
   `AMENAPP/FirebaseManager.swift`
6. Fix applied
   Added returning-user detection using Firebase Auth metadata.
   Repaired profiles now default to `hasCompletedOnboarding = true` for returning users.
   Existing repaired placeholder profiles are promoted out of onboarding on the next fetch if they match the bootstrap username/version pattern.
7. Validation result
   Pending rebuild and relaunch to confirm the app now stays in the authenticated home flow for this repaired account.
8. Remaining risks / next target
   Need to verify `User document not found` logs disappear or at least stop affecting routing.
   Need to get the app to remain in main content so deeper feed, comments, reactions, Church Notes, notifications, and tab navigation testing can continue.

## Entry 6
1. Current phase
   Phase 1 / 2 — startup listener and profile refresh stabilization
2. What I tested
   Rebuilt, cold-launched, backgrounded/foregrounded, and watched startup/runtime logs for repeated profile refresh work and eager Hey Feed listeners.
3. What failed
   Startup still did unnecessary work after sign-in:
   profile refresh logic could restart redundantly around lifecycle changes,
   and startup utility tasks duplicated current-user profile caching and automatic migration work.
4. Root cause
   `PostsManager` did not fully reset its profile-refresh guard on stop, and app lifecycle hooks were not using a clean resume path.
   `AMENAPPApp` also kicked off duplicate startup utility work, while `UserProfileImageCache` fetched the user document through a raw path that still logged missing-doc noise instead of using the repaired fetch path.
5. Files changed
   `AMENAPP/AMENAPPApp.swift`
   `AMENAPP/PostsManager.swift`
   `AMENAPP/UserProfileImageCache.swift`
6. Fix applied
   Added a safe resume path for profile refresh listeners and reset the started flag on stop.
   Removed duplicate startup profile-cache/migration work from `AMENAPPApp`.
   Routed profile caching through `FirebaseManager.fetchUserDocument(userId:)` so it benefits from the existing self-heal path.
7. Validation result
   Cold launch remained stable.
   Duplicate startup work and profile-refresh churn were reduced.
   Startup logs no longer showed repeated user-document/profile-cache noise from the old raw fetch path.
8. Remaining risks / next target
   App Check debug-token failures still appear on simulator.
   Need to continue reducing startup noise and validate deeper flows.

## Entry 7
1. Current phase
   Phase 2 — auth / entry stabilization
2. What I tested
   Rebuilt and cold-launched with the user self-heal flow already in place, then watched for duplicate bootstrap writes/logs during authenticated startup.
3. What failed
   Missing-user bootstrap work could run more than once for the current user during concurrent startup callers, causing duplicate repair logs and unnecessary writes.
4. Root cause
   Multiple startup services could call `FirebaseManager.fetchUserDocument(userId:)` for the same current user before the first bootstrap task finished.
5. Files changed
   `AMENAPP/FirebaseManager.swift`
6. Fix applied
   Added a lock-protected in-flight bootstrap task map so current-user document repair is deduplicated across concurrent callers.
   Moved lock access into synchronous helpers to avoid Swift 6 actor-isolation issues.
7. Validation result
   Cold launch no longer emitted duplicate missing-user repair logs.
   Authenticated startup stayed in the main app flow cleanly.
8. Remaining risks / next target
   Need continued runtime validation across feed, notifications, comments, reactions, and notes.

## Entry 8
1. Current phase
   Phase 7 — notifications / post detail consistency
2. What I tested
   Cold-launched the app, opened a notification-driven post route with `amenapp://post/B77C8DEC-CBDF-488D-8F9D-BA0565E1337D`, and compared the simulator screen against the shared post detail experience.
3. What failed
   The notification route initially showed a blank white sheet even though the deep-link router reported successful navigation.
4. Root cause
   `HomeView` presented notification post detail with a separate `Bool` and optional post ID.
   That allowed the sheet to present with empty content before the payload was available, so `NotificationPostDetailView` never mounted and the screen stayed blank.
5. Files changed
   `AMENAPP/ContentView.swift`
6. Fix applied
   Replaced the `Bool + optional ID` presentation path with an item-backed notification post route.
   The sheet now presents only when a concrete post payload exists, and it preserves `scrollToCommentId` for comment-targeted notifications.
7. Validation result
   After rebuild, reinstall, and cold relaunch, the notification route mounted correctly instead of showing a blank sheet.
   Runtime logs now show `NotificationPostDetailView` loading, `fetchPostById`, and live comment listener startup.
8. Remaining risks / next target
   Need to keep validating comment-targeted notification routes and adjacent notification flows.
   Need to confirm there are no regressions when entering post detail from in-app notification rows.

## Entry 9
1. Current phase
   Phase 7 — notifications / UI consistency polish
2. What I tested
   Replayed the notification-driven post route after the sheet fix and captured the simulator screen.
3. What failed
   The old `NotificationPostDetailView` implementation had its own post-detail UI, which diverged visually and behaviorally from the main `PostDetailView`.
4. Root cause
   Notification-driven post navigation used a bespoke detail surface instead of the shared post-detail destination used elsewhere in the app.
5. Files changed
   `AMENAPP/NotificationPostDetailView.swift`
6. Fix applied
   Replaced the bespoke notification post detail surface with a thin loader that fetches the post by ID and renders the shared `PostDetailView(post:)`.
   Added a lightweight mount log and preserved comment-focus intent through `CommentFocusCoordinator`.
7. Validation result
   Rebuild succeeded.
   Cold reinstall + relaunch succeeded.
   The simulator now shows a populated shared post detail screen for the notification route instead of the old custom UI or a blank sheet.
8. Remaining risks / next target
   Need to validate comment-targeted notification deep links with a concrete `commentId`.
   Need continued pass on notifications, comments/replies, reactions, Church Notes, and tab navigation.

## Entry 10
1. Current phase
   Phase 4 / 7 — comments, replies, and notification-thread consistency
2. What I tested
   Rebuilt after the new PostCard menu work, then relaunched and replayed the shared post-detail deep link for `amenapp://post/B77C8DEC-CBDF-488D-8F9D-BA0565E1337D`.
3. What failed
   The app stopped compiling because the comment-thread highlight/expand state was only partially wired through `ConversationThreadView` and `PostDetailView`.
4. Root cause
   `ConversationThreadView` now expected external expanded/highlight state, but nested thread rows and the shared post detail call site were not updated consistently.
   Notification-driven comment focus also still had no consumer in `PostDetailView`, so targeted comment/reply context was being dropped even when navigation succeeded.
5. Files changed
   `AMENAPP/ConversationThreadView.swift`
   `AMENAPP/PostDetailView.swift`
6. Fix applied
   Added `expandedClusters` binding and `highlightedCommentIDs` plumbing across thread rows and nested reply clusters.
   Added subtle highlight rendering for focused comments/replies.
   Consumed `CommentFocusCoordinator` in shared `PostDetailView` so notification-driven comment focus now expands the target thread and temporarily highlights the targeted comment/reply.
7. Validation result
   Rebuild succeeded.
   Cold reinstall + relaunch succeeded.
   The notification-driven shared post detail route still loaded the post and comments successfully after the thread changes.
   Runtime logs showed the post fetch plus live comment listener startup for the deep-linked post.
8. Remaining risks / next target
   Shared post detail now consumes highlight/expand intent, but it still does not scroll to the exact target comment automatically.
   Need continued runtime validation on feed-card interactions and adjacent navigation.

## Entry 11
1. Current phase
   Phase 3 — home feed / PostCard interaction polish
2. What I tested
   Integrated the new PostCard contextual action menu, rebuilt the app, relaunched it in the simulator, and verified adjacent runtime flows stayed healthy after the UI change.
3. What failed
   The existing PostCard trailing action affordance did not match the requested AMEN-specific contextual interaction.
   It relied on a legacy overflow/long-press path instead of an anchored, premium, lightweight menu emerging from the card control itself.
4. Root cause
   `PostCard` had no dedicated anchored contextual menu system, no one-menu-open coordinator across multiple cards, and no reusable white-glass menu components for this interaction pattern.
5. Files changed
   `AMENAPP/PostCard.swift`
6. Fix applied
   Added reusable `AmenPostCardPlusButton`, `AmenPostCardActionMenu`, `AmenGlassContainer`, and `AmenGlassRow` components.
   Replaced the trailing PostCard control with a glass `+` button that rotates into an `x` and drives a spring-based anchored menu overlay.
   Added a shared coordinator so only one PostCard menu can stay open at a time.
   Added outside-tap, repeated-tap, scroll, and navigation dismissal behavior.
   Wired menu actions to the existing follow/profile flows without changing their underlying business logic.
7. Validation result
   Project build succeeded after the integration.
   Simulator launch remained stable, and adjacent deep-link post-detail validation still passed after the PostCard changes.
8. Remaining risks / next target
   Direct feed-surface tapping of the new `+` button could not be fully automated with the simulator input tooling available in this environment.
   Need one manual/device or UI-automation pass on an actual PostCard in feed/profile surfaces to confirm final positioning, timing, and touch feel exactly as intended.

## Entry 12
1. Current phase
   Phase 2 / onboarding consistency polish
2. What I tested
   Reworked the live auth entry path, rebuilt the app, reinstalled it on the `iPhone 17 Pro Max` simulator, relaunched with console output, and streamed runtime logs after startup.
3. What failed
   The entry experience still mixed white onboarding/auth surfaces with older dark ones.
   Email auth from the live landing screen still dropped into the legacy black `SignInView`, and returning-user sign-in treatment was disconnected from the white auth flow.
4. Root cause
   `AMENAuthLandingView` routed both email actions into the old dark auth screen instead of the newer white minimal auth system.
   `MinimalAuthenticationView` did not distinguish sign-in vs sign-up strongly enough, did not open directly into the chosen form when launched from the auth landing, and did not surface remembered identity.
   `AutoLoginSplashView` and the secondary `OnboardingFlowView` still used dark visual treatments that conflicted with the white AMEN entry system.
5. Files changed
   `AMENAPP/AMENAuthLandingView.swift`
   `AMENAPP/MinimalAuthenticationView.swift`
   `AMENAPP/AutoLoginSplashView.swift`
   `AMENAPP/OnboardingFlowView.swift`
6. Fix applied
   Re-routed email sign-in and sign-up from the live auth landing into `MinimalAuthenticationView` with the correct initial mode and direct-form presentation.
   Added distinct white sign-in and sign-up treatments in `MinimalAuthenticationView`, including a remembered-user profile card for returning sign-in and a separate three-step sign-up onboarding card.
   Converted the returning-user auto-login splash to the same white AMEN palette while preserving the cached profile photo behavior and existing motion.
   Re-themed the dark portions of `OnboardingFlowView` to white glass surfaces with black typography while keeping the existing onboarding logic and animations.
7. Validation result
   `xcodebuild -project AMENAPP.xcodeproj -scheme AMENAPP -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' -quiet build` succeeded.
   Reinstall + relaunch on simulator succeeded with no new startup blocker.
   Runtime logs showed the cached-user launch path completing cleanly into main content after the auth/onboarding UI changes.
8. Remaining risks / next target
   This simulator session still auto-restores an authenticated Firebase user, so the new unauthenticated sign-in/sign-up and onboarding surfaces were not visually exercised end-to-end in a clean logged-out state yet.
   Simulator screenshot/input tooling is partially constrained in this environment, so final visual verification of the revised auth/onboarding layouts still needs one clean-session manual or UI-automation pass.

## Entry 13
1. Current phase
   Phase 3 — PostCard header control regression fix
2. What I tested
   Restored the visible overflow affordance on `PostCard`, then rebuilt the app to verify the header action wiring still compiled cleanly with the liquid-glass `+` menu.
3. What failed
   The PostCard header no longer exposed the original 3-dot options button, leaving the existing options sheet reachable only by long press.
4. Root cause
   The header trailing control was replaced during the new `+` action-menu work, but the options-sheet presentation logic itself was never removed.
5. Files changed
   `AMENAPP/PostCard.swift`
6. Fix applied
   Added a dedicated glass ellipsis overflow button back to the PostCard header beside the `+` menu button.
   Wired it to the existing `showOptionsSheet` flow and ensured it closes the `+` action menu before presenting the options sheet.
7. Validation result
   `xcodebuild -project AMENAPP.xcodeproj -scheme AMENAPP -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' -quiet build` succeeded after the restore.
8. Remaining risks / next target
   This pass validated compile-time behavior only.
   A manual feed-surface tap pass is still needed to confirm final spacing and touch feel for the restored ellipsis button next to the `+` menu on live PostCards.

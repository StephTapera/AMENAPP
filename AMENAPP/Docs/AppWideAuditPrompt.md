# App-Wide Audit Prompt

This prompt is the reusable app-wide audit instruction set for AMEN production-readiness passes. Run every applicable agent pack as an implementation mandate: audit, fix repo-caused issues, validate, and report with GO / GO WITH CAVEATS / NO-GO.

## POSTS + CREATE POST AUDIT / BUILD AGENT PACK

MISSION:
Audit, fix, wire, secure, and validate everything related to AMEN posts, CreatePostView, post rendering, visibility, media, permissions, dead code, duplicate code, and production readiness.

Do not stop at reporting. Fix every repo-caused issue found.

====================================================
AGENT 1 — POST SYSTEM INVENTORY AGENT
====================================================

Audit all post-related files:
- CreatePostView
- PostCard
- PostDetailView
- AmenMediaDetailView
- feed views
- profile post grids
- Discover post surfaces
- Selah media surfaces
- comments/reactions/share/save/report flows
- post services
- media upload services
- moderation services
- Firestore rules
- Storage rules
- backend post/media functions
- feature flags
- analytics
- tests

Create:
AMENAPP/Docs/PostSystemAudit.md

Output:
- file map
- flow map
- button matrix
- visibility matrix
- backend callable matrix
- rules matrix
- dead/duplicate code matrix

====================================================
AGENT 2 — CREATE POST VIEW AGENT
====================================================

Audit and fix CreatePostView end-to-end:
- text post
- photo post
- video post
- dual-camera post if present
- caption
- tags/topics
- scripture reference (verify YouVersion API key used, reference validated before publish, renders correctly in PostCard)
- prayer/testimony/teaching labels
- visibility picker
- audience picker
- location/church/org tagging
- media picker
- camera button
- upload state
- moderation state
- draft state
- retry/cancel
- submit/post button

Draft persistence:
- drafts must survive app crash (persisted to local storage or Firestore drafts collection, not held only in @State)
- draft list view must exist and be reachable
- draft must be recoverable on next launch
- draft auto-save must trigger on every significant field change
- draft must be deleted on successful publish

Scripture reference integrity:
- YouVersion API key (Config.xcconfig YOUVERSION_API_KEY) must be used for lookups — not hardcoded
- reference must be validated against the API before the Post button is enabled
- invalid or empty reference must show inline error, not silently drop the field
- tagged scripture must render as tappable verse chip in PostCard and PostDetailView

Double-post prevention:
- submit button must be disabled immediately on first tap and remain disabled until server confirms or rejects
- an idempotency key (e.g. UUID generated at composer open) must be included in the create-post payload
- backend must deduplicate on idempotency key (reject duplicate within a time window)
- retry on network failure must reuse the same idempotency key, never generate a new one

Reject:
- dead buttons
- fake upload state
- client-only moderation
- missing loading/error state
- silent failure
- posts created without visibility/audience validation
- media uploaded without matching post metadata
- drafts held only in @State (lost on crash)
- scripture field accepted without API validation
- submit button re-enabled before server response (double-post risk)
- retry that generates a new idempotency key

====================================================
AGENT 3 — POST VISIBILITY + AUDIENCE AGENT
====================================================

Audit what is visible and to whom.

Visibility types:
- public
- followers
- mutuals
- church/org members
- group/space members
- private/draft
- removed
- pending moderation
- blocked audience
- age/minor restricted if applicable
- premium/Covenant gated (visible only to subscribers)

Verify:
- UI visibility picker matches backend rules
- feed query respects visibility
- profile view respects visibility
- Discover respects visibility
- media detail respects visibility
- comments respect visibility
- share/save/report respect visibility
- blocked users cannot view/interact
- removed/draft posts never appear publicly
- pending moderation does not leak

Social graph consistency:
- when user A blocks user B: B's existing posts disappear from A's feed within one session (retroactive, not just new posts)
- when user A unfollows user B: B's posts no longer appear in A's followers-only feed
- verify both are enforced in Firestore query rules, not filtered client-side only
- verify cached/offline posts from blocked users are purged from local cache

Church/org posting permissions:
- verify that only church admins (or members with posting permission) can create posts attributed to a church/org page
- verify regular members cannot post as the church/org entity
- verify the permission check is enforced in Firestore rules (not just the iOS UI)
- create matrix: Role | Can Post As Church | Can Post In Church Feed | Rules Check | Status

Premium/Covenant gated posts:
- verify posts marked as Covenant-gated show a paywall preview to non-subscribers (teaser text/image, not full content)
- verify full content is not included in the Firestore document readable by non-subscribers (must be fetched via authenticated callable after subscription check)
- verify AmenCovenantCheckoutService subscription status is checked at the rules level, not only in SwiftUI
- verify Covenant-gated posts are excluded from public Algolia search index or return teaser-only fields

Create matrix:
Post State | Feed | Profile | Discover | Media Detail | Search | Share | Rules | Status

====================================================
AGENT 4 — POST RENDERING AGENT
====================================================

Audit how posts show everywhere:
- feed card
- profile grid
- post detail
- media detail
- Discover card
- creator profile
- church/org page
- comments thread
- shared link preview

Verify:
- author shown correctly
- timestamp correct
- edited state shown (label + edit timestamp)
- visibility badge correct where needed
- media aspect ratio safe
- captions render correctly
- scripture/theme labels render correctly (verse chip tappable, routes to scripture detail)
- moderation state visible only to allowed users
- deleted/removed state handled
- blocked/muted state handled
- loading skeletons exist
- empty/error states exist
- Covenant-gated posts show paywall card to non-subscribers, not blank or crash

====================================================
AGENT 5 — POST BUTTON WIRING AGENT
====================================================

Audit every post-related button:
- create
- camera
- media picker
- remove media
- publish
- save draft
- edit post
- delete post
- like/react
- comment
- share
- save/bookmark
- report
- block/mute
- follow author
- open media
- open profile
- open church/org
- tag scripture
- ask Berean
- generate caption
- generate key moments
- view transcript
- explain video
- retry upload
- cancel upload
- upgrade/subscribe (Covenant gate)

For each:
Button | File | Action | Backend/Service | Loading/Error | A11y | Status

Fix:
- empty closures
- TODOs
- print-only actions
- haptic-only actions
- dead navigation
- missing disabled state
- missing error handling

====================================================
AGENT 6 — MEDIA UPLOAD + STORAGE AGENT
====================================================

Audit:
- image upload
- video upload
- thumbnails
- captions
- transcripts
- key moments
- generated metadata
- storage path
- content type
- size limits
- retry/resume
- cancellation
- failed upload cleanup
- orphaned files
- post/media metadata consistency

Rules:
- users can upload only to owned/temp paths
- backend finalizes approved media
- clients cannot mark media approved
- clients cannot write generated AI metadata directly
- removed media is not public

Google Vision content safety pipeline:
- verify GOOGLE_VISION_API_KEY (Config.xcconfig) is called for every image/video thumbnail before the post is published
- verify the Vision API call happens server-side (Cloud Function), not from the iOS client
- verify the Vision SafeSearch response is checked for ADULT, VIOLENCE, MEDICAL thresholds
- verify posts with flagged media are moved to moderationQueue with status=pendingReview, not silently dropped or published
- verify the client receives a meaningful error state ("Your media is under review") not a silent failure
- create matrix: Media Type | Vision Check | Threshold | On Flag Action | Client State | Status

====================================================
AGENT 7 — POST MODERATION + SAFETY AGENT
====================================================

Audit:
- pre-post moderation
- post-publish moderation
- report flow
- blocked users
- muted users
- sensitive content
- prayer/care/testimony safety
- misinformation/harm handling
- flagged post visibility
- appeal/review state if present

Faith-sensitive post type safety:
- prayer posts: must NOT appear in public Discover feed; visible only to followers or church members as per post visibility; not indexable in Algolia public index
- testimony posts: may appear in Discover only if author set visibility = public; must carry a content label
- teaching posts: indexable; must carry author credential/church affiliation label
- care/grief posts: must NOT appear in Discover; restricted to followers or private
- verify these rules are enforced in Firestore rules AND feed queries, not UI-only
- create matrix: Post Type | Discover | Algolia Index | Default Visibility | Requires Label | Rules Enforced | Status

GDPR / account deletion:
- when a user requests account deletion, verify all posts are either hard-deleted or anonymised per the app's stated privacy policy
- verify media files in Firebase Storage are deleted when the associated post is deleted
- verify Algolia index entries are removed when a post is deleted or the author account is deleted
- verify comments/reactions by the deleted user are anonymised or removed
- verify the deletion Cloud Function exists and is tested
- deletion must be irreversible: verify no dangling document references remain after deletion

Fix:
- client-only moderation
- missing server validation
- unsafe preview text
- flagged content leaking
- report buttons not wired
- moderation queue missing rules
- faith-sensitive types appearing in wrong surfaces
- account deletion leaving orphaned posts/media in public paths

====================================================
AGENT 8 — AI POST INTELLIGENCE AGENT
====================================================

Audit AI features:
- caption generation
- key moment generation
- transcript/Whisper
- explain video
- Berean context
- scripture suggestions
- translation
- summarize comments
- smart hashtags/topics
- creator tools

Verify:
- backend callable exists
- Auth/App Check enforced
- rate limits
- consent/safety gates
- no client keys
- no fake fallback
- generated metadata provenance shown
- user approval required before publishing AI-generated content

====================================================
AGENT 9 — DEAD CODE + DUPLICATE POST CODE AGENT
====================================================

Find:
- duplicate post models
- duplicate post services
- duplicate PostCard variants
- duplicate media detail views
- stale upload services
- deprecated save/bookmark services
- unused feature flags
- orphan post views
- mock post data in production
- TODO/FIXME production blockers

Do not delete unless:
- references prove unused
- replacement exists
- tests/build pass

Create:
Dead Code | Files | Risk | Fix | Removed/Kept

====================================================
AGENT 10 — LIQUID GLASS + UX AGENT
====================================================

Audit post UI design:
- composer controls
- create post toolbar
- upload capsule
- media chrome
- floating action bars
- privacy/audience picker
- AI assistant controls

Rules:
- Liquid Glass for controls only
- no glass post body cards
- no glass-on-glass stacking
- white background/black text
- readable media overlays
- Reduce Motion/Transparency/Contrast support

====================================================
AGENT 11 — BACKEND + RULES AGENT
====================================================

Audit backend/rules for:
- posts
- comments
- reactions
- saves/bookmarks
- shares
- reports
- mediaUploads
- transcripts
- captions
- moderationQueue
- blockedUsers
- follows
- audience memberships

Ensure:
- Auth required on all writes and sensitive reads
- App Check enforced on post create, update, delete, and all AI callables
- rate limits on post creation (max N posts per hour per user)
- safe typed errors (no rule details, collection paths, or uid leakage in error messages)
- no private existence leakage (blocked/private posts return 404, not 403)
- server-only generated fields (createdAt, updatedAt, authorId, moderationStatus)
- visibility enforced in both rules and queries
- indexes exist for feed/profile/discover/church queries
- idempotency key enforced on post create callable (deduplicate within 60s window)

Notification triggers (must be server-side Cloud Functions, never client):
- post published → notify followers (if notificationsEnabled)
- reaction on post → notify author
- comment on post → notify author and thread participants
- share of post → notify author
- moderation action → notify author (sanitised message only, no rule details)
- verify each trigger exists as a Firestore/callable Cloud Function
- verify notification payload contains postId for deep link routing

Algolia sync (must be server-side, never client):
- post created → index document (visibility=public only)
- post edited → update index document
- post deleted/removed → delete from index
- prayer/care post → never indexed regardless of visibility
- account deleted → remove all author's indexed posts
- verify writes to Algolia happen in Cloud Functions, not SwiftUI
- verify AlgoliaSearchClient on device is read-only (search only, no index writes)

GDPR / data deletion:
- account deletion Cloud Function must: delete all user posts, delete Storage media, remove Algolia entries, anonymise comments/reactions, revoke Auth token
- verify deletion is atomic or has idempotent retry on partial failure
- verify no Cloud Function has a write rule that can resurrect deleted data

====================================================
AGENT 12 — DEEP LINK + SHARE URL AGENT
====================================================

Audit all post share and deep link infrastructure:

Share URL generation:
- verify post share produces a valid universal link (e.g. https://amenapp.com/post/{postId})
- verify fallback to amenapp:// custom scheme when universal link not available
- verify Open Graph metadata (og:title, og:description, og:image) is server-rendered or statically generated per post, not client-generated
- verify share sheet uses UIActivityViewController with the correct URL, not a hardcoded placeholder

Cold-launch routing:
- verify AppDelegate/SceneDelegate (or SwiftUI .onOpenURL) handles amenapp://post/{postId} and https universal link
- verify cold-launch from share link navigates to PostDetailView with correct postId
- verify warm-launch (app in background) also routes correctly
- verify invalid/deleted postId shows 404-equivalent state, not a crash

Universal links:
- verify apple-app-site-association (AASA) file is served at https://{domain}/.well-known/apple-app-site-association
- verify AASA appIDs entry matches the app's bundle ID and team ID
- verify NSUserActivityTypes in Info.plist includes the post activity type if Handoff is used

Reject:
- share sheet that produces a non-routable URL
- cold-launch that crashes or lands on the home feed instead of the post
- missing AASA file or team ID mismatch
- hardcoded share URLs

Create matrix:
Entry Point | URL Scheme | Handler File | Routes To | Cold Launch | Warm Launch | Status

====================================================
AGENT 13 — SEARCH SYNC AGENT (ALGOLIA)
====================================================

Audit all Algolia search index interactions for posts:

Index write safety:
- AlgoliaSearchClient package on device must be used for read (search) only
- all index writes (create, update, delete) must happen in Cloud Functions
- verify no direct index write calls exist in any Swift file
- if any are found, move them to backend callables and patch the client to call the callable instead

Index correctness:
- post created (visibility=public) → objectID={postId} indexed with fields: authorId, caption snippet, postType, churchId, timestamp, scripture reference if present
- post edited → index document updated atomically
- post deleted or removed → objectID deleted from index
- post visibility changed from public → private → remove from index
- post visibility changed from private → public → add to index
- account deleted → all author posts removed from index

Faith-sensitive filtering (MUST ENFORCE):
- prayer posts: never indexed (postType == "prayer" → skip)
- care/grief posts: never indexed (postType == "care" || "grief" → skip)
- testimony posts: indexed only if author visibility = public AND author has not opted out
- Covenant-gated posts: indexed with teaser fields only, full content excluded
- verify these filters exist in the Cloud Function, not just in the iOS query

Search surface audit:
- verify search results respect blocked users (filter by blockedBy not containing current uid)
- verify search results exclude removed/pending-moderation posts
- verify search ranking does not boost posts from muted users

Create matrix:
Post Event | Algolia Action | Cloud Function | Filter Applied | Client Write Risk | Status

====================================================
AGENT 14 — ACCESSIBILITY AGENT
====================================================

Audit VoiceOver, Dynamic Type, Reduce Motion, and contrast compliance across all post surfaces.

PostCard accessibility:
- author name: accessibilityLabel includes display name and @handle
- timestamp: accessibilityLabel uses relative or absolute spoken form, not "2h"
- post body text: readable by VoiceOver without custom label needed
- media attachment: accessibilityLabel describes media type and alt text if present; "Image" alone is not acceptable
- scripture chip: accessibilityLabel reads full reference e.g. "John 3:16, tap to read"
- reaction count: accessibilityLabel reads "N reactions" not just the number
- comment count: same
- action buttons (like, comment, share, save, report): all have accessibilityLabel and accessibilityHint
- post type label (prayer, testimony): announced by VoiceOver
- Covenant paywall card: accessibilityLabel explains gated state and subscribe action

Composer (CreatePostView) accessibility:
- all toolbar buttons have accessibilityLabel
- visibility picker announces current selection
- character count announces remaining characters when approaching limit
- upload progress announces percentage or completion
- error states announced via accessibilityAnnouncement

Dynamic Type:
- PostCard body text scales with Dynamic Type
- no text truncation at largest accessibility sizes that hides critical content
- media captions scale

Reduce Motion:
- feed scroll animations disabled under reduceMotion
- post publish confirmation animation disabled under reduceMotion
- upload capsule animation disabled under reduceMotion

Contrast:
- all text on media overlays meets WCAG AA (4.5:1) at minimum
- action button labels meet contrast requirements in both light and dark mode

Fix every identified gap. Do not leave TODOs.

Create matrix:
Surface | Element | accessibilityLabel | accessibilityHint | Dynamic Type | Reduce Motion | Contrast | Status

====================================================
AGENT 15 — POST NOTIFICATION ROUTING AGENT
====================================================

Audit all push notifications triggered by post activity and their in-app routing.

Notification triggers (must originate from Cloud Functions):
- post.published → followers notified (batched, not fan-out per follower in client)
- post.reacted → author notified (de-duped, max 1 per 30 min per post per reactor)
- post.commented → author + thread participants notified
- post.shared → author notified
- post.flagged → author notified (moderation action, sanitised message)
- post.removed → author notified

Notification payload contract:
- every post notification payload must include: { type, postId, actorId, timestamp }
- postId is required for deep link routing; reject if missing
- sensitive post types (prayer, care) must NOT include post body preview in notification payload

In-app routing:
- notification tap while app is closed → cold launch → PostDetailView(postId)
- notification tap while app is backgrounded → resume → PostDetailView(postId)
- notification tap while app is in foreground → present PostDetailView(postId) as sheet or push
- invalid/deleted postId in notification → show "Post not available" state, not a crash
- verify UNUserNotificationCenterDelegate (or SwiftUI equivalent) handles all three states
- verify routing lands on the correct post, not the feed root

Notification settings:
- verify user notificationsEnabled preference (set in onboarding) is checked before sending
- verify per-type notification toggles (if any) are honoured
- verify notification permission prompt timing does not conflict with onboarding flow

Reject:
- notification payload missing postId
- notification tap that lands on home feed instead of the post
- prayer/care post body text in notification preview
- client-side notification dispatch

Create matrix:
Trigger | Cloud Function | Payload Fields | iOS Handler | Routes To | Sensitive Filter | Status

====================================================
AGENT 16 — ANALYTICS + CREATOR METRICS AGENT
====================================================

Audit post impression tracking, creator analytics, and Creator OS dashboard data integrity.

Impression tracking:
- a view event must be logged when a post is visible in the feed for ≥1 second (not on scroll-past)
- view events must be written server-side (Cloud Function on Firestore trigger or callable), not directly from the iOS client
- verify no client writes to any analytics or impressions Firestore collection
- de-duplicate: max 1 view event per viewer per post per 24 hours
- verify view counts in PostCard are read from a server-aggregated field, not real-time counted from raw events

Creator metrics (visible only to the post author):
- impressions: total unique viewers
- reach: unique accounts reached
- engagement rate: (reactions + comments + shares) / impressions
- saves/bookmarks count
- verify metrics are only readable by the post's authorId (Firestore rules)
- verify metrics fields are server-written only (client cannot increment directly)

Creator OS dashboard:
- verify AmenCreatorKitHome surfaces these metrics correctly
- verify loading/empty/error states exist for each metric
- verify data is not stale (refreshed on view or within acceptable TTL)

Analytics privacy:
- verify view events do not store viewer identity in a way readable by the post author (aggregate only)
- verify analytics data is purged when the viewer's account is deleted
- verify analytics data is purged when the post is deleted

Reject:
- client writes to impressions or analytics collections
- creator viewing another user's private metrics
- metrics counters that can be gamed (no rate limit or dedup)
- stale metrics with no refresh mechanism

Create matrix:
Metric | Collection | Writer | Reader | Rules Check | Dedup | Privacy | Status

====================================================
AGENT 17 — POST EDIT FLOW AGENT
====================================================

Audit the edit-published-post workflow end-to-end.

What can be edited after publish:
- caption text: allowed
- scripture reference: allowed (re-validates against YouVersion API)
- visibility: allowed (triggers Algolia index update or removal accordingly)
- post type label (prayer/testimony/teaching): allowed if moderation approves
- media: NOT allowed after publish (media is immutable)
- post author: NOT allowed

Edit flow:
- verify an Edit button exists on PostDetailView for the post author only
- verify EditPostView (or sheet) is wired and functional, not a dead button
- verify all editable fields are present in the edit UI
- verify the save/update button calls a backend callable (not a direct Firestore write)
- verify the callable validates the edit and updates updatedAt server-side
- verify the edited post re-enters moderation review if caption changed significantly (configurable threshold)
- verify post shows "Edited" label with updatedAt timestamp after a successful edit

Edit history:
- if edit history is stored, verify it is readable only by the author and admins, not publicly
- if not stored, verify this is an explicit product decision documented in PostSystemAudit.md

Downstream sync after edit:
- Algolia index updated on edit (caption snippet refreshed)
- notification subscribers see updated content on next view (no stale cached version served indefinitely)
- shared link preview (og:tags) reflects updated caption

Reject:
- Edit button that is a TODO or haptic-only
- direct Firestore client write on edit (must be callable)
- edit that allows changing media (security: original upload must be canonical)
- edit history readable by non-authors
- Algolia not updated after a caption edit

Create matrix:
Field | Editable | Re-moderated | Algolia Sync | Edit History | Callable | Status

====================================================
AGENT 18 — TEST + VALIDATION AGENT
====================================================

Add/run tests for:
- create post (text, photo, video)
- publish post — idempotency key prevents double-post
- draft post persists across simulated crash/relaunch
- delete post — Storage media deleted, Algolia entry removed
- edit post — caption updates in Algolia, "Edited" label shown
- visibility rules — blocked/removed/pending posts inaccessible
- social graph consistency — block hides retroactively, unfollow removes from feed
- church/org post permission — non-admin cannot post as church
- Covenant-gated post — non-subscriber sees paywall, not content
- media upload rules — Google Vision flagged media enters moderationQueue
- comments/reactions rules
- AI metadata server-only
- button wiring where testable (no haptic-only, no TODO)
- no duplicate active PostCard route
- deep link cold-launch routes to correct PostDetailView
- warm-launch notification tap routes to correct PostDetailView
- notification payload missing postId shows safe error state
- faith-sensitive post types excluded from Discover and Algolia
- Algolia: post create/edit/delete reflects in index
- Algolia: prayer/care post never indexed
- Algolia: account deletion removes all author posts
- scripture reference validation rejects invalid references and shows inline error
- local draft survives simulated @State wipe (crash recovery)
- creator metrics readable only by post author (rules test)
- client write to analytics/impressions collection rejected by rules
- GDPR deletion: posts, media, Algolia entries, and analytics purged
- VoiceOver: PostCard author, media, and action buttons all have labels
- Dynamic Type: PostCard body text scales at xxxLarge

Run:
npm --prefix functions run lint -- --quiet
npm --prefix functions run test
npm exec --prefix functions -- tsc --noEmit
firebase deploy --only functions,firestore:rules,firestore:indexes,storage --dry-run

xcodebuild \
-project AMENAPP.xcodeproj \
-scheme AMENAPP \
-destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
build test

====================================================
AGENT 19 — CRITIC / QUALITY GATE
====================================================

Reject GO if:
- any create-post button is unwired
- any post action is haptic-only or TODO
- draft/removed/pending posts leak publicly
- visibility picker does not match rules
- client can write generated AI fields
- media can upload to unsafe paths
- moderation is client-only
- duplicate post systems conflict
- Liquid Glass is applied to content body cards
- cold-launch from share link does not route to the post
- notification tap does not route to the correct post
- Algolia index write occurs from device (must be server-only)
- prayer or care post is indexable or appears in Discover
- scripture reference field accepts unvalidated input
- local draft is held only in @State with no persistence layer
- submit button can be tapped twice (double-post risk)
- Google Vision safety check is client-side or bypassed
- GDPR deletion leaves orphaned posts, media, or Algolia entries
- non-admin can post as a church/org entity
- Covenant-gated full content is readable by non-subscribers via rules
- creator metrics are writable or readable by non-authors via rules
- Edit button is a dead TODO or calls direct Firestore write
- social graph block does not retroactively hide existing posts
- tests fail
- build fails

====================================================
FINAL REPORT
====================================================

Return:
- GO / GO WITH CAVEATS / NO-GO
- audit doc path
- files reviewed
- files changed
- post flow matrix
- visibility matrix (includes Covenant-gated + church permission columns)
- button wiring matrix
- backend callable matrix
- Firestore/Storage rules matrix
- media upload matrix (includes Google Vision safety pipeline column)
- AI post intelligence matrix
- dead/duplicate code matrix
- Liquid Glass matrix
- deep link + share URL matrix
- Algolia search sync matrix
- accessibility matrix (VoiceOver / Dynamic Type / Reduce Motion / Contrast)
- post notification routing matrix
- faith-sensitive post type safety matrix
- draft persistence matrix
- scripture reference integrity matrix
- post edit flow matrix
- analytics + creator metrics matrix
- GDPR / account deletion matrix
- social graph consistency matrix
- double-post / idempotency matrix
- tests run
- remaining caveats
- exact deploy commands
- rollout recommendation

IMPORTANT:
Do not stop at audit. Fix every repo-caused post/CreatePostView gap automatically.

# AMEN App — Human Verification Walkthrough Script
**Generated:** 2026-06-11 | **Agent:** 2 (Runtime Proof Orchestrator)  
**Branch:** safety-hardening | **Target:** iPhone 17 Pro simulator `313273F4-133A-42A8-9D12-8784FC893230`  
**Estimated time:** ~45 minutes total (≈2–3 min per station)

---

## Pre-flight

Before starting, build and install the app:

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
xcodebuild build \
  -project AMENAPP.xcodeproj \
  -scheme AMENAPP \
  -destination "id=313273F4-133A-42A8-9D12-8784FC893230" \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync \
  CODE_SIGNING_ALLOWED=NO
```

Then install + launch via Xcode: Product → Run (Cmd+R) with the AMEN-Verify simulator selected.

Sign in with a real Firebase test account (non-minor). The app must reach Home Feed before you begin.

**Debug flags panel path:** Settings (gear icon, bottom right of tab bar) → scroll down → "Debug" section → "Feature Flags"

---

## Station 1: Home Feed

**Flag to enable (if any):** None — feed is always-on  
**Path:** App launch → Home tab (house icon, bottom left)

**Expected behavior:**
- [ ] At least 3 post cards render within 3 seconds of sign-in
- [ ] Each post card shows author name, avatar, post text, and timestamp
- [ ] AI-label pill appears on any AI-assisted post (look for "AI-assisted" chip on card)
- [ ] Anti-doomscroll pacing: after 10–15 cards a "Take a breath" nudge appears (scroll slowly)
- [ ] Suggested Follows rail appears after card index 2 (scroll 2–3 posts down)
- [ ] No blank/white boxes or unresolved SwiftUI placeholder frames

**Doctrine check:** Feed renders without auth-dependent data loss and enforces healthy-use guardrails before user requests them.

**Screenshot column:** Core UX baseline  
**Red flag:** Blank feed after 5s, missing author avatars on all cards, or crash on scroll.

---

## Station 2: Create Post — Composer + Aegis Pre-Post Gate

**Flag to enable (if any):** `aegisPrePostReviewEnabled = true` (default ON — verify it fires)  
**Path:** Home → Compose button (pencil/plus icon, bottom center or floating)

**Expected behavior:**
- [ ] Composer sheet opens with text field focused
- [ ] Visibility picker (Everyone / Friends / Church / Private) present and tappable
- [ ] Photo attachment button opens system photo picker; selected image thumbnails in composer
- [ ] Type a post body (e.g., "Testing AMEN post safety flow") and tap Post/Submit
- [ ] Aegis Pre-Post Review sheet (`AmenPrePostReviewSheet`) fires BEFORE post submits — a review overlay appears showing content analysis
- [ ] Post submits successfully after Aegis approval; post appears at top of feed
- [ ] No crash when attaching a photo and switching visibility in the same session

**Doctrine check:** Every post creation passes through the Aegis content safety gate (aegisPrePostReviewEnabled = true). No post bypasses review.

**Screenshot column:** SafetyP0 — Aegis gate evidence  
**Red flag:** Post submits instantly with no review sheet, or Aegis sheet shows and then crashes.

---

## Station 3: Comments — Smart Reply Chips + Tone Checker

**Flag to enable (if any):** None — comment flow is always-on  
**Path:** Home Feed → tap any post → tap comment bubble icon or "Comment" label

**Expected behavior:**
- [ ] Comment thread opens showing existing comments (or "No comments yet" empty state)
- [ ] Comment composer field at bottom of screen with Send/submit button
- [ ] Smart reply chips appear above the keyboard (e.g., "Amen", "Praying", "Thanks for sharing")
- [ ] Tap a smart reply chip — text populates composer
- [ ] Type original comment; tone checker activates if inflammatory language detected (a yellow warning banner should appear before submit)
- [ ] Submit comment; it appears in thread within 2 seconds
- [ ] No crash when scrolling back to the post after commenting

**Doctrine check:** Smart reply chips reduce friction for positive engagement; tone checker prevents drive-by harassment.

**Screenshot column:** Core UX — Comments  
**Red flag:** No smart reply chips appear, or typing abusive text shows no warning and posts immediately.

---

## Station 4: Find a Church — Search + Filter

**Flag to enable (if any):** None — `findAChurchEnabled = true` (default ON)  
**Path:** Bottom tab bar → Church icon (magnifying glass with cross, or map pin icon)

**Expected behavior:**
- [ ] Find a Church tab loads showing a MapKit map with church pin clusters
- [ ] Search bar at top; type "Phoenix" — results populate within 3 seconds
- [ ] Results show church name, denomination label, distance, and a star/match rating
- [ ] Filter chip row visible (denomination: Baptist, Non-denom, Catholic, etc.) — tap one to filter
- [ ] Filtering updates results list without crashing
- [ ] Tap a church card → church detail sheet slides up with address, service times, About text
- [ ] "Get Directions" button present in detail sheet

**Doctrine check:** Church discovery is functional without any Find Church 2.0 flags enabled — baseline experience ships.

**Screenshot column:** FindChurch2 — baseline  
**Red flag:** Map loads blank, search returns 0 results for "Phoenix" (requires corpus seed), or filter tap crashes.

---

## Station 5: Find Church 2.0 — 3-Phase Liquid Glass Onboarding

**Flag to enable:** `findChurch2OnboardingEnabled = true` via Settings → Debug → Feature Flags  
**Path:** Settings → Debug → Feature Flags → toggle `findChurch2_onboarding` → return to Find a Church tab → pull-to-refresh or re-navigate

**Expected behavior:**
- [ ] `FindChurch2OnboardingView` presents as a full-screen Liquid Glass sheet on first visit after flag enable
- [ ] Phase 1: "What are you looking for?" preference picker (Worship style, community size, distance)
- [ ] Phase 2: "Tell us about your journey" (life stage picker + faith background)
- [ ] Phase 3: Summary / confirmation screen with "Find My Church" CTA
- [ ] Completing onboarding persists a `SeekerProfile` and returns to the main Find a Church list view
- [ ] SeekerProfile influences the sort order (closest match cards appear first)
- [ ] "Skip for now" link on each phase works and bypasses remaining phases

**Doctrine check:** Onboarding is non-mandatory (skip available) and stores only user-volunteered preference data (no silent profiling).

**Screenshot column:** FindChurch2 — onboarding flow  
**Red flag:** Onboarding sheet doesn't appear after flag enable, Phase 3 crashes, or skip link not present.

---

## Station 6: Berean AI — Ask Berean on Post

**Flag to enable (if any):** None — `bereanRAGEnabled = true` (default ON)  
**Path:** Home Feed → long-press any post → context menu → "Ask Berean" option

**Expected behavior:**
- [ ] Long-press context menu on a post shows "Ask Berean" option alongside Share/Report/etc.
- [ ] Tapping "Ask Berean" opens the Berean chat sheet, pre-seeded with the post content as context
- [ ] Berean responds with scripture-grounded answer within 5 seconds (or streaming response begins)
- [ ] Source attribution appears below the response (verse references, commentary citations)
- [ ] Berean AI disclosure label visible ("This response was generated by AI and may not reflect all theological traditions")
- [ ] "Save to Church Notes" and "Save to Selah" action buttons present under response
- [ ] Theology boundary active: ask a theologically off-limits question (e.g. "Is Jesus a myth?") and confirm a boundary message appears instead of a fabricated answer

**Doctrine check:** Every AI response is attributed, disclosed, and theology-bounded. No fabricated scripture citations.

**Screenshot column:** Berean AI — source attribution  
**Red flag:** No source attribution, no AI disclosure label, or boundary question returns a direct fabricated answer.

---

## Station 7: Church Notes — Scripture Detection + Save

**Flag to enable (if any):** None — `scriptureDetectionEnabled = true`, `churchNotesIntelligenceEnabled = true` (both default ON)  
**Path:** Bottom tab bar → Notes icon → tap "+" or "New Note"

**Expected behavior:**
- [ ] Church Notes composer opens with title field and body text area
- [ ] Type a body that includes a scripture reference (e.g., "I was reading John 3:16 today and…") — the reference should auto-highlight/underline within 1 second of typing
- [ ] Tap the highlighted reference — a popover appears with the verse text
- [ ] Title field: type a note title
- [ ] Tap Save — note saves and appears in the Notes list
- [ ] Tap saved note — detail view opens with scripture highlights intact
- [ ] Sermon audio capture button visible in toolbar (microphone icon)

**Doctrine check:** Scripture detection works offline (local pattern matching); save operation is atomic and does not silently fail.

**Screenshot column:** Church Notes  
**Red flag:** Scripture reference typed but not highlighted, save crashes or disappears note, or note list empty after save.

---

## Station 8: Connect Hub — AI Catch-Up Chip + Reply

**Flag to enable (if any):** `connectHubEnabled = true` (default ON); for Catch-Up chip: `messagingCatchUpEnabled` or `connectSmartBereanEnabled = true` via Debug flags if not visible  
**Path:** Bottom tab bar → Connect/Messages icon

**Expected behavior:**
- [ ] Connect Hub loads showing existing DM threads (or "Start a conversation" empty state)
- [ ] Open any existing thread (or start a new one with yourself if no threads exist)
- [ ] Scroll up through a long thread — AI Catch-Up chip ("You have X unread — catch me up") appears at the top of unread messages
- [ ] Tap Catch-Up chip — a summary banner appears with key topics from unread messages
- [ ] Composer field at bottom: type a reply and tap Send — message appears in thread immediately
- [ ] Message shows timestamp and delivery indicator (sent/delivered checkmark)
- [ ] Thread list shows typing indicator when composing

**Doctrine check:** AI catch-up is clearly labeled as AI-generated summary; DM delivery is synchronous (no silent failure).

**Screenshot column:** ConnectV2 — catch-up chip  
**Red flag:** Catch-Up chip absent even after flag enable, or Send tap does nothing and message does not appear.

---

## Station 9: Daily Brief — Digest Card + Refresh

**Flag to enable (if any):** None — `amenDailyDigestEnabled = true` (default ON)  
**Path:** Home → top of feed (below header) or Home → swipe to "Brief" tab if present

**Expected behavior:**
- [ ] Daily Brief / Digest card visible near top of home feed
- [ ] Card shows: date, scripture of the day, weather snippet (if location permission granted), and 1–3 community highlights
- [ ] Tap card → expanded digest sheet opens with full content
- [ ] In expanded sheet: "Ask Berean About This" and "Save to Church Notes" action buttons present
- [ ] Pull-to-refresh on the digest sheet — spinner appears, then content refreshes
- [ ] **Error state:** toggle airplane mode on the simulator → retry pull-to-refresh — an error message should appear ("Unable to refresh — check your connection") rather than a crash

**Doctrine check:** Digest is non-intrusive (below fold by default), actionable (Berean + Notes CTAs), and handles network loss gracefully.

**Screenshot column:** Core UX — Daily Digest  
**Red flag:** Digest card absent from feed, expanded sheet crashes, or network loss causes unhandled crash.

---

## Station 10: Safety Report — Three-Dot Menu Flow

**Flag to enable (if any):** None — reporting is always-on  
**Path:** Home Feed → any post → tap "..." (three-dot) button on post card → "Report"

**Expected behavior:**
- [ ] Three-dot menu opens showing: Report, Block [User], Mute [User], Copy Link, Share
- [ ] Tap "Report" → category selection screen appears with options: Spam, Harassment, Misinformation, Inappropriate Content, Minor Safety, Other
- [ ] Select "Spam" → optional description text field appears
- [ ] Tap "Submit Report" → confirmation screen: "Your report has been received. We review all reports within 24 hours."
- [ ] Confirmation screen has "Done" button; tapping it returns to the feed
- [ ] Separately verify "Block [User]": tap → confirmation dialog → confirm → success toast "User blocked"
- [ ] Blocked user's posts no longer appear in feed after blocking

**Doctrine check:** Safety reporting is accessible from every post card via one tap, covers minor safety as a category, and confirms submission. This provides Guideline 1.2 compliance evidence.

**Screenshot column:** SafetyP0 — report flow (3 screens)  
**Red flag:** "Report" option missing from three-dot menu, submit crashes, no confirmation screen, or minor safety category absent.

---

## Station 11: Minor-Safe DM Gate

**Flag to enable (if any):** `minorSafetyModeEnabled = true` (default ON); requires a second test account with `isMinor = true` in Firestore  
**Path:** Navigate to a minor user's profile (or create a Firestore test user with `ageTier: "minor"`)

**Setup note:** This station requires a pre-configured test minor account in Firebase. If no minor test account exists, document the UI state as "cannot fully verify without test account" and move to Station 12. The code path is: `SecureMessagingMinorGateTests` pass in CI, which provides contractual coverage.

**Expected behavior (with minor test account):**
- [ ] Navigate to minor user profile → "Send Message" button is either absent or shows as greyed-out/disabled
- [ ] Attempting to message a minor (if DM initiation is somehow accessible) shows a blocking modal: "Direct messages to this account are restricted for safety reasons"
- [ ] Modal has no bypass option — only a "Go Back" or "OK" button
- [ ] Minor user's own DM inbox shows a restricted UI banner explaining their DM settings

**Expected behavior (without minor test account):**
- [ ] Open Settings → Privacy → Minor Safety Mode is visible and reads "On" by default
- [ ] The setting shows a description of what protections are active

**Doctrine check:** Minor DM gate is fail-closed — no workaround path exists in the UI for adults to DM minors without guardian approval.

**Screenshot column:** SafetyP0 — minor gate  
**Red flag (if minor account available):** "Send Message" works without any gate, or modal has a bypass option.

---

## Station 12: Profile — Edit + Follow/Unfollow

**Flag to enable (if any):** None — `profileV2Enabled = true` (default ON)  
**Path:** Bottom tab bar → Profile icon (rightmost) for own profile; search for another user for their profile

**Expected behavior (own profile):**
- [ ] Profile loads showing: avatar, display name, bio, follower/following count, post grid
- [ ] Tap "Edit Profile" → edit sheet opens with editable name, bio, website, profile photo
- [ ] Tap profile photo → system image picker opens; select a photo → photo updates in edit sheet
- [ ] Tap "Save" → profile returns with updated bio text visible
- [ ] Post grid (media grid) shows uploaded posts in masonry/grid layout

**Expected behavior (other user profile):**
- [ ] Visit a non-followed user's profile → "Follow" button present
- [ ] Tap "Follow" → button changes to "Following" (or "Unfollow") and follower count increments
- [ ] Tap "Following"/"Unfollow" → button returns to "Follow" and count decrements
- [ ] No crash during rapid follow/unfollow toggling (tap 3x quickly)

**Doctrine check:** Profile mutation operations are immediately reflected in UI (optimistic update) and eventually consistent with Firestore.

**Screenshot column:** Core UX — Profile  
**Red flag:** Edit sheet does not save, photo picker crashes, or follow count does not update.

---

## Station 13: Selah Scripture — Full Action Row

**Flag to enable (if any):** None — `selahScriptureActionsEnabled = true`, `selahMediaOSEnabled = true` (both default ON)  
**Path:** Bottom tab bar → Selah icon (book/dove icon) → select any scripture entry

**Expected behavior:**
- [ ] Selah tab loads with scripture entries list or today's verse
- [ ] Tap any scripture entry → full scripture reader opens with verse text
- [ ] Selah action bar at bottom shows: Save, Reflect, Ask Berean, Share
- [ ] "Save to Selah" button: tap → saves entry; success toast "Saved to Selah"
- [ ] "Ask Berean": tap → Berean chat opens with scripture pre-loaded as context
- [ ] "Share": tap → share sheet opens (AmenSmartShareSheet) with recipient rail
- [ ] Berean's response in the Selah context includes scripture-to-scripture connections
- [ ] "Save to Church Notes" bridge: from Berean response, tap "Save to Church Notes" → note created

**Doctrine check:** Scripture content is always attributed with version/source; AI interpretation is offered but not substituted for the text itself.

**Screenshot column:** Core UX — Selah  
**Red flag:** Selah tab blank, action bar missing buttons, or "Ask Berean" in Selah context produces no response.

---

## Station 14: Settings — Privacy Controls Inventory

**Flag to enable (if any):** None  
**Path:** Bottom tab bar → Settings (gear icon) → Privacy section

**Expected behavior:**
- [ ] Privacy section visible in Settings with at minimum these items:
  - Block List (count of blocked users; tapping opens list)
  - Muted Accounts (count of muted users; tapping opens list)
  - Data Export Request (or "Download My Data") — link or form present
  - Minor Safety Mode toggle (visible and set to ON by default)
  - AI Personalization settings (ability to opt out of AI-powered feed ranking)
- [ ] Block List: at least an empty state "You haven't blocked anyone yet" or actual entries
- [ ] Muted Accounts: same pattern
- [ ] Data Export Request: tapping opens a form or shows "Request submitted" confirmation
- [ ] No crashes navigating between Privacy subsections

**Doctrine check:** All required privacy controls are discoverable from Settings without requiring third-party links — App Store Guideline 5.1.1 compliance.

**Screenshot column:** Core UX — Privacy Settings  
**Red flag:** "Data Export Request" missing, Block List crashes, or Privacy section absent from Settings.

---

## Station 15: Sign Out + Sign Back In — Data Persistence

**Flag to enable (if any):** None  
**Path:** Settings → scroll to bottom → "Sign Out" button

**Expected behavior:**
- [ ] Tap "Sign Out" → confirmation dialog: "Are you sure you want to sign out?"
- [ ] Confirm → app navigates to sign-in / onboarding screen within 1 second
- [ ] All user state cleared (no leftover avatar/name from previous session visible on auth screen)
- [ ] Sign back in with same credentials → app navigates to Home Feed
- [ ] Feed and profile data match pre-sign-out state (posts still visible, bio unchanged)
- [ ] Keychain identity hint present on sign-in screen ("Continue as [name]" or email pre-filled) — requires `smartAccountResumeEnabled = true` (default ON)
- [ ] No crash during sign-in after cold sign-out

**Doctrine check:** Sign-out fully clears user session (no residual PII in memory or on-screen); sign-in is frictionless via smart resume.

**Screenshot column:** Auth — sign-out/sign-in persistence  
**Red flag:** Sign-out does not navigate away from feed (session persists), or sign-in after sign-out crashes on Firebase auth state restoration.

---

## Post-Walkthrough: Flag-Gated Surfaces (Enable Individually as Time Permits)

These surfaces exist but require manual flag enable. Enable via Settings → Debug → Feature Flags, then navigate to the relevant screen.

| Surface | Flag to enable | Where to navigate |
|---|---|---|
| Connect V2 Glass UI | `connectLayoutV2Enabled = true` + `connectPolishV2Enabled = true` | Connect tab → observe glass union bar |
| Find Church 2.0 Design Refresh | `findChurch2DesignRefreshEnabled = true` | Find a Church tab → pull-to-refresh |
| Find Church 2.0 Match Badges | `findChurch2MatchExplainEnabled = true` | Find a Church → tap church card → "Why this church?" |
| Find Church 2.0 Visit Planner | `findChurch2VisitPlannerEnabled = true` | Church detail → "Plan a Visit" |
| Spiritual OS Hub | `spiritualOS_hub_enabled = true` (Remote Config only) | Home → Spiritual OS section |
| Daily Digest Expanded AI | `amenDailyDigestAIReflectionEnabled = true` (default ON) | Home → Brief card → expand |
| Note Share Viewer | `noteShareViewerEnabled = true` | Church Notes → any note → share icon |

---

## Appendix: Quick Simulator Commands

```bash
# Boot simulator
xcrun simctl boot "313273F4-133A-42A8-9D12-8784FC893230"

# Open Simulator.app
open -a Simulator

# Take a screenshot
xcrun simctl io "313273F4-133A-42A8-9D12-8784FC893230" screenshot ~/Desktop/amen_capture_$(date +%Y%m%d_%H%M%S).png

# Check app installation
xcrun simctl get_app_container "313273F4-133A-42A8-9D12-8784FC893230" com.amen.app

# Force-quit app
xcrun simctl terminate "313273F4-133A-42A8-9D12-8784FC893230" com.amen.app
```

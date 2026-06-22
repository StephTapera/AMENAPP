# Screenshot Capture Plan
**Generated:** 2026-06-11 | **Agent:** 2 (Runtime Proof Orchestrator)  
**Device:** iPhone 17 Pro simulator — `313273F4-133A-42A8-9D12-8784FC893230`  
**Filename convention:** `amen_[station]_[state]_[device].png`  
  - station: camelCase surface name (e.g., `homeFeed`, `reportFlow`)  
  - state: what is shown (e.g., `loaded`, `step1`, `confirmed`, `empty`, `error`)  
  - device: `sim17pro` for simulator, `deviceXX` for physical device

**Quick capture command:**
```bash
xcrun simctl io "313273F4-133A-42A8-9D12-8784FC893230" screenshot ~/Desktop/screenshots/amen_[name].png
```

---

## Capture Group A — Before Sign-In (no auth required)

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| A1 | `amen_launch_splash_sim17pro.png` | App launch splash screen / loading indicator | App Store presence |
| A2 | `amen_auth_signInScreen_sim17pro.png` | Sign-in screen: email/Apple Sign-In buttons, AMEN logo visible | App Store presence |
| A3 | `amen_auth_smartResume_sim17pro.png` | Sign-in with "Continue as [name]" smart-resume hint shown (after first sign-in cycle) | Core UX — Auth |

---

## Capture Group B — Home Feed & Core UX

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| B1 | `amen_homeFeed_loaded_sim17pro.png` | Feed showing 3+ post cards, header visible, bottom tab bar visible | Core UX baseline |
| B2 | `amen_homeFeed_postCard_sim17pro.png` | Single post card showing: avatar, name, text, AI label pill (on AI-assisted post) | Core UX — AI labels |
| B3 | `amen_homeFeed_suggestedRail_sim17pro.png` | Feed scrolled to show Suggested Follows rail between posts | Core UX — discovery |
| B4 | `amen_homeFeed_antiDoomscroll_sim17pro.png` | "Take a breath" / session-pacing nudge visible (scroll 10–15 posts) | SafetyP0 — wellbeing |

---

## Capture Group C — Create Post + Aegis Gate

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| C1 | `amen_composer_open_sim17pro.png` | Post composer sheet open with text field, visibility picker, attachment button visible | Core UX — create |
| C2 | `amen_composer_visibilityPicker_sim17pro.png` | Visibility picker expanded showing Everyone/Friends/Church/Private options | Core UX — create |
| C3 | `amen_composer_withPhoto_sim17pro.png` | Composer with a photo thumbnail attached, text filled in | Core UX — create |
| C4 | `amen_aegisGate_reviewing_sim17pro.png` | Aegis Pre-Post Review sheet visible mid-submission (safety analysis overlay) | SafetyP0 — Aegis gate |
| C5 | `amen_aegisGate_approved_sim17pro.png` | Aegis approval confirmation before post finalizes | SafetyP0 — Aegis gate |

---

## Capture Group D — Comments

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| D1 | `amen_comments_thread_sim17pro.png` | Comment thread open with 1+ comments visible | Core UX — comments |
| D2 | `amen_comments_smartReplyChips_sim17pro.png` | Smart reply chips visible above keyboard (Amen / Praying / Thanks for sharing) | Core UX — comments |
| D3 | `amen_comments_toneWarning_sim17pro.png` | Tone checker warning banner visible when inflammatory text is typed (if triggered) | SafetyP0 — tone |

---

## Capture Group E — Find a Church

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| E1 | `amen_findChurch_mapView_sim17pro.png` | Find a Church tab: MapKit map with church pin clusters visible | FindChurch2 — baseline |
| E2 | `amen_findChurch_searchResults_sim17pro.png` | Search "Phoenix" results list showing church cards with name/denomination/distance | FindChurch2 — baseline |
| E3 | `amen_findChurch_denominationFilter_sim17pro.png` | Filter chip row visible with one denomination chip selected, results filtered | FindChurch2 — baseline |
| E4 | `amen_findChurch_churchDetail_sim17pro.png` | Church detail bottom sheet open: address, service times, About text, Get Directions button | FindChurch2 — baseline |

---

## Capture Group F — Find Church 2.0 Onboarding (flag: findChurch2_onboarding)

Enable `findChurch2OnboardingEnabled = true` in Debug flags before capturing.

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| F1 | `amen_findChurch2_onboarding_phase1_sim17pro.png` | LG onboarding Phase 1: worship style / community size preference picker | FindChurch2 — onboarding |
| F2 | `amen_findChurch2_onboarding_phase2_sim17pro.png` | LG onboarding Phase 2: life stage + faith background picker | FindChurch2 — onboarding |
| F3 | `amen_findChurch2_onboarding_phase3_sim17pro.png` | LG onboarding Phase 3: summary confirmation screen with CTA | FindChurch2 — onboarding |
| F4 | `amen_findChurch2_matchBadge_sim17pro.png` | Smart Church Card showing MatchExplanation badge ("92% match — Your style") | FindChurch2 — match |

---

## Capture Group G — Berean AI

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| G1 | `amen_berean_contextMenu_sim17pro.png` | Long-press context menu on post showing "Ask Berean" option | Berean AI |
| G2 | `amen_berean_responseWithAttribution_sim17pro.png` | Berean response sheet: answer text + source attribution (verse refs) visible | Berean AI — attribution |
| G3 | `amen_berean_aiDisclosure_sim17pro.png` | AI disclosure label/banner visible beneath Berean response | Berean AI — disclosure |
| G4 | `amen_berean_theologicalBoundary_sim17pro.png` | Theology boundary message shown in response to an off-limits question | SafetyP0 — theology boundary |
| G5 | `amen_berean_saveActions_sim17pro.png` | "Save to Church Notes" and "Save to Selah" action buttons visible under response | Berean AI — bridges |

---

## Capture Group H — Church Notes

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| H1 | `amen_churchNotes_list_sim17pro.png` | Notes list view showing saved notes with titles and dates | Church Notes |
| H2 | `amen_churchNotes_composer_sim17pro.png` | Note composer open with title field, body text area, audio capture mic button | Church Notes |
| H3 | `amen_churchNotes_scriptureHighlight_sim17pro.png` | Body text with a scripture ref (e.g., John 3:16) highlighted/underlined | Church Notes — scripture detect |
| H4 | `amen_churchNotes_versePopover_sim17pro.png` | Verse popover showing the full text of the detected scripture reference | Church Notes — scripture detect |

---

## Capture Group I — Connect Hub

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| I1 | `amen_connect_threadList_sim17pro.png` | Connect tab: DM thread list showing thread previews | ConnectV2 — baseline |
| I2 | `amen_connect_catchUpChip_sim17pro.png` | Open thread with AI Catch-Up chip at top of unread messages | ConnectV2 — catch-up |
| I3 | `amen_connect_catchUpSummary_sim17pro.png` | Catch-Up summary banner expanded with key topics | ConnectV2 — catch-up |
| I4 | `amen_connect_composerSend_sim17pro.png` | Message composer with typed text, Send button visible | ConnectV2 — baseline |

---

## Capture Group J — Daily Brief / Digest

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| J1 | `amen_dailyDigest_feedCard_sim17pro.png` | Daily Digest / Brief card in home feed showing date + scripture + weather snippet | Core UX — digest |
| J2 | `amen_dailyDigest_expanded_sim17pro.png` | Expanded digest sheet showing full content + Berean + Church Notes action buttons | Core UX — digest |
| J3 | `amen_dailyDigest_errorState_sim17pro.png` | Error state shown after airplane mode refresh attempt | Core UX — resilience |

---

## Capture Group K — Safety Report Flow

**Critical for App Store Guideline 1.2 compliance evidence.**

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| K1 | `amen_report_threeDotsMenu_sim17pro.png` | Three-dot menu open on a post showing: Report, Block, Mute options | SafetyP0 — report surface |
| K2 | `amen_report_categorySelect_sim17pro.png` | Report category screen showing all categories incl. "Minor Safety" | SafetyP0 — report categories |
| K3 | `amen_report_description_sim17pro.png` | Report optional description text field (after selecting a category) | SafetyP0 — report form |
| K4 | `amen_report_confirmation_sim17pro.png` | Report confirmation screen: "Your report has been received" message | SafetyP0 — report confirm |
| K5 | `amen_block_confirmDialog_sim17pro.png` | Block confirmation dialog: "[User] will no longer see your posts…" | SafetyP0 — block |
| K6 | `amen_block_successToast_sim17pro.png` | "User blocked" success toast notification | SafetyP0 — block |

---

## Capture Group L — Minor Safety Gate

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| L1 | `amen_minorGate_restrictedDMButton_sim17pro.png` | Minor user profile: "Send Message" button absent or disabled/greyed-out | SafetyP0 — minor gate |
| L2 | `amen_minorGate_blockingModal_sim17pro.png` | Blocking modal: "Direct messages to this account are restricted for safety reasons" | SafetyP0 — minor gate |
| L3 | `amen_minorGate_settingsPanel_sim17pro.png` | Settings → Privacy: Minor Safety Mode setting showing "On" with description | SafetyP0 — minor gate |

---

## Capture Group M — Profile

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| M1 | `amen_profile_own_loaded_sim17pro.png` | Own profile: avatar, bio, follower/following count, post grid | Core UX — profile |
| M2 | `amen_profile_editSheet_sim17pro.png` | Edit Profile sheet with name, bio, photo edit controls | Core UX — profile |
| M3 | `amen_profile_other_followButton_sim17pro.png` | Another user's profile showing "Follow" button | Core UX — social graph |
| M4 | `amen_profile_other_followingState_sim17pro.png` | Same profile after follow: button changed to "Following/Unfollow" | Core UX — social graph |

---

## Capture Group N — Selah Scripture

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| N1 | `amen_selah_list_sim17pro.png` | Selah tab: scripture entries list or today's verse | Core UX — Selah |
| N2 | `amen_selah_reader_sim17pro.png` | Scripture reader with verse text + action bar (Save, Reflect, Ask Berean, Share) | Core UX — Selah |
| N3 | `amen_selah_bereanContext_sim17pro.png` | Ask Berean from Selah context: response with scripture-to-scripture connections visible | Berean AI — Selah bridge |
| N4 | `amen_selah_shareSheet_sim17pro.png` | Smart Share sheet open from Selah with recipient rail | Core UX — share |

---

## Capture Group O — Settings & Privacy

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| O1 | `amen_settings_main_sim17pro.png` | Main Settings screen showing Privacy section item | App Store — privacy |
| O2 | `amen_settings_privacy_list_sim17pro.png` | Privacy section: Block List, Muted Accounts, Data Export, Minor Safety Mode visible | App Store — privacy |
| O3 | `amen_settings_blockList_sim17pro.png` | Block List view (empty state or with entries) | App Store — privacy |
| O4 | `amen_settings_dataExport_sim17pro.png` | Data Export Request form or "Request submitted" confirmation | App Store — privacy |

---

## Capture Group P — Sign-Out / Sign-In Persistence

| # | Filename | What to capture | Cert column |
|---|---|---|---|
| P1 | `amen_auth_signOutDialog_sim17pro.png` | "Are you sure you want to sign out?" confirmation dialog | Auth — sign-out |
| P2 | `amen_auth_signOutComplete_sim17pro.png` | Auth/onboarding screen after sign-out (user state cleared) | Auth — sign-out |
| P3 | `amen_auth_signInRestore_sim17pro.png` | Home feed after sign back in — same posts and profile as before | Auth — persistence |

---

## Screenshot Priority Order (if time-constrained)

Prioritize in this order for App Store submission evidence:

**MUST HAVE (Guideline 1.2 + Safety):**
K1, K2, K4 (report flow), L2 (minor gate modal), C4 (Aegis gate), G4 (theology boundary), B4 (wellbeing nudge)

**MUST HAVE (Core UX):**
A2 (auth screen), B1 (home feed), C1 (composer), D2 (smart reply chips), E2 (church search), H3 (scripture highlight), N2 (Selah reader)

**SHOULD HAVE (Feature Cert):**
F1–F3 (FC2 onboarding), G2–G3 (Berean attribution + disclosure), I2 (catch-up chip), J2 (digest expanded), O2 (privacy settings)

**NICE TO HAVE:**
All remaining captures in Groups F, M, P.

---

## Total Capture Count

| Group | Count | Priority |
|---|---|---|
| A (Pre sign-in) | 3 | Should Have |
| B (Home Feed) | 4 | Must Have |
| C (Create Post) | 5 | Must Have |
| D (Comments) | 3 | Should Have |
| E (Find Church baseline) | 4 | Must Have |
| F (Find Church 2.0) | 4 | Should Have |
| G (Berean AI) | 5 | Must Have |
| H (Church Notes) | 4 | Should Have |
| I (Connect Hub) | 4 | Should Have |
| J (Daily Digest) | 3 | Should Have |
| K (Safety Report) | 6 | **Must Have — Guideline 1.2** |
| L (Minor Gate) | 3 | **Must Have — Guideline 1.2** |
| M (Profile) | 4 | Should Have |
| N (Selah) | 4 | Must Have |
| O (Settings) | 4 | Must Have |
| P (Sign-out/in) | 3 | Should Have |
| **Total** | **67** | — |

# COMMUNITIES_RECON.md

> Recon pass mandated by the Amen Communities build prompt §3. **No new file is written until this is committed.**
> Purpose: record the *real* names/systems the Communities feature must wire into — to enhance, never duplicate.
> Date: 2026-06-20 · Branch at recon time: `feature/volunteer-board-wave0`

---

## 0. Headline finding — there are already THREE "community-ish" systems

Communities-style functionality is **not greenfield**. Before any contract is written, the substrate decision below (§9) must be ruled on, because choosing wrong = building the exact parallel stack the prompt forbids.

| Existing system | What it actually is | Joinable named group w/ membership + roles? |
|---|---|---|
| **`Covenant`** (`AMENAPP/AMENAPP/Covenant/`) | Patreon/Slack-style creator membership group: tiers, rooms (channels), trust badges, privacy, moderation | **YES** — full membership + roles + rooms |
| **`CommunityOS`** (`AMENAPP/AMENAPP/CommunityOS/`) | Content-centric communities that form *around* a content object (song/sermon/etc.); discovery + health/affinity indexing | No — engagement index, not a joinable registry |
| **`AmenCommunityHub`** (`AMENAPP/AMENAPP/AmenCommunityHub.swift`) | Object-hub that forms around a canonical content object; `AmenObjectHubMembership` | Partial — "membership" = engagement with content, not a topic group |

`SavedCommunitiesService` already enumerates community types as **`covenant | hub | ark`** — i.e. the app's own model already treats "a community" as polymorphic across these.

---

## 1. Post model + post card + feed (reuse target for community feeds)

| Capability | Real name | Path | Notes |
|---|---|---|---|
| Post model | `struct Post` | `AMENAPP/PostsManager.swift:109` | No `communityId` field today → add one optional field; do **not** fork. `category: PostCategory`, `topicTag: String?`, `visibility: PostVisibility` already exist. |
| Post category | `enum PostCategory` | `AMENAPP/PostsManager.swift:260` | openTable/testimonies/prayer/tip/funFact |
| Post card view | `struct PostCard` | `AMENAPP/PostCard.swift:20` | Canonical card; renders a `Post`. Reuse as-is for community feed rows. |
| Post header context tag | `AmenFeedContextLabel` | `AMENAPP/AMENAPP/AmenFeedContextLabelSystem.swift:168` | **Already has `communityId: String?` (line ~179)** and a `communityQuestion` context type → the "Posted in [Community]" tag is wireable with **no fork**. |
| Feed service + pagination | `FirebasePostService.shared` | `AMENAPP/FirebasePostService.swift:420` | Cursor pagination via `lastDocuments[categoryKey]`, `pageSize = 25`. Add a `community_<id>` cursor key; reuse the loader. |
| Composer | `CreatePostView` + `PostsManager.createPost(...)` | `AMENAPP/CreatePostView.swift`, `AMENAPP/PostsManager.swift:964` | Audience/visibility already pluggable (church-tag sheet precedent). Add a community scope the same way. |

## 2. Profile (reuse target for "Communities on profile")

| Capability | Real name | Path |
|---|---|---|
| Profile screen | `ProfileView` | `AMENAPP/ProfileView.swift` (tabs enum ~`:33`, content switch ~`:2114`) — add a `communities` tab/section here, do not build a new profile. |
| User model | `struct User` | `AMENAPP/UserService.swift:39` |
| User model (alt) | `struct UserModel` | `AMENAPP/UserModel.swift:14` |

## 3. DM / Share (reuse target for CommunityShareSheet)

| Capability | Real name | Path |
|---|---|---|
| OS share sheet wrapper | `ShareSheet` (`UIViewControllerRepresentable`) | `AMENAPP/ShareSheet.swift:15` |
| In-app share view precedent | `AmenShareSheet` | `AMENAPP/ShareSheet.swift:62` |
| Share-to-DM | `ShareToMessagesSheet` | `AMENAPP/ShareToMessagesSheet.swift:11` |
| Messaging service | `FirebaseMessagingService.shared` | `AMENAPP/FirebaseMessagingService.swift:79` (`sendMessage(...)` ~`:1295`) |

## 4. Notifications

| Capability | Real name | Path |
|---|---|---|
| Notification service | `NotificationService.shared` | `AMENAPP/NotificationService.swift:20` |
| Notification model + types | `AppNotification`, `enum NotificationType` | `AMENAPP/NotificationService.swift:986`, `:1110` — add `.community*` cases, don't fork. |
| Smart batching | `SmartNotificationService` | `AMENAPP/SmartNotificationService.swift:49` |

## 5. Moderation / reporting = GUARDIAN / TrustOS (route into, do not rebuild)

| Capability | Real name | Path |
|---|---|---|
| Risk context object | `struct SocialContext` (+ `SocialSurfaceContext.Kind`) | `AMENAPP/ActionThreads/SocialSpineModels.swift:7` — `Kind` enum already has `group`, `room`, `community` visibility; **extend `Kind`/`Visibility` for community surfaces here**. |
| Human-review queue | `guardianReviewQueue` collection | `functions/berean/feedbackCapture.ts:140` — community reports route in with a `type`/`sourceRef` scope. |
| Content moderation CF | `moderateContent` / `analyzeContentWithAI` | `functions/aiModeration.js:164` — fail-closed (holds for human review on AI-unavailable). |
| Injection sanitizer (Aegis) | `sanitizeImportText` | `functions/context/contextSanitize.ts` |
| Crisis short-circuit | GUARDIAN hook | `functions/berean/constitutionalPipeline.ts` (P0-06) |

## 6. Privacy taxonomy + MEDIA-GATE

- **PRIVACY-CORE is NOT a literal Z1–Z5 enum.** Real model = 8-tier permission-precedence + visibility levels documented in `Docs/privacy-model.md` (visibility: public / followers / trustedCircle / church / space / private). Field-tagging in TS contracts will use a `// PRIVACY-ZONE:` comment convention mapped to these tiers.
- **MEDIA-GATE** = `MediaSafetyGateway.shared.evaluate(...)` (decision enum: allow / allowWithAsyncScan / hold / reject / freeze), entry referenced in `AMENAPP/FirebaseMessagingService.swift`. Metadata strip happens here.
- `NSPrivacyTracking=false` spine: see Privacy Manifest notes (PrivacyInfo.xcprivacy).

## 7. Liquid Glass design system (match, no-glass-on-glass)

| Component | Real name | Path |
|---|---|---|
| Material intensity + solid fallback | `enum AmenGlassMaterialIntensity` (`.solidFallback`) | `AMENAPP/AmenLiquidGlassSurface.swift:8` |
| Glass action pill | `AmenLiquidGlassPill<Content>` | `AMENAPP/AmenLiquidGlassPill.swift:13` |
| Glass sheet/overlay | `AmenLiquidGlassCardOverlay<Content>` | `AMENAPP/AmenLiquidGlassCardOverlay.swift:17` |
| Glass surface + low-power/reduce-transparency mgr | `LiquidGlassSurface`, `LiquidGlassMaterialManager` | `AMENAPP/AMENAPP/AMENAPP/LiquidGlass/BereanLiquidGlassSystem.swift:4` |
| Capsule modifier | `.amenLiquidGlassCapsuleSurface(...)` | `AMENAPP/AmenLiquidGlassComponents.swift:53` |
| Tab bar | `AMENTabBar` / `enum AMENTab` | `AMENAPP/AMENTabBar.swift:15` |
| A11y fallback pattern | `@Environment(\.accessibilityReduceTransparency / ReduceMotion / colorSchemeContrast)` → solid fill / cross-fade | established across the glass files above |

## 8. Auth, flags

- **Auth/current user:** no shared env object; canonical is `Auth.auth().currentUser?.uid`; services like `UserService.shared`, `FollowService.shared` injected as `@ObservedObject`.
- **Feature flags — TWO systems exist:**
  - `AMENFeatureFlags.shared` (`AMENAPP/AMENFeatureFlags.swift`) — central, Remote Config keys in `remoteconfig.template.json`, **defaults OFF for new features**. *(Add the 5 Communities flags here.)*
  - `CommunityOSFlagService` (`AMENAPP/AMENAPP/CommunityOS/CommunityOSFeatureFlags.swift`) — separate, defaults **TRUE**. Do **not** put Communities flags here (wrong default posture).
- **TS contracts source of truth:** `Backend/functions/src/contracts/*.ts` (`connect.ts`, `volunteer.ts`); Swift mirrors field-for-field. New file → `Backend/functions/src/contracts/communities.ts`.
- **Firestore rules:** root `firestore.rules` (owner: T&S Lead; human-gated deploy).

## 9. OPEN RULING REQUIRED (blocks Wave 0 contracts) — substrate decision

The prompt's #1 rule (enhance, don't duplicate) + §13 stop condition force this decision **before** any contract is written:

- **Option A — Extend `Covenant`** (`AMENAPP/AMENAPP/Covenant/CovenantModels.swift`): reuse `Covenant` + `CovenantMembership` (roles creator/admin/moderator/member) + `CovenantRoom` + moderation + privacy. Add flair, rules, resources, community events, profile-display. *Risk:* Covenant is monetization/creator-tier framed; bending it to free, secular topic-communities (tech/design/health/family) may distort it and couple Communities to paid tiers.
- **Option B — New lightweight `Community` entity alongside** Covenant/Hub/Ark (it becomes the 4th `SavedCommunityType`). Own membership model decoupled from paid tiers; still routes posts→existing Post system, moderation→GUARDIAN, glass→existing kit, share→existing DM. *Risk:* must be vigilant it reuses primitives and doesn't re-implement membership/rooms that Covenant already has.

**This recon does not presume the answer.** See the founder-ruling raised alongside this commit.

---

## Build-state note
At recon time the **build broker `.build-lock` is HELD** by another agent (`liquid-glass-redesign`). Per §2.1 no build may run until released; the build→commit→hash gate for Wave 0 is therefore pending lock availability. This recon doc requires no build and is committed independently.

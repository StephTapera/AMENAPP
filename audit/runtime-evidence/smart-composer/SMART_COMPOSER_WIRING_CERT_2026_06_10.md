# Smart Composer Runtime Evidence + Wiring Cert

Date: 2026-06-10 America/Phoenix
Updated: 2026-06-11 America/Phoenix
Lane: Codex — Smart Composer surfaces
Implementation commit: `7bec341f Add smart composer review gate`

## Runtime Proof Status

Runtime screenshots for the four owed Smart Composer surfaces are **blocked by auth/onboarding state**, not by the Smart Composer implementation.

Blocker:
- `BuildProject` completed green on 2026-06-11.
- `RunProject` launched the app successfully (`launchSessionReference: 7b8f93f300`, process `1561`).
- The shared verification simulator stops at the auth landing surface.
- `Skip — Test Mode` is intentionally guarded by `AuthenticationViewModel.bypassAuthForTesting()` and refuses to continue unless `Auth.auth().currentUser?.uid` already exists.
- No real Firebase test user is present on the erased shared simulator, so runtime capture cannot reach `CreatePostView` without weakening the real-user auth gate.

Captured blocker artifact:
- Auth blocker screenshot: `/var/folders/v6/7zm8wr6d7hq4wkm528s6q94m0000gn/T/ActionArtifacts/8C6507B5-5558-4F9E-8ED0-3AE7669191BD/DeviceInteractionSynthesize/Smart Composer Proof 0611 Attach B/Smart Composer Proof 0611 Attach B-08_03_01_490/screenshot.png`
- Auth blocker hierarchy: `/var/folders/v6/7zm8wr6d7hq4wkm528s6q94m0000gn/T/ActionArtifacts/8C6507B5-5558-4F9E-8ED0-3AE7669191BD/DeviceInteractionSynthesize/Smart Composer Proof 0611 Attach B/Smart Composer Proof 0611 Attach B-08_03_01_490/hierarchy.txt`
- Green build log: `/var/folders/v6/7zm8wr6d7hq4wkm528s6q94m0000gn/T/ActionArtifacts/BuildProject/BuildProject-Log-20260611-061300.txt`
- Launch proof: Xcode `RunProject` returned `The app was launched successfully` with launch session `7b8f93f300`.

## Total Control Wiring

| Surface | Control | Destination / action | Disposition | Screenshot |
|---|---|---|---|---|
| CreatePostView topic tag area | Suggested topic chip | Sets `selectedTopicTag` from `PostComposerSmartDetectionService.detectTopicTags` | WIRED | BLOCKED — auth gate before composer |
| SmartPostContextTray | Link chip | Sets `linkURL` and calls `linkController.handleTextChange` | WIRED | BLOCKED — auth gate before composer |
| SmartPostContextTray | Topic tag chip | Sets `selectedTopicTag` to detected tag | WIRED | BLOCKED — auth gate before composer |
| SmartPostContextTray | Audience/privacy chip | Opens `SmartComposerReviewSheet` | WIRED | BLOCKED — auth gate before composer |
| CreatePostView warning icon | Warning triangle with dot | Opens `SmartComposerReviewSheet` when `smartComposerReviewNotes` is non-empty; otherwise toggles sensitive content | WIRED | BLOCKED — auth gate before composer |
| SmartComposerReviewSheet | Make followers only | Sets `postVisibility = .followers` | WIRED | BLOCKED — auth gate before composer |
| SmartComposerReviewSheet | Limit replies | Sets `commentPermission = .followersOnly` and `allowComments = true` | WIRED | BLOCKED — auth gate before composer |
| SmartComposerReviewSheet | Add content warning | Sets `hasSensitiveContent = true` and fills default reason when empty | WIRED | BLOCKED — auth gate before composer |
| SmartComposerReviewSheet | Choose topic | Opens existing `TopicTagSheet` | WIRED | BLOCKED — auth gate before composer |
| SmartComposerReviewSheet | Preview link | Opens existing `LinkInputSheet` | WIRED | BLOCKED — auth gate before composer |
| SmartComposerReviewSheet | Add verse context | Opens existing verse picker drawer | WIRED | BLOCKED — auth gate before composer |
| CreatePostView post buttons | Publish / schedule | Routes through `requestPublishFromSmartComposer`; opens review before publish when confirmation is required, otherwise proceeds to existing publish path | WIRED | BLOCKED — auth gate before composer |
| SmartComposerReviewSheet confirmation toolbar | Post anyway | Sets `smartComposerRiskAcknowledged = true`, dismisses review, then calls `publishPost()` | WIRED | BLOCKED — auth gate before composer |

## Owed Runtime Screenshots

Still owed after a real Firebase test user is available on the shared simulator:
- Topic chips suggested from text.
- Warning review sheet opened from warning icon.
- Link/audience notes visible in the review sheet.
- Post confirmation gate for a personal/public/open-replies draft.

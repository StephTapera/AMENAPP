# Smart Composer Runtime Evidence + Wiring Cert

Date: 2026-06-10 America/Phoenix
Lane: Codex — Smart Composer surfaces
Implementation commit: `7bec341f Add smart composer review gate`

## Runtime Proof Status

Runtime screenshots for the four owed Smart Composer surfaces are **blocked in the current dirty workspace**.

Blocker:
- `DeviceInteractionInstallAndRun` failed with `Launch session has not been found`.
- `RunProject` then failed to build due unrelated current compile errors in `AMENAPP/MusicContentLayer/MusicContentContracts.swift`.
- Reported duplicate redeclarations: `ContentAttachmentType`, `ContentAttachment`, `PostIntentType`, `ProfileResourceItem`, `ProfileResourceCategory`, `FaithGraphNodeType`, `AmenPulseDigestItemType`.

Captured blocker artifact:
- Screenshot: `/var/folders/v6/7zm8wr6d7hq4wkm528s6q94m0000gn/T/ActionArtifacts/09C0EA48-7FF2-4CCA-BC79-3CB3E31C223A/DeviceInteractionSynthesize/Smart Composer Proof/Smart Composer Proof-23_50_12_876/screenshot.png`
- Hierarchy: `/var/folders/v6/7zm8wr6d7hq4wkm528s6q94m0000gn/T/ActionArtifacts/09C0EA48-7FF2-4CCA-BC79-3CB3E31C223A/DeviceInteractionSynthesize/Smart Composer Proof/Smart Composer Proof-23_50_12_876/hierarchy.txt`
- Build log: `/var/folders/v6/7zm8wr6d7hq4wkm528s6q94m0000gn/T/ActionArtifacts/09C0EA48-7FF2-4CCA-BC79-3CB3E31C223A/RunProject/RunProject-Log-20260610-234945.txt`

## Total Control Wiring

| Surface | Control | Destination / action | Disposition | Screenshot |
|---|---|---|---|---|
| CreatePostView topic tag area | Suggested topic chip | Sets `selectedTopicTag` from `PostComposerSmartDetectionService.detectTopicTags` | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartPostContextTray | Link chip | Sets `linkURL` and calls `linkController.handleTextChange` | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartPostContextTray | Topic tag chip | Sets `selectedTopicTag` to detected tag | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartPostContextTray | Audience/privacy chip | Opens `SmartComposerReviewSheet` | WIRED | BLOCKED — current workspace compile failure before app launch |
| CreatePostView warning icon | Warning triangle with dot | Opens `SmartComposerReviewSheet` when `smartComposerReviewNotes` is non-empty; otherwise toggles sensitive content | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartComposerReviewSheet | Make followers only | Sets `postVisibility = .followers` | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartComposerReviewSheet | Limit replies | Sets `commentPermission = .followersOnly` and `allowComments = true` | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartComposerReviewSheet | Add content warning | Sets `hasSensitiveContent = true` and fills default reason when empty | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartComposerReviewSheet | Choose topic | Opens existing `TopicTagSheet` | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartComposerReviewSheet | Preview link | Opens existing `LinkInputSheet` | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartComposerReviewSheet | Add verse context | Opens existing verse picker drawer | WIRED | BLOCKED — current workspace compile failure before app launch |
| CreatePostView post buttons | Publish / schedule | Routes through `requestPublishFromSmartComposer`; opens review before publish when confirmation is required, otherwise proceeds to existing publish path | WIRED | BLOCKED — current workspace compile failure before app launch |
| SmartComposerReviewSheet confirmation toolbar | Post anyway | Sets `smartComposerRiskAcknowledged = true`, dismisses review, then calls `publishPost()` | WIRED | BLOCKED — current workspace compile failure before app launch |

## Owed Runtime Screenshots

Still owed after the current build regression is cleared:
- Topic chips suggested from text.
- Warning review sheet opened from warning icon.
- Link/audience notes visible in the review sheet.
- Post confirmation gate for a personal/public/open-replies draft.

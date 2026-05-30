# Per-Media Captions Contract

Status: Locked. Agents A4-A7 consume this.

## Flags
perMediaCaptionsEnabled=false, perMediaCaptionEducationEnabled=false
perMediaCaptionModerationEnabled=true, perMediaCaptionAltTextEnabled=true
perMediaCaptionScriptureRefsEnabled=true, perMediaCaptionIncrementalModerationEnabled=true

## Moderation States (MediaCaptionModerationState in MediaMetadataDraftModels.swift)
not_required, pending (fail-closed), approved, rejected (hidden), removed (no post-caption fallback)

## Models
PublishedMediaCaptionModeration in PostMediaModels.swift: status, reason?, checkedAt?
PostMediaItem new fields: perMediaCaption?, altText?, captionModeration?, scriptureRefs[], reflectionPrompt?
FrameCaptionDraft->PostMediaItem: text->perMediaCaption, altText->altText, scriptureRefs->scriptureRefs

## Callables
publishPostWithMedia, moderateMediaCaption, updatePostMediaCaptions, generateAltText
All: requireAuth+requireAppCheck. Owner-only on update.

## Validation
perMediaCaption<=2200, altText<=1000, scriptureRefs<=10, reflectionPrompt<=500

## Error Codes
media-caption-too-long: Caption is too long. Shorten it before posting.
media-caption-rejected: One or more captions could not be approved. Review the flagged items.
validation-failed: Something looks off. Check your captions and try again.
network: Connection issue. Please try again.
rate-limited: Too many requests. Please wait a moment and try again.

## Safety Rules
Server derives status only. Ignore client captionModeration. Fail-closed on timeout.
Combined-payload check. Alt text + reflectionPrompt always moderated.

## Analytics Events
per_media_caption_added, per_media_caption_moderated, per_media_caption_rejected,
carousel_caption_swiped, alt_text_generated, education_modal_shown, education_modal_dismissed,
post_published_with_captions. Never log raw text. uid is hashed.

## Fallback Law
1. Flag OFF -> post caption only
2. approved -> show perMediaCaption
3. rejected/removed -> collapse (no post-caption substitution)
4. nil/no moderation -> post caption
5. no post caption -> collapse

## Education Modal Gate
Both flags on + >=2 media selected + not seen. Failures never block post.

## Backward Compat
All new PostMediaItem fields optional. Flag OFF = no new reads/writes.
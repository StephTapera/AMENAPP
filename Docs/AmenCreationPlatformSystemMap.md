# Amen Creation Platform System Map

## Product Surfaces

- Home Feed: keep legacy posts canonical; add `ContentNode` render adapters when the model is enabled.
- Composer: keep `CreatePostView` as fallback; `AmenCreateHubView` and `AmenAdaptiveComposerView` are gated by `universalCreateEnabled`.
- Media Viewer: reuse `AmenMediaDetailView`; route future `ContentNode.mediaRefs` through existing media detail and caption infrastructure.
- Church Notes: bridge existing note blocks to `ContentBlock`; do not replace Church Notes storage until adapter tests pass.
- Berean AI: use contextual actions and AI review sheets as embedded AI, not a separate noisy assistant.
- Creator Tools: reuse existing Creator backend project pipeline before adding new design/video export functions.
- Communities: keep Covenant/community systems canonical; use `community` visibility on `ContentNode` only after server filtering is complete.
- Search/Profile/Feeds: consume universal content only after moderation and visibility filters are server-enforced.

## Adaptive Liquid Glass Direction

- Liquid Glass evolves from static material to adaptive behavior.
- Use glass for controls, tab/navigation layers, action trays, smart pills, media chrome, composer controls, and contextual panels.
- Do not use glass behind dense reading text, note bodies, or stacked cards.
- Prefer opacity/material swaps over animated blur radius.
- Respect Dynamic Type, Reduce Motion, Reduce Transparency, Increase Contrast, Low Power Mode, and VoiceOver.

## Surface Guidance

- Home Feed: Vanishing Chrome, Adaptive Interface Density, Intentive Controls, humane session pacing.
- Berean AI: AI-native contextual actions, selection trays, source-aware summaries, no chatbot-first takeover.
- Church Notes: calmer reading/editing density, autosave clarity, block adapters, AI suggestions requiring user acceptance.
- Selah: Semantic Atmosphere, Temporal Interfaces, reduced stimulation at night, reflective action priority.
- Messaging: Intentive reply tools, safety nudge, thread summary, private reflection alternative.
- Media Viewer: Vanishing Chrome, velocity-aware controls, explain/save/share actions only when relevant.
- Sharing: smart destination suggestions with clear privacy and disabled/unavailable states.
- Profiles: content-first media grid, restrained tabs, private/blocked/empty states.
- Discover/Search: semantic filters, related content, visibility-safe results.
- Composer: adaptive toolbar, preview before publish, no auto-publish from AI.
- iPad/VisionOS readiness: keep navigation native and content panes separable; avoid custom rendering engines.

## Apple Approval Read

Likely approved:
- Native controls, restrained materials, accessible fallbacks, server-side moderation, App Check, clear AI labeling, user-confirmed AI output.

Likely rejected:
- Fake buttons, UI claiming unavailable backend functions exist, opaque AI publishing, heavy blur stacks, poor contrast, inaccessible custom controls, client-owned moderation.

## Firestore Paths Added

- `content/{contentId}`
- `content/{contentId}/metrics/aggregate`
- `users/{uid}/drafts/{draftId}`

## Backend Callables Added

- `createContentNode`
- `updateContentNode`
- `publishContentNode`
- `deleteContentNode`
- `getContentNode`
- `saveContentDraft`
- `getContentDraft`
- `deleteContentDraft`
- `publishDraftToContentNode`

## Release Position

The platform foundation is additive and safe with flags off. The full platform is not ready for broad release until rules tests, backend tests, iOS build validation, and end-to-end flow audits pass.


# Berean Conversational OS Audit

## Status

GO WITH CAVEATS for the Berean composer UI pass.

This pass implements the compact, calmer Berean interaction surface in the existing SwiftUI composer and preserves all existing modes, callbacks, and flow ownership. It does not claim the full backend Conversational OS is production-ready; backend-heavy intelligence remains feature-flagged off.

## UX Philosophy

Berean should feel like a contemplative spiritual intelligence surface, not a generic chatbot or operational dashboard. The UI should prioritize presence, scripture, reflection, prayer, and conversation. Liquid Glass is reserved for interaction surfaces: composer, contextual controls, voice surfaces, action trays, and mode capsules.

## Interaction Hierarchy

1. Composer: primary object and emotional center.
2. Text field: quiet, direct, scripture-native prompt language.
3. Contextual controls: plus, tools, mic, send, and stop shown only when useful.
4. Action tray: compact contextual commands, no persistent toolbar sprawl.
5. Mode control: all modes preserved, compact selected-label treatment.

## Implemented In This Pass

- `BereanComposerBar` shell reduced in padding, width, shadows, and highlight intensity.
- Right-side controls now collapse contextually: mic when empty, send when typing, stop while streaming, prayer pulse while voice-ready.
- Voice state now uses a warm breathing pulse instead of waveform-heavy motion.
- Action tray buttons are smaller with lower contrast, tighter padding, and softer material.
- `BereanModeControlBar` keeps Ask, Reason, Create, and Reflect while reducing label scale and shadow weight.
- Feature flags added for requested Berean/Conversation OS gates with conservative defaults.

## Liquid Glass Rules

GO:
- Berean composer
- Mode capsule
- Contextual action tray
- Voice prayer pulse
- Floating status pills

GO WITH CAVEATS:
- Recap capsules, organizational memory banners, unresolved discussion chips, and topic clusters require backend permission validation before enabling.

NO-GO:
- Full-screen blur
- Stacked transparent cards
- Neon/glowing AI chrome
- Admin/moderation dashboards
- Upload and active search flows

## Motion Principles

- Slow, breathing, low-amplitude motion.
- Reduce Motion uses static pulse sizing instead of repeated animation.
- Voice prayer should feel calm and intimate, not waveform-chaotic.

## Accessibility Rules

- Preserve VoiceOver labels and hints for all icon-only controls.
- Keep modes reachable even when visual labels are compacted.
- Honor Reduce Motion for pulse animation.
- Keep text visible with `lineLimit` and `minimumScaleFactor` in compact action buttons.

## Feature Flag Matrix

| Flag | Default | Reason |
| --- | --- | --- |
| `bereanConversationalOSEnabled` | off | Backend/platform integration not fully shipped in this pass. |
| `ambientConversationIntelligenceEnabled` | off | Requires permission-safe recap and memory surfaces. |
| `bereanLiquidGlassComposerEnabled` | on | Local UI-only composer work is implemented. |
| `contextualRecapCapsulesEnabled` | off | Requires backend summaries and provenance. |
| `unresolvedDiscussionTrackingEnabled` | off | Requires extraction accuracy and rules coverage. |
| `organizationalMemoryEnabled` | off | Existing flag remains off for privacy-safe rollout. |
| `semanticTopicClusteringEnabled` | off | Requires backend clustering and access filtering. |
| `prayerAwareComposerEnabled` | on | Local prayer-aware voice pulse is implemented. |
| `selahConversationIntelligenceEnabled` | off | Selah surface integration is deferred. |
| `conversationOSDebugTelemetryEnabled` | off | Debug-only. |

## Surface Map

GO:
- Berean composer and Berean mode controls.

GO WITH CAVEATS:
- Selah, Daily Digest, Spaces, Church discussions, Organization hubs, Creator communities, classroom/event/leadership discussions, and catch-up views after backend/rules validation.

NO-GO:
- Moderation consoles, admin inboxes, upload flows, active search, and operational dashboards.

## Rollout Order

1. Ship compact Berean composer and mode control UI behind `bereanLiquidGlassComposerEnabled`.
2. Validate accessibility, build, and device screenshots.
3. Wire recap/memory services only after permission validation and provenance labels are enforced.
4. Enable backend-heavy flags one at a time with Remote Config cohorts.
5. Monitor debug telemetry only in internal builds.

## Remaining Caveats

- Uploaded inspiration images were unavailable from the Photos temp paths, so this audit uses the written design spec and existing AMEN/Berean code.
- Firestore functions, rules, indexes, and backend summarization services were not created in this compact UI pass.
- Full xcodebuild test/deploy validation depends on local simulator and Firebase environment availability.

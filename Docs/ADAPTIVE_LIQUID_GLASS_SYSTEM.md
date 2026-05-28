# Amen Adaptive Liquid Glass System

This guide turns Amen's Liquid Glass direction into implementation rules for the current app. It is intentionally conservative: glass is a control layer, not a content treatment.

## Core Rules

- Use native SwiftUI materials and Liquid Glass APIs first.
- Put glass on navigation, composers, floating controls, media chrome, toolbars, menus, action trays, and sheets.
- Do not put glass on every feed card, long-form reading area, or large scrolling surface.
- Do not stack translucent surfaces directly together.
- Use opacity/material swaps for scroll response; do not animate blur radius.
- Respect Reduce Motion, Reduce Transparency, Dynamic Type, Increased Contrast, VoiceOver, Low Power Mode, and legibility before visual effect.
- Keep motion short, damped, and purposeful.
- Keep AI actions contextual and quiet, surfaced where the user already has intent.

## Canonical Primitive

`AmenAdaptiveLiquidGlass` is the default reusable primitive for small adaptive control surfaces.

Use roles deliberately:

- `navigation`: floating tabs, compressed headers, compact route controls.
- `composer`: text inputs and publishing controls.
- `floatingControl`: pills, chips, safety labels, media controls, contextual actions.
- `sheetChrome`: action sheets and bottom-sheet headers.
- `mediaChrome`: playback, captions, sharing, and viewer controls.

This primitive handles reduced transparency fallback, reduced motion fallback, subtle edge lighting, ambient tint, selected states, and pressed states without heavy blur stacks.

## Surface Map

### Home Feed

- Fit: vanishing chrome, adaptive density, humane feed boundaries, algorithm transparency.
- Evolve: permanent feed controls into compact mode pills and contextual "Why am I seeing this?" actions.
- Remove: glass cards for every post, infinite-scroll-only behavior, noisy recommendation explanations.
- AI: embedded in ranking explanation, safety labels, and topic controls.
- Glass: feed controls only; content remains solid and readable.
- Apple-likely approve: native list behavior, restrained floating controls. Reject: stacked glass over every card.
- Performance: one fixed header/control glass layer, no scrolling blur fields.
- Accessibility: feed controls expose labels/actions; boundary cards stay solid.
- Platforms: iPad sidebar modes, visionOS floating control layer, landscape split detail.
- Simplicity: default feed stays clean; controls appear when needed.

### Berean AI

- Fit: intentive controls, AI-native architecture, adaptive density.
- Evolve: AI from a separate destination into selected-text actions, study context, and source cards.
- Remove: persistent assistant chrome competing with scripture/content.
- AI: Ask Berean, summarize, compare context, and save reflection appear after selection or pause.
- Glass: contextual action tray and composer chrome only.
- Apple-likely approve: native text selection and menus. Reject: always-on chatbot overlays.
- Performance: reuse a single action tray surface.
- Accessibility: all AI actions must be reachable from rotor/context menu.
- Platforms: iPad inspector, visionOS side context, wearable handoff summaries.
- Simplicity: AI appears as a tool, not a personality layer.

### Church Notes

- Fit: temporal interface, adaptive density, private reflection.
- Evolve: note capture controls into composer glass and focused modes.
- Remove: dense toolbars during reading/listening.
- AI: transcription, clip suggestions, summaries, and claim context attach quietly.
- Glass: recording/composer controls and review sheet chrome.
- Apple-likely approve: native recording affordances. Reject: animated visualizer clutter.
- Performance: static progress edges, no full-screen blur.
- Accessibility: clear recording status and review actions.
- Platforms: iPad two-column notes, landscape editor, visionOS floating note tray.
- Simplicity: capture first, intelligence second.

### Selah

- Fit: semantic atmosphere, temporal interfaces, humane computing.
- Evolve: pauses into calm overlays with explicit user choice.
- Remove: shaming streaks, guilt-based dashboards, forced animations.
- AI: reflection routing and private prompts, not diagnosis.
- Glass: bottom controls and pause overlay chrome only.
- Apple-likely approve: quiet wellbeing controls. Reject: manipulative retention loops.
- Performance: fade/scale overlay, no animated blur.
- Accessibility: reduced-motion static transitions; crisis resources use plain text.
- Platforms: wearable check-in handoff, iPad reflection view.
- Simplicity: one primary action and clear alternatives.

### Messaging

- Fit: intentive controls, safety-first adaptive action surfaces.
- Evolve: composer into a protected glass capsule with safety state.
- Remove: unsafe message previewing in notifications and high-risk content chips.
- AI: DM risk firewall, rewrite guard, panic flow, and safe boundary replies.
- Glass: composer and action tray only; message bubbles stay legible.
- Apple-likely approve: clear privacy and safety prompts. Reject: exposing risk logic to suspected abusers.
- Performance: one composer material, one sheet material.
- Accessibility: panic/report actions have explicit labels and confirmation states.
- Platforms: iPad conversation/sidebar, visionOS floating composer, wearable safe alerts.
- Simplicity: normal chats remain normal until risk appears.

### Media Viewer

- Fit: vanishing chrome, media chrome, fluid layer morphing.
- Evolve: controls fade at rest and reappear on tap/pause.
- Remove: permanent toolbars covering media.
- AI: integrity labels, captions, source context, and creator tools as contextual chips.
- Glass: media chrome only.
- Apple-likely approve: Photos-like immersive chrome. Reject: heavy lensing/warping.
- Performance: material opacity swaps, static highlights, no live distortion.
- Accessibility: controls remain discoverable with VoiceOver.
- Platforms: visionOS-ready layered controls and landscape full bleed.
- Simplicity: content dominates.

### Sharing

- Fit: intentive controls and humane routing.
- Evolve: share sheet toward safer destination suggestions.
- Remove: viral-forwarding defaults for sensitive content.
- AI: suggests private share, prayer request, Church Notes, or Selah when appropriate.
- Glass: compact share tray only.
- Apple-likely approve: native share patterns. Reject: dark-pattern resharing pressure.
- Performance: system sheet where possible.
- Accessibility: every route is text-labeled.
- Platforms: cross-device continuation.
- Simplicity: primary safe route first.

### Profiles

- Fit: adaptive density and trusted safety controls.
- Evolve: safety/report controls into clear contextual menus.
- Remove: hidden or multi-step abuse controls.
- AI: profile risk surfaces only as user-safe controls, never as scores.
- Glass: profile actions and menu chrome, not the profile body.
- Apple-likely approve: transparent controls. Reject: public reputation scores.
- Performance: no glass over profile feed grid.
- Accessibility: block/report/trusted contact controls are explicit.
- Platforms: iPad profile inspector.
- Simplicity: identity and safety are easy to find.

### Discover

- Fit: user-controlled algorithms, why-seen cards, adaptive density.
- Evolve: discovery into mode-aware recommendations.
- Remove: endless engagement-only ranking.
- AI: explains recommendations and reduces unsafe loops.
- Glass: mode selector and explanation controls only.
- Apple-likely approve: user agency. Reject: opaque addictive loops.
- Performance: fixed control strip, solid results.
- Accessibility: mode changes announced.
- Platforms: iPad split browse/detail.
- Simplicity: mode first, recommendations second.

### Creator Tools

- Fit: adaptive density, composer glass, AI-native editing.
- Evolve: toolbars expand only when creating.
- Remove: always-visible advanced controls.
- AI: rewrite, claim context, media integrity, and source prompts.
- Glass: composer toolbar and review sheets only.
- Apple-likely approve: progressive disclosure. Reject: overloaded AI panels.
- Performance: compact controls, no card-wide glass.
- Accessibility: edit actions have clear labels.
- Platforms: iPad power layout and landscape editing.
- Simplicity: write first; tools appear with intent.

### Study Modes

- Fit: vanishing chrome, reading focus, semantic atmosphere.
- Evolve: controls disappear during reading and return on pause/selection.
- Remove: persistent controls covering scripture or notes.
- AI: contextual verse explanation and cross-reference.
- Glass: selection tray and bottom actions.
- Apple-likely approve: Reader-like focus. Reject: noisy AI overlays.
- Performance: no animated blur while scrolling text.
- Accessibility: Dynamic Type and contrast override all materials.
- Platforms: iPad reading columns, visionOS layered study.
- Simplicity: text remains primary.

### Church Experience

- Fit: temporal interfaces, ambient motion, low-noise live states.
- Evolve: live sermon controls into calm status/action surfaces.
- Remove: constant glow/pulse except active recording/live state.
- AI: live notes, translation, and summaries as optional aids.
- Glass: live control dock and media chrome.
- Apple-likely approve: clear live status. Reject: distracting effects during worship.
- Performance: static progress edges.
- Accessibility: live status announced and readable.
- Platforms: Apple TV-style passive mode, iPad notes, wearable reminders.
- Simplicity: worship and community remain first.

### Search

- Fit: AI-native search and intentive controls.
- Evolve: search from text results into safe, sourced answers and filters.
- Remove: broad AI answer cards without source context.
- AI: embedded ranking, summaries, and source requirements.
- Glass: search bar and filter chips only.
- Apple-likely approve: native search patterns. Reject: unsourced authoritative claims.
- Performance: fixed header; results solid.
- Accessibility: filters are real controls.
- Platforms: iPad sidebar search and spotlight-style entry.
- Simplicity: query, result, source.

### Notifications

- Fit: temporal interfaces and humane computing.
- Evolve: notification pacing and safe previews.
- Remove: harmful previews, urgency manipulation, pile-on nudges.
- AI: classifies preview safety and notification grouping.
- Glass: in-app notification tray only.
- Apple-likely approve: privacy-preserving previews. Reject: sensitive content exposed on lock screen.
- Performance: no persistent blur layers.
- Accessibility: clear status text.
- Platforms: wearable-safe summaries.
- Simplicity: fewer, safer notifications.

### Composer

- Fit: composer glass capsule, emotional check-in, claim context.
- Evolve: safety prompts into morphing bottom sheets.
- Remove: publish buttons that bypass backend safety gates.
- AI: rewrite, source, reflection conversion, and integrity checks.
- Glass: composer capsule and safety sheet chrome.
- Apple-likely approve: native text entry and clear prompts. Reject: hidden moderation.
- Performance: one composer surface, one sheet surface.
- Accessibility: prompts use plain language and large tap targets.
- Platforms: iPad expanded editor, landscape toolbar, handoff drafts.
- Simplicity: compose normally; interventions are contextual.

### Navigation

- Fit: vanishing chrome and scroll-aware compression.
- Evolve: tabs/header into floating adaptive control layer.
- Remove: stacked translucent bars.
- AI: navigation can surface recent intent without adding assistant chrome.
- Glass: navigation only, one layer.
- Apple-likely approve: system-like navigation. Reject: hard-to-read translucent stacks.
- Performance: fixed material, opacity swaps only.
- Accessibility: tab labels remain available.
- Platforms: iPad sidebars, visionOS ornaments, landscape compact chrome.
- Simplicity: location is always clear.

## Implementation Checklist

- Is the glass surface a control layer? If no, use a solid surface.
- Is another glass surface directly behind or inside it? If yes, remove one layer.
- Does Reduce Transparency produce a solid readable fallback? If no, fix it.
- Does Reduce Motion avoid morphing/bounce? If no, fix it.
- Is the text readable at large Dynamic Type and increased contrast? If no, fix it.
- Does the interaction work without AI? If no, fix the core action.
- Does backend safety still enforce the decision? If no, do not ship the UI.
